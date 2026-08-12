import Foundation

public enum EffectiveLanguage: Equatable, Sendable {
    case english
    case simplifiedChinese
    case systemDefault(String)
}

public enum ChineseEligibility: Equatable, Sendable {
    case available
    case systemLanguageNotSimplifiedChinese(String)
    case missingResource
}

public struct LanguageState: Equatable, Sendable {
    public let effective: EffectiveLanguage
    public let chineseEligibility: ChineseEligibility
    public let markerExists: Bool

    public init(
        effective: EffectiveLanguage,
        chineseEligibility: ChineseEligibility,
        markerExists: Bool
    ) {
        self.effective = effective
        self.chineseEligibility = chineseEligibility
        self.markerExists = markerExists
    }
}

public protocol PreferredLanguageProviding: Sendable {
    var preferredLanguages: [String] { get }
}

public struct SystemPreferredLanguageProvider: PreferredLanguageProviding {
    public init() {}

    public var preferredLanguages: [String] {
        Locale.preferredLanguages
    }
}

public protocol LanguageStateDetecting: Sendable {
    func detect(for installation: AEInstallation, markerURL: URL) -> LanguageState
}

public struct LanguageStateDetector: LanguageStateDetecting, Sendable {
    public static let emptyPreferredLanguageFallback = "en"

    private let preferredLanguageProvider: any PreferredLanguageProviding
    private let markerExistsProvider: @Sendable (URL) -> Bool

    public init(
        preferredLanguageProvider: any PreferredLanguageProviding = SystemPreferredLanguageProvider(),
        markerExists: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    ) {
        self.preferredLanguageProvider = preferredLanguageProvider
        self.markerExistsProvider = markerExists
    }

    public func detect(for installation: AEInstallation, markerURL: URL) -> LanguageState {
        let firstPreferredLanguage = preferredLanguageProvider.preferredLanguages.first
            ?? Self.emptyPreferredLanguageFallback
        let markerExists = markerExistsProvider(markerURL)
        let chineseEligibility = chineseEligibility(
            for: installation,
            firstPreferredLanguage: firstPreferredLanguage
        )

        let effective: EffectiveLanguage
        if markerExists {
            effective = .english
        } else if chineseEligibility == .available {
            effective = .simplifiedChinese
        } else {
            effective = .systemDefault(firstPreferredLanguage)
        }

        return LanguageState(
            effective: effective,
            chineseEligibility: chineseEligibility,
            markerExists: markerExists
        )
    }

    private func chineseEligibility(
        for installation: AEInstallation,
        firstPreferredLanguage: String
    ) -> ChineseEligibility {
        guard installation.availableLocales.contains(.simplifiedChinese) else {
            return .missingResource
        }
        guard Self.isSimplifiedChinese(firstPreferredLanguage) else {
            return .systemLanguageNotSimplifiedChinese(firstPreferredLanguage)
        }
        return .available
    }

    private static func isSimplifiedChinese(_ language: String) -> Bool {
        switch language {
        case "zh-Hans", "zh_CN", "zh-Hans-CN":
            true
        default:
            false
        }
    }
}
