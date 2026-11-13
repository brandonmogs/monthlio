import Foundation
import SwiftData

enum RestoreMode: Equatable {
    /// Delete everything, then load the backup.
    case replace
    /// Add what's missing, keep what's already here.
    case merge
}

struct RestoreSummary: Equatable {
    var expensesAdded = 0
    var expensesSkipped = 0
    var budgetsAdded = 0
    var ratesAdded = 0
    var snapshotsAdded = 0
}

/// Full JSON backup and restore over the SwiftData store.
///
/// Reminders and the app lock are deliberately not restored: they depend on
/// this device's permissions and biometrics, and restoring `requireAuthentication`
/// onto a device with no passcode would lock the user out.
@MainActor
enum BackupService {
    static func document(from context: ModelContext, appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, now: Date = .now) throws -> BackupDocument {
        let settings = AppSettings.existing(in: context).map {
            BackupDocument.SettingsRecord(
                monthlyIncome: $0.monthlyIncome.backupString,
                baseCurrencyCode: $0.baseCurrencyCode,
                notificationsEnabled: $0.notificationsEnabled,
                requireAuthentication: $0.requireAuthentication
            )
        }
        let expenses = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.createdAt)])).map {
            BackupDocument.ExpenseRecord(
                id: $0.id,
                name: $0.name,
                amount: $0.amount.backupString,
                currencyCode: $0.currencyCode,
                category: $0.categoryRaw,
                cadence: $0.cadenceRaw,
                dueDay: $0.dueDay,
                chargeDate: $0.chargeDate,
                isActive: $0.isActive,
                notes: $0.notes,
                createdAt: $0.createdAt,
                previousAmount: $0.previousAmount?.backupString,
                amountChangedAt: $0.amountChangedAt,
                colorHex: $0.colorHex,
                reminderDate: $0.reminderDate
            )
        }
        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>(sortBy: [SortDescriptor(\.categoryRaw)])).map {
            BackupDocument.BudgetRecord(category: $0.categoryRaw, cap: $0.cap.backupString)
        }
        let rates = try context.fetch(FetchDescriptor<ExchangeRate>(sortBy: [SortDescriptor(\.code)])).map {
            BackupDocument.ExchangeRateRecord(code: $0.code, rateToBase: $0.rateToBase.backupString, baseCode: $0.baseCode, updatedAt: $0.updatedAt)
        }
        // A month from before months knew their currency was recorded in the
        // base of its day; the base at export is the best account of that.
        let baseAtExport = AppSettings.existing(in: context)?.resolvedBaseCurrencyCode ?? CurrencyFormat.baseCode
        let snapshots = try context.fetch(FetchDescriptor<MonthSnapshot>(sortBy: [SortDescriptor(\.key)])).map {
            BackupDocument.SnapshotRecord(year: $0.year, month: $0.month, total: $0.total.backupString, updatedAt: $0.updatedAt, currencyCode: $0.currencyCode.isEmpty ? baseAtExport : $0.currencyCode)
        }
        return BackupDocument(
            exportedAt: now,
            appVersion: appVersion,
            settings: settings,
            expenses: expenses,
            budgets: budgets,
            exchangeRates: rates,
            snapshots: snapshots
        )
    }

    static func data(from context: ModelContext) throws -> Data {
        try BackupDocument.makeEncoder().encode(document(from: context))
    }

    static func decode(_ data: Data) throws -> BackupDocument {
        let document: BackupDocument
        do {
            document = try BackupDocument.makeDecoder().decode(BackupDocument.self, from: data)
        } catch {
            // A JSON file that decodes as something else is "not a backup";
            // anything that isn't JSON at all is unreadable.
            if (try? JSONSerialization.jsonObject(with: data)) != nil { throw BackupError.notABackup }
            throw BackupError.unreadable
        }
        guard document.format == BackupDocument.format else { throw BackupError.notABackup }
        guard document.version <= BackupDocument.currentVersion else { throw BackupError.unsupportedVersion(document.version) }
        return document
    }

    /// True when nothing has been entered yet, so a restore can skip the
    /// replace-or-merge question.
    static func isEmpty(_ context: ModelContext) -> Bool {
        let expenses = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0
        let budgets = (try? context.fetchCount(FetchDescriptor<CategoryBudget>())) ?? 0
        let rates = (try? context.fetchCount(FetchDescriptor<ExchangeRate>())) ?? 0
        let snapshots = (try? context.fetchCount(FetchDescriptor<MonthSnapshot>())) ?? 0
        let settings = AppSettings.existing(in: context)
        let income = settings?.monthlyIncome ?? 0
        let chosenBase = !(settings?.baseCurrencyCode.isEmpty ?? true)
        return expenses == 0 && budgets == 0 && rates == 0 && snapshots == 0 && income == 0 && !chosenBase
    }

    /// Replace rewrites the rows the backup knows rather than deleting and
    /// re-inserting them: on a synced store a delete-then-insert of the same
    /// identity reaches other devices as an original beside a restored copy,
    /// each device picks a survivor, and the deletes sync. Only rows the
    /// backup doesn't know are removed. Merge adds what is missing and keeps
    /// what is here.
    @discardableResult
    static func restore(_ document: BackupDocument, into context: ModelContext, mode: RestoreMode) throws -> RestoreSummary {
        var summary = RestoreSummary()
        let replacing = mode == .replace

        // Expenses, by id. A backup that itself carries a duplicated row
        // restores it once; duplicates already in the store collapse too.
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        var expenseByID: [UUID: Expense] = [:]
        for expense in expenses where expenseByID[expense.id] == nil { expenseByID[expense.id] = expense }
        var seenExpenses = Set<UUID>()
        for record in document.expenses {
            guard seenExpenses.insert(record.id).inserted,
                  let amount = Decimal(backupString: record.amount), MoneyLimits.isValidAmount(amount) else {
                summary.expensesSkipped += 1
                continue
            }
            let name = MoneyLimits.clampedName(record.name)
            guard !name.isEmpty else { summary.expensesSkipped += 1; continue }
            if let existing = expenseByID[record.id] {
                guard replacing else { summary.expensesSkipped += 1; continue }
                apply(record, name: name, amount: amount, to: existing)
            } else {
                let expense = Expense(id: record.id, name: name, amount: amount, category: .other)
                apply(record, name: name, amount: amount, to: expense)
                context.insert(expense)
            }
            summary.expensesAdded += 1
        }
        if replacing {
            for expense in expenses where !seenExpenses.contains(expense.id) || expenseByID[expense.id] !== expense {
                context.delete(expense)
            }
        }

        // Budgets, by category.
        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>())
        var budgetByCategory: [String: CategoryBudget] = [:]
        for budget in budgets where budgetByCategory[budget.categoryRaw] == nil { budgetByCategory[budget.categoryRaw] = budget }
        var seenBudgets = Set<String>()
        for record in document.budgets {
            guard let category = ExpenseCategory(rawValue: record.category),
                  let cap = Decimal(backupString: record.cap), MoneyLimits.isValidAmount(cap),
                  seenBudgets.insert(record.category).inserted else { continue }
            if let existing = budgetByCategory[record.category] {
                guard replacing else { continue }
                if existing.cap != cap { existing.cap = cap }
            } else {
                context.insert(CategoryBudget(category: category, cap: cap))
            }
            summary.budgetsAdded += 1
        }
        if replacing {
            for budget in budgets where !seenBudgets.contains(budget.categoryRaw) || budgetByCategory[budget.categoryRaw] !== budget {
                context.delete(budget)
            }
        }

        // Exchange rates, by currency and base.
        let rates = try context.fetch(FetchDescriptor<ExchangeRate>())
        var rateByKey: [String: ExchangeRate] = [:]
        for rate in rates where rateByKey["\(rate.code)/\(rate.baseCode)"] == nil { rateByKey["\(rate.code)/\(rate.baseCode)"] = rate }
        var seenRates = Set<String>()
        for record in document.exchangeRates {
            let key = "\(record.code)/\(record.baseCode)"
            guard let rate = Decimal(backupString: record.rateToBase), MoneyLimits.isValidRate(rate),
                  seenRates.insert(key).inserted else { continue }
            if let existing = rateByKey[key] {
                guard replacing else { continue }
                if existing.rateToBase != rate { existing.rateToBase = rate }
                if existing.updatedAt != record.updatedAt { existing.updatedAt = record.updatedAt }
            } else {
                context.insert(ExchangeRate(code: record.code, rateToBase: rate, baseCode: record.baseCode, updatedAt: record.updatedAt))
            }
            summary.ratesAdded += 1
        }
        if replacing {
            for rate in rates where !seenRates.contains("\(rate.code)/\(rate.baseCode)") || rateByKey["\(rate.code)/\(rate.baseCode)"] !== rate {
                context.delete(rate)
            }
        }

        // Month history, by month key. A record without a currency comes
        // from a backup made before months knew theirs: the backup's base.
        let backupBase = document.settings?.baseCurrencyCode ?? ""
        let snapshots = try context.fetch(FetchDescriptor<MonthSnapshot>())
        var snapshotByKey: [String: MonthSnapshot] = [:]
        for snapshot in snapshots where snapshotByKey[snapshot.key] == nil { snapshotByKey[snapshot.key] = snapshot }
        var seenSnapshots = Set<String>()
        for record in document.snapshots {
            guard (1...12).contains(record.month),
                  let total = Decimal(backupString: record.total), MoneyLimits.isValidOrZero(total) else { continue }
            let key = MonthSnapshot.key(year: record.year, month: record.month)
            guard seenSnapshots.insert(key).inserted else { continue }
            let currency = record.currencyCode ?? backupBase
            if let existing = snapshotByKey[key] {
                guard replacing else { continue }
                if existing.total != total { existing.total = total }
                if existing.updatedAt != record.updatedAt { existing.updatedAt = record.updatedAt }
                if existing.currencyCode != currency { existing.currencyCode = currency }
            } else {
                context.insert(MonthSnapshot(year: record.year, month: record.month, total: total, updatedAt: record.updatedAt, currencyCode: currency))
            }
            summary.snapshotsAdded += 1
        }
        if replacing {
            for snapshot in snapshots where !seenSnapshots.contains(snapshot.key) || snapshotByKey[snapshot.key] !== snapshot {
                context.delete(snapshot)
            }
        }

        if let record = document.settings {
            let settings = AppSettings.current(in: context)
            if let income = Decimal(backupString: record.monthlyIncome), MoneyLimits.isValidOrZero(income),
               mode == .replace || settings.monthlyIncome == 0 {
                settings.monthlyIncome = income
            }
            if mode == .replace || settings.baseCurrencyCode.isEmpty {
                settings.baseCurrencyCode = record.baseCurrencyCode
            }
        }

        try context.save()
        return summary
    }

    /// Writes a backup record into a row, touching only fields that differ
    /// so an unchanged row isn't marked modified (and re-exported to iCloud).
    private static func apply(_ record: BackupDocument.ExpenseRecord, name: String, amount: Decimal, to expense: Expense) {
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Expense, T>, _ value: T) {
            if expense[keyPath: keyPath] != value { expense[keyPath: keyPath] = value }
        }
        set(\.name, name)
        set(\.amount, amount)
        set(\.currencyCode, record.currencyCode)
        set(\.categoryRaw, (ExpenseCategory(rawValue: record.category) ?? .other).rawValue)
        set(\.cadenceRaw, (Cadence(rawValue: record.cadence) ?? .monthly).rawValue)
        set(\.dueDay, record.dueDay.flatMap { (1...31).contains($0) ? $0 : nil })
        set(\.chargeDate, record.chargeDate)
        set(\.isActive, record.isActive)
        set(\.notes, record.notes.map(MoneyLimits.clampedNotes).flatMap { $0.isEmpty ? nil : $0 })
        set(\.createdAt, record.createdAt)
        set(\.previousAmount, record.previousAmount.flatMap(Decimal.init(backupString:)))
        set(\.amountChangedAt, record.amountChangedAt)
        set(\.colorHex, ExpenseColor.canonicalHex(record.colorHex))
        set(\.reminderDate, record.reminderDate)
    }
}
