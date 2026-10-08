import Foundation

/// Versioned, self-describing JSON backup of everything the app stores.
/// Money is written as strings so no reader has to guess how a JSON number
/// was rounded; dates are ISO 8601. Enum values use their raw names.
struct BackupDocument: Codable, Equatable {
    static let format = "monthlio-backup"
    static let currentVersion = 1

    var format: String = BackupDocument.format
    var version: Int = BackupDocument.currentVersion
    var exportedAt: Date
    var appVersion: String?
    var settings: SettingsRecord?
    var expenses: [ExpenseRecord]
    var budgets: [BudgetRecord]
    var exchangeRates: [ExchangeRateRecord]
    var snapshots: [SnapshotRecord]

    struct SettingsRecord: Codable, Equatable {
        var monthlyIncome: String
        var baseCurrencyCode: String
        var notificationsEnabled: Bool
        var requireAuthentication: Bool
    }

    struct ExpenseRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var amount: String
        var currencyCode: String
        var category: String
        var cadence: String
        var dueDay: Int?
        var chargeDate: Date?
        var isActive: Bool
        var notes: String?
        var createdAt: Date
        var previousAmount: String?
        var amountChangedAt: Date?
        /// "#RRGGBB"; absent in backups from before 1.4.
        var colorHex: String?
        /// The expense's own notification; absent in backups from before 1.5.
        var reminderDate: Date?
    }

    struct BudgetRecord: Codable, Equatable {
        var category: String
        var cap: String
    }

    struct ExchangeRateRecord: Codable, Equatable {
        var code: String
        var rateToBase: String
        var baseCode: String
        var updatedAt: Date
    }

    struct SnapshotRecord: Codable, Equatable {
        var year: Int
        var month: Int
        var total: String
        var updatedAt: Date
    }

    /// ISO 8601 with fractional seconds, so rows created in the same second
    /// keep their order after a restore. Files from before this read fine:
    /// the decoder accepts whole seconds too.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }

    /// Filename like "Monthlio Backup 2026-09-24.json".
    static func fileName(for date: Date = .now) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        return "Monthlio Backup \(day).json"
    }
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case unsupportedVersion(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notABackup:
            String(localized: "That file isn't a Monthlio backup.")
        case .unsupportedVersion(let version):
            String(localized: "This backup was made by a newer version of Monthlio (format \(version)). Update the app to restore it.")
        case .unreadable:
            String(localized: "The file couldn't be read.")
        }
    }
}

extension Decimal {
    /// Locale-independent text, e.g. "1500" or "15.49".
    var backupString: String { "\(self)" }

    init?(backupString: String) {
        guard let value = Decimal(string: backupString.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX")),
              value.isFinite, !value.isNaN else { return nil }
        self = value
    }
}
