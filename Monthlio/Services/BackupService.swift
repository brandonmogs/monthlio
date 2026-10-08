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
        let snapshots = try context.fetch(FetchDescriptor<MonthSnapshot>(sortBy: [SortDescriptor(\.key)])).map {
            BackupDocument.SnapshotRecord(year: $0.year, month: $0.month, total: $0.total.backupString, updatedAt: $0.updatedAt)
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

    @discardableResult
    static func restore(_ document: BackupDocument, into context: ModelContext, mode: RestoreMode) throws -> RestoreSummary {
        var summary = RestoreSummary()

        if mode == .replace {
            // One object at a time: store-level batch deletes are not mirrored
            // to CloudKit, so they would come back from other devices.
            for expense in try context.fetch(FetchDescriptor<Expense>()) { context.delete(expense) }
            for budget in try context.fetch(FetchDescriptor<CategoryBudget>()) { context.delete(budget) }
            for rate in try context.fetch(FetchDescriptor<ExchangeRate>()) { context.delete(rate) }
            for snapshot in try context.fetch(FetchDescriptor<MonthSnapshot>()) { context.delete(snapshot) }
        }

        // Ids already in the store, plus each id as it is restored, so a
        // backup that itself carries a duplicated row restores it once.
        var existingIDs = Set(try context.fetch(FetchDescriptor<Expense>()).map(\.id))
        for record in document.expenses {
            guard existingIDs.insert(record.id).inserted,
                  let amount = Decimal(backupString: record.amount), MoneyLimits.isValidAmount(amount) else {
                summary.expensesSkipped += 1
                continue
            }
            let name = MoneyLimits.clampedName(record.name)
            guard !name.isEmpty else { summary.expensesSkipped += 1; continue }
            let expense = Expense(
                id: record.id,
                name: name,
                amount: amount,
                currencyCode: record.currencyCode,
                category: ExpenseCategory(rawValue: record.category) ?? .other,
                cadence: Cadence(rawValue: record.cadence) ?? .monthly,
                dueDay: record.dueDay.flatMap { (1...31).contains($0) ? $0 : nil },
                chargeDate: record.chargeDate,
                isActive: record.isActive,
                notes: record.notes.map(MoneyLimits.clampedNotes).flatMap { $0.isEmpty ? nil : $0 },
                createdAt: record.createdAt
            )
            expense.previousAmount = record.previousAmount.flatMap(Decimal.init(backupString:))
            expense.amountChangedAt = record.amountChangedAt
            expense.colorHex = ExpenseColor.canonicalHex(record.colorHex)
            expense.reminderDate = record.reminderDate
            context.insert(expense)
            summary.expensesAdded += 1
        }

        let existingBudgets = Set(try context.fetch(FetchDescriptor<CategoryBudget>()).map(\.categoryRaw))
        for record in document.budgets {
            guard !existingBudgets.contains(record.category),
                  let category = ExpenseCategory(rawValue: record.category),
                  let cap = Decimal(backupString: record.cap), MoneyLimits.isValidAmount(cap) else { continue }
            context.insert(CategoryBudget(category: category, cap: cap))
            summary.budgetsAdded += 1
        }

        let existingRates = Set(try context.fetch(FetchDescriptor<ExchangeRate>()).map { "\($0.code)/\($0.baseCode)" })
        for record in document.exchangeRates {
            guard !existingRates.contains("\(record.code)/\(record.baseCode)"),
                  let rate = Decimal(backupString: record.rateToBase), MoneyLimits.isValidRate(rate) else { continue }
            context.insert(ExchangeRate(code: record.code, rateToBase: rate, baseCode: record.baseCode, updatedAt: record.updatedAt))
            summary.ratesAdded += 1
        }

        let existingSnapshots = Set(try context.fetch(FetchDescriptor<MonthSnapshot>()).map(\.key))
        for record in document.snapshots {
            guard (1...12).contains(record.month), !existingSnapshots.contains(MonthSnapshot.key(year: record.year, month: record.month)),
                  let total = Decimal(backupString: record.total), MoneyLimits.isValidOrZero(total) else { continue }
            context.insert(MonthSnapshot(year: record.year, month: record.month, total: total, updatedAt: record.updatedAt))
            summary.snapshotsAdded += 1
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
}
