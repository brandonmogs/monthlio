import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "store")

extension ModelContext {
    /// Saves, and on failure rolls the pending changes back, logs the error
    /// and returns it so the caller can tell the user, instead of a failed
    /// save passing for a success behind a haptic. Nil means saved.
    @discardableResult
    func saveReporting(_ what: StaticString) -> Error? {
        do {
            try save()
            return nil
        } catch {
            log.error("Couldn't save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            rollback()
            return error
        }
    }
}
