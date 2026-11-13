import Foundation

/// Where the app points people: one place, so the paywall, Settings and
/// the README agree.
enum SupportLinks {
    static let privacyPolicy = URL(string: "https://brandonmogs.github.io/monthlio-privacy/")!
    /// Issues on the public privacy repository (the app's own repository is
    /// private); the App Store listing's support URL should match.
    static let support = URL(string: "https://github.com/brandonmogs/monthlio-privacy/issues")!

    /// "1.5 (10)" from the bundle.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
