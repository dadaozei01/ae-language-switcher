import Foundation

public enum AELocale: String, Hashable, Sendable {
    case englishUS = "en_US"
    case simplifiedChinese = "zh_CN"
}

public struct AEInstallation: Identifiable, Equatable, Sendable {
    public var id: URL { appURL }
    public let displayName: String
    public let version: String
    public let build: String
    public let bundleIdentifier: String
    public let appURL: URL
    public let availableLocales: Set<AELocale>

    public init(
        displayName: String,
        version: String,
        build: String,
        bundleIdentifier: String,
        appURL: URL,
        availableLocales: Set<AELocale>
    ) {
        self.displayName = displayName
        self.version = version
        self.build = build
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.availableLocales = availableLocales
    }
}
