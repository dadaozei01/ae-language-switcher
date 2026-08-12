import Foundation
import XCTest
@testable import AELanguageSwitcherCore

final class AfterEffectsScannerTests: XCTestCase {
    func testScanReturnsFormalInstallationsSortedByNumericVersionWithBundleMetadataAndLocales() throws {
        let applicationsURL = try makeTemporaryApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: applicationsURL) }

        _ = try makeAppBundle(
            in: applicationsURL,
            name: "Adobe After Effects 9.app",
            displayName: "After Effects 9",
            version: "9.10",
            build: "9.10.123",
            locales: ["zh_CN"]
        )
        let newestURL = try makeAppBundle(
            in: applicationsURL,
            name: "Adobe After Effects 2025.app",
            displayName: "After Effects 2025",
            version: "25.1.0",
            build: "25.1.0.42",
            locales: ["zh_CN", "en_US"]
        )

        let installations = try AfterEffectsScanner(applicationsURL: applicationsURL).scan()

        XCTAssertEqual(installations.map(\.version), ["25.1.0", "9.10"])
        XCTAssertEqual(installations.first?.displayName, "After Effects 2025")
        XCTAssertEqual(installations.first?.build, "25.1.0.42")
        XCTAssertEqual(installations.first?.bundleIdentifier, "com.adobe.AfterEffects.application")
        XCTAssertEqual(
            installations.first?.appURL.resolvingSymlinksInPath(),
            newestURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(installations.first?.availableLocales, [.simplifiedChinese, .englishUS])
        XCTAssertEqual(installations.last?.availableLocales, [.simplifiedChinese])
    }

    func testScanFindsBetaAppsAtTheSecondDirectoryLevel() throws {
        let applicationsURL = try makeTemporaryApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: applicationsURL) }
        let betaFolder = applicationsURL.appendingPathComponent("Adobe", isDirectory: true)
        try FileManager.default.createDirectory(at: betaFolder, withIntermediateDirectories: true)
        let betaURL = try makeAppBundle(
            in: betaFolder,
            name: "Adobe After Effects Beta.app",
            displayName: "After Effects Beta",
            version: "26.0.0",
            build: "26.0.0x1"
        )

        let installations = try AfterEffectsScanner(applicationsURL: applicationsURL).scan()

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installations.first?.displayName, "After Effects Beta")
        XCTAssertEqual(installations.first?.appURL.resolvingSymlinksInPath(), betaURL.resolvingSymlinksInPath())
    }

    func testScanRejectsRenderEngineAndUnexpectedBundleIdentifiers() throws {
        let applicationsURL = try makeTemporaryApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: applicationsURL) }
        _ = try makeAppBundle(
            in: applicationsURL,
            name: "Adobe After Effects 2025.app",
            displayName: "After Effects 2025",
            version: "25.0",
            build: "25.0.1"
        )
        _ = try makeAppBundle(
            in: applicationsURL,
            name: "Adobe After Effects Render Engine 2025.app",
            displayName: "After Effects Render Engine 2025",
            version: "25.0",
            build: "25.0.1"
        )
        _ = try makeAppBundle(
            in: applicationsURL,
            name: "Adobe After Effects Impostor.app",
            displayName: "After Effects Impostor",
            version: "25.0",
            build: "25.0.1",
            bundleIdentifier: "com.example.aftereffects"
        )

        let installations = try AfterEffectsScanner(applicationsURL: applicationsURL).scan()

        XCTAssertEqual(installations.map(\.displayName), ["After Effects 2025"])
    }

    func testScanOmitsMalformedBundlesAndAppsDeeperThanSecondDirectoryLevel() throws {
        let applicationsURL = try makeTemporaryApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: applicationsURL) }
        let malformedURL = applicationsURL.appendingPathComponent("Adobe After Effects Broken.app", isDirectory: true)
        try FileManager.default.createDirectory(at: malformedURL, withIntermediateDirectories: true)

        let deepFolder = applicationsURL.appendingPathComponent("Adobe/2025/Beta", isDirectory: true)
        try FileManager.default.createDirectory(at: deepFolder, withIntermediateDirectories: true)
        _ = try makeAppBundle(
            in: deepFolder,
            name: "Adobe After Effects Beta.app",
            displayName: "Too Deep",
            version: "26.0",
            build: "26.0.1"
        )

        let installations = try AfterEffectsScanner(applicationsURL: applicationsURL).scan()

        XCTAssertTrue(installations.isEmpty)
    }
}
