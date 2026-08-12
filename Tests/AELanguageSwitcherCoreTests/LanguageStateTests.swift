import Foundation
import XCTest
@testable import AELanguageSwitcherCore

final class LanguageStateTests: XCTestCase {
    func testDetectDerivesDeterministicLanguageState() {
        let installationWithChinese = makeInstallation(locales: [.englishUS, .simplifiedChinese])
        let installationWithoutChinese = makeInstallation(locales: [.englishUS])
        let cases: [(name: String, installation: AEInstallation, preferredLanguages: [String], markerExists: Bool, expected: LanguageState)] = [
            (
                name: "marker takes precedence over eligible simplified Chinese",
                installation: installationWithChinese,
                preferredLanguages: ["zh-Hans"],
                markerExists: true,
                expected: LanguageState(
                    effective: .english,
                    chineseEligibility: .available,
                    markerExists: true
                )
            ),
            (
                name: "zh-Hans selects simplified Chinese",
                installation: installationWithChinese,
                preferredLanguages: ["zh-Hans"],
                markerExists: false,
                expected: LanguageState(
                    effective: .simplifiedChinese,
                    chineseEligibility: .available,
                    markerExists: false
                )
            ),
            (
                name: "zh_CN selects simplified Chinese",
                installation: installationWithChinese,
                preferredLanguages: ["zh_CN"],
                markerExists: false,
                expected: LanguageState(
                    effective: .simplifiedChinese,
                    chineseEligibility: .available,
                    markerExists: false
                )
            ),
            (
                name: "zh-Hans-CN selects simplified Chinese",
                installation: installationWithChinese,
                preferredLanguages: ["zh-Hans-CN"],
                markerExists: false,
                expected: LanguageState(
                    effective: .simplifiedChinese,
                    chineseEligibility: .available,
                    markerExists: false
                )
            ),
            (
                name: "English remains the exact system default",
                installation: installationWithChinese,
                preferredLanguages: ["en-US"],
                markerExists: false,
                expected: LanguageState(
                    effective: .systemDefault("en-US"),
                    chineseEligibility: .systemLanguageNotSimplifiedChinese("en-US"),
                    markerExists: false
                )
            ),
            (
                name: "missing Chinese resource prevents simplified Chinese",
                installation: installationWithoutChinese,
                preferredLanguages: ["zh-Hans"],
                markerExists: false,
                expected: LanguageState(
                    effective: .systemDefault("zh-Hans"),
                    chineseEligibility: .missingResource,
                    markerExists: false
                )
            ),
            (
                name: "zh-Hant is not simplified Chinese",
                installation: installationWithChinese,
                preferredLanguages: ["zh-Hant"],
                markerExists: false,
                expected: LanguageState(
                    effective: .systemDefault("zh-Hant"),
                    chineseEligibility: .systemLanguageNotSimplifiedChinese("zh-Hant"),
                    markerExists: false
                )
            ),
            (
                name: "zh-TW is not simplified Chinese",
                installation: installationWithChinese,
                preferredLanguages: ["zh-TW"],
                markerExists: false,
                expected: LanguageState(
                    effective: .systemDefault("zh-TW"),
                    chineseEligibility: .systemLanguageNotSimplifiedChinese("zh-TW"),
                    markerExists: false
                )
            ),
            (
                name: "an empty preference list uses a stable fallback",
                installation: installationWithChinese,
                preferredLanguages: [],
                markerExists: false,
                expected: LanguageState(
                    effective: .systemDefault("en"),
                    chineseEligibility: .systemLanguageNotSimplifiedChinese("en"),
                    markerExists: false
                )
            )
        ]

        for testCase in cases {
            let markerExists = testCase.markerExists
            let detector = LanguageStateDetector(
                preferredLanguageProvider: PreferredLanguagesStub(testCase.preferredLanguages),
                markerExists: { _ in markerExists }
            )

            XCTAssertEqual(
                detector.detect(
                    for: testCase.installation,
                    markerURL: URL(fileURLWithPath: "/controlled-test-marker")
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    private func makeInstallation(locales: Set<AELocale>) -> AEInstallation {
        AEInstallation(
            displayName: "After Effects",
            version: "25.0",
            build: "1",
            bundleIdentifier: "com.adobe.AfterEffects.application",
            appURL: URL(fileURLWithPath: "/Applications/Adobe After Effects.app"),
            availableLocales: locales
        )
    }
}

private struct PreferredLanguagesStub: PreferredLanguageProviding {
    let preferredLanguages: [String]

    init(_ preferredLanguages: [String]) {
        self.preferredLanguages = preferredLanguages
    }
}
