import Foundation
import XCTest
@testable import AELanguageSwitcherCore

final class LanguageSwitcherTests: XCTestCase {
    private var documentsURL: URL!
    private var markerURL: URL!

    override func setUpWithError() throws {
        documentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        markerURL = documentsURL.appendingPathComponent("ae_force_english.txt")
    }

    override func tearDownWithError() throws {
        if let documentsURL {
            try? FileManager.default.removeItem(at: documentsURL.deletingLastPathComponent())
        }
    }

    func testEnglishCreatesTheMarkerThatAfterEffectsRecognizes() throws {
        try switcher().switch(to: .english, chineseEligibility: .available)

        XCTAssertEqual(try fileSize(at: markerURL), 0)
    }

    func testSimplifiedChineseRemovesZeroByteMarker() throws {
        try makeEmptyFile(at: markerURL)

        try switcher().switch(to: .simplifiedChinese, chineseEligibility: .available)

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testEnglishDoesNotOverwriteExistingNonEmptyMarker() throws {
        let originalContents = Data("keep me".utf8)
        try originalContents.write(to: markerURL)

        try switcher().switch(to: .english, chineseEligibility: .available)

        XCTAssertEqual(try Data(contentsOf: markerURL), originalContents)
    }

    func testSimplifiedChineseRejectsNonEmptyMarker() throws {
        try Data("keep me".utf8).write(to: markerURL)

        XCTAssertThrowsError(
            try switcher().switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            XCTAssertEqual(error as? LanguageSwitchError, .nonEmptyMarker)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testEnglishRejectsDirectoryMarker() throws {
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try switcher().switch(to: .english, chineseEligibility: .available)
        ) { error in
            XCTAssertEqual(error as? LanguageSwitchError, .unsafeMarkerType)
        }
    }

    func testSimplifiedChineseRejectsDirectoryMarker() throws {
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try switcher().switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            XCTAssertEqual(error as? LanguageSwitchError, .unsafeMarkerType)
        }
    }

    func testEnglishRejectsSymbolicLinkMarker() throws {
        let targetURL = documentsURL.appendingPathComponent("target")
        try Data("protected".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: markerURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(
            try switcher().switch(to: .english, chineseEligibility: .available)
        ) { error in
            XCTAssertEqual(error as? LanguageSwitchError, .unsafeMarkerType)
        }
        XCTAssertEqual(try? Data(contentsOf: targetURL), Data("protected".utf8))
    }

    func testSimplifiedChineseRejectsSymbolicLinkMarker() throws {
        let targetURL = documentsURL.appendingPathComponent("target")
        try makeEmptyFile(at: targetURL)
        try FileManager.default.createSymbolicLink(at: markerURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(
            try switcher().switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            XCTAssertEqual(error as? LanguageSwitchError, .unsafeMarkerType)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testSimplifiedChineseRejectsUnavailableEligibility() throws {
        try makeEmptyFile(at: markerURL)
        let eligibility = ChineseEligibility.systemLanguageNotSimplifiedChinese("en-US")

        XCTAssertThrowsError(
            try switcher().switch(to: .simplifiedChinese, chineseEligibility: eligibility)
        ) { error in
            XCTAssertEqual(error as? LanguageSwitchError, .chineseUnavailable(eligibility))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testSimplifiedChineseDoesNotDeleteSubstitutedNonEmptyMarker() throws {
        try makeEmptyFile(at: markerURL)
        let markerURL = markerURL!
        let replacement = Data("do not delete".utf8)
        let switcher = LanguageSwitcher(markerURL: markerURL, beforeMarkerDeletion: {
            try! FileManager.default.removeItem(at: markerURL)
            try! replacement.write(to: markerURL)
        })

        XCTAssertThrowsError(
            try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: markerURL), replacement)
    }

    func testSimplifiedChineseDoesNotDeleteSubstitutedDirectory() throws {
        try makeEmptyFile(at: markerURL)
        let markerURL = markerURL!
        let switcher = LanguageSwitcher(markerURL: markerURL, beforeMarkerDeletion: {
            try! FileManager.default.removeItem(at: markerURL)
            try! FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)
        })

        XCTAssertThrowsError(
            try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSimplifiedChineseDoesNotDeleteSubstitutedSymbolicLink() throws {
        try makeEmptyFile(at: markerURL)
        let markerURL = markerURL!
        let targetURL = documentsURL.appendingPathComponent("replacement-target")
        try Data("protected".utf8).write(to: targetURL)
        let switcher = LanguageSwitcher(markerURL: markerURL, beforeMarkerDeletion: {
            try! FileManager.default.removeItem(at: markerURL)
            try! FileManager.default.createSymbolicLink(at: markerURL, withDestinationURL: targetURL)
        })

        XCTAssertThrowsError(
            try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: markerURL.path),
            targetURL.path
        )
        XCTAssertEqual(try Data(contentsOf: targetURL), Data("protected".utf8))
    }

    func testSimplifiedChineseRestoresNonEmptyMarkerSubstitutedAfterIdentityCheck() throws {
        try makeEmptyFile(at: markerURL)
        let markerURL = markerURL!
        let replacement = Data("do not delete".utf8)
        let switcher = LanguageSwitcher(markerURL: markerURL, beforeQuarantineRename: {
            try! FileManager.default.removeItem(at: markerURL)
            try! replacement.write(to: markerURL)
        })

        XCTAssertThrowsError(
            try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: markerURL), replacement)
    }

    func testSimplifiedChineseRestoresDirectorySubstitutedAfterIdentityCheck() throws {
        try makeEmptyFile(at: markerURL)
        let markerURL = markerURL!
        let switcher = LanguageSwitcher(markerURL: markerURL, beforeQuarantineRename: {
            try! FileManager.default.removeItem(at: markerURL)
            try! FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)
        })

        XCTAssertThrowsError(
            try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSimplifiedChineseRestoresSymbolicLinkSubstitutedAfterIdentityCheck() throws {
        try makeEmptyFile(at: markerURL)
        let markerURL = markerURL!
        let targetURL = documentsURL.appendingPathComponent("replacement-target-after-check")
        try Data("protected".utf8).write(to: targetURL)
        let switcher = LanguageSwitcher(markerURL: markerURL, beforeQuarantineRename: {
            try! FileManager.default.removeItem(at: markerURL)
            try! FileManager.default.createSymbolicLink(at: markerURL, withDestinationURL: targetURL)
        })

        XCTAssertThrowsError(
            try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: markerURL.path),
            targetURL.path
        )
        XCTAssertEqual(try Data(contentsOf: targetURL), Data("protected".utf8))
    }

    func testEnglishReportsFileOperationWhenParentIsMissing() {
        let missingParentMarker = documentsURL
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("ae_force_english.txt")

        XCTAssertThrowsError(
            try LanguageSwitcher(
                markerURL: missingParentMarker,
                clearApplicationLanguage: { _ in }
            ).switch(
                to: .english,
                chineseEligibility: .available
            )
        ) { error in
            guard case .fileOperation = error as? LanguageSwitchError else {
                return XCTFail("Expected fileOperation, got \(error)")
            }
        }
    }

    func testRepeatedEnglishIsIdempotent() throws {
        try switcher().switch(to: .english, chineseEligibility: .available)
        try switcher().switch(to: .english, chineseEligibility: .available)

        XCTAssertEqual(try fileSize(at: markerURL), 0)
    }

    func testRepeatedSimplifiedChineseWithoutMarkerIsIdempotentAfterEligibilitySucceeds() throws {
        try switcher().switch(to: .simplifiedChinese, chineseEligibility: .available)
        try switcher().switch(to: .simplifiedChinese, chineseEligibility: .available)

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    private func switcher() -> LanguageSwitcher {
        LanguageSwitcher(
            markerURL: markerURL,
            clearApplicationLanguage: { _ in }
        )
    }

    private func makeEmptyFile(at url: URL) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }

}
