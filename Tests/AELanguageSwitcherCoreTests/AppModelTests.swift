import Foundation
import XCTest
@testable import AELanguageSwitcherCore

@MainActor
final class AppModelTests: XCTestCase {
    func testPrimarySwitchTargetIsEnglishForSimplifiedChineseState() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: DetectorStub(states: [installation.id: .eligibleChinese])
        )

        model.refresh()

        XCTAssertEqual(model.primarySwitchTarget, .english)
    }

    func testPrimarySwitchTargetIsSimplifiedChineseForEnglishState() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let englishState = LanguageState(
            effective: .english,
            chineseEligibility: .available,
            markerExists: true
        )
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: DetectorStub(states: [installation.id: englishState])
        )

        model.refresh()

        XCTAssertEqual(model.primarySwitchTarget, .simplifiedChinese)
    }

    func testPrimarySwitchTargetIsNilBeforeRefresh() {
        let model = makeModel()

        XCTAssertNil(model.primarySwitchTarget)
    }

    func testPrimarySwitchTargetIsNilForSystemDefaultState() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let systemDefaultState = LanguageState(
            effective: .systemDefault("en-US"),
            chineseEligibility: .available,
            markerExists: false
        )
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: DetectorStub(states: [installation.id: systemDefaultState])
        )

        model.refresh()

        XCTAssertNil(model.primarySwitchTarget)
    }

    func testFirstRefreshSelectsHighestInstallationAndDerivesItsLanguageState() {
        let highest = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let older = makeInstallation(version: "25.0", path: "/Applications/AE 25.app")
        let expectedState = LanguageState(
            effective: .simplifiedChinese,
            chineseEligibility: .available,
            markerExists: false
        )
        let detector = DetectorStub(states: [highest.id: expectedState])
        let model = makeModel(
            scanner: ScannerStub(result: .success([highest, older])),
            detector: detector
        )

        model.refresh()

        XCTAssertEqual(model.installations, [highest, older])
        XCTAssertEqual(model.selectedInstallationID, highest.id)
        XCTAssertEqual(model.languageState, expectedState)
        XCTAssertEqual(detector.installationIDs, [highest.id])
        XCTAssertFalse(model.isBusy)
    }

    func testRefreshAlwaysSelectsNewHighestInstallationAndDerivesItsState() {
        let newest = makeInstallation(version: "27.0", path: "/Applications/AE 27.app")
        let selected = makeInstallation(version: "25.0", path: "/Applications/AE 25.app")
        let newestState = LanguageState(
            effective: .english,
            chineseEligibility: .available,
            markerExists: true
        )
        let scanner = ScannerStub(result: .success([selected]))
        let detector = DetectorStub(states: [newest.id: newestState])
        let model = makeModel(scanner: scanner, detector: detector)
        model.refresh()
        scanner.result = .success([newest, selected])

        model.refresh()

        XCTAssertEqual(model.selectedInstallationID, newest.id)
        XCTAssertEqual(model.languageState, newestState)
        XCTAssertEqual(detector.installationIDs, [selected.id, newest.id])
    }

    func testRefreshFallsBackToFirstInstallationWhenSelectionDisappears() {
        let replacement = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let disappeared = makeInstallation(version: "25.0", path: "/Applications/AE 25.app")
        let scanner = ScannerStub(result: .success([disappeared]))
        let model = makeModel(scanner: scanner)
        model.refresh()
        scanner.result = .success([replacement])

        model.refresh()

        XCTAssertEqual(model.selectedInstallationID, replacement.id)
    }

    func testSelectInstallationAcceptsKnownIDsAndRejectsUnknownIDs() {
        let newest = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let older = makeInstallation(version: "25.0", path: "/Applications/AE 25.app")
        let model = makeModel(scanner: ScannerStub(result: .success([newest, older])))
        model.refresh()

        model.selectInstallation(id: older.id)
        XCTAssertEqual(model.selectedInstallationID, older.id)

        model.selectInstallation(id: URL(fileURLWithPath: "/Applications/Unknown.app"))
        XCTAssertEqual(model.selectedInstallationID, older.id)
    }

    func testRunningAfterEffectsKeepsActionAvailableButBlocksMutationWhenRequested() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let process = RunningAEProcess(
            name: "Adobe After Effects 2026",
            bundleIdentifier: "com.adobe.AfterEffects.application"
        )
        let monitor = ProcessMonitorStub(running: [])
        let switcher = SwitcherSpy()
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            switcher: switcher,
            monitor: monitor
        )
        model.refresh()
        monitor.running = [process]
        model.sceneBecameActive()

        XCTAssertEqual(model.primarySwitchTarget, .english)
        XCTAssertTrue(model.isPrimarySwitchEnabled)

        model.requestSwitch(to: .english)

        XCTAssertEqual(model.runningProcesses, [process])
        XCTAssertEqual(model.alert, .afterEffectsRunning)
        XCTAssertEqual(model.statusMessage, "请先退出所有正在运行的 After Effects，再切换语言。")
        XCTAssertTrue(switcher.calls.isEmpty)
    }

    func testRefreshReportsMissingChineseResourceWithoutInvokingSwitcher() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let state = LanguageState(
            effective: .english,
            chineseEligibility: .missingResource,
            markerExists: true
        )
        let switcher = SwitcherSpy()
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: DetectorStub(states: [installation.id: state]),
            switcher: switcher
        )

        model.refresh()

        XCTAssertEqual(model.alert, .chineseUnavailable(.missingResource))
        XCTAssertEqual(model.statusMessage, "无法切换到简体中文：所选 AE 缺少中文资源。")
        XCTAssertEqual(model.primarySwitchTarget, .simplifiedChinese)
        XCTAssertTrue(switcher.calls.isEmpty)
    }

    func testRefreshReportsIneligibleSystemLanguageWithoutInvokingSwitcher() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let eligibility = ChineseEligibility.systemLanguageNotSimplifiedChinese("en-US")
        let state = LanguageState(
            effective: .systemDefault("en-US"),
            chineseEligibility: eligibility,
            markerExists: false
        )
        let switcher = SwitcherSpy()
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: DetectorStub(states: [installation.id: state]),
            switcher: switcher
        )

        model.refresh()

        XCTAssertEqual(model.alert, .chineseUnavailable(eligibility))
        XCTAssertEqual(model.statusMessage, "无法切换到简体中文：macOS 首选语言为 en-US。")
        XCTAssertNil(model.primarySwitchTarget)
        XCTAssertTrue(switcher.calls.isEmpty)
    }

    func testRefreshDoesNotReplaceRunningAlertWithDetectedChineseIneligibility() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let ineligibleState = LanguageState(
            effective: .english,
            chineseEligibility: .missingResource,
            markerExists: true
        )
        let detector = DetectorStub(statesInOrder: [.eligibleChinese, ineligibleState])
        let process = RunningAEProcess(
            name: "Adobe After Effects 2026",
            bundleIdentifier: "com.adobe.AfterEffects.application"
        )
        let monitor = ProcessMonitorStub(running: [])
        let switcher = SwitcherSpy()
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: detector,
            switcher: switcher,
            monitor: monitor
        )
        model.refresh()
        monitor.running = [process]
        model.requestSwitch(to: .english)
        monitor.running = []

        model.refresh()

        XCTAssertEqual(model.languageState, ineligibleState)
        XCTAssertEqual(model.alert, .afterEffectsRunning)
        XCTAssertEqual(model.statusMessage, "请先退出所有正在运行的 After Effects，再切换语言。")
        XCTAssertTrue(switcher.calls.isEmpty)
    }

    func testSuccessfulSwitchPassesTargetAndEligibilityThenRefreshesState() {
        let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let before = LanguageState(
            effective: .simplifiedChinese,
            chineseEligibility: .available,
            markerExists: false
        )
        let after = LanguageState(
            effective: .english,
            chineseEligibility: .available,
            markerExists: true
        )
        let detector = DetectorStub(statesInOrder: [before, after])
        let switcher = SwitcherSpy()
        let model = makeModel(
            scanner: ScannerStub(result: .success([installation])),
            detector: detector,
            switcher: switcher
        )
        model.refresh()

        model.requestSwitch(to: .english)

        XCTAssertEqual(switcher.calls, [SwitchCall(target: .english, eligibility: .available)])
        XCTAssertEqual(model.languageState, after)
        XCTAssertNil(model.alert)
        XCTAssertEqual(model.statusMessage, "已切换到 English。将在下次启动 After Effects 时生效。")
        XCTAssertFalse(model.isBusy)
    }

    func testSelectionChangeRedetectsEligibilityBeforeChineseSwitch() {
        let eligible = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
        let missingChinese = makeInstallation(version: "25.0", path: "/Applications/AE 25.app")
        let availableState = LanguageState(
            effective: .simplifiedChinese,
            chineseEligibility: .available,
            markerExists: false
        )
        let missingResourceState = LanguageState(
            effective: .systemDefault("zh-Hans"),
            chineseEligibility: .missingResource,
            markerExists: false
        )
        let detector = DetectorStub(states: [
            eligible.id: availableState,
            missingChinese.id: missingResourceState
        ])
        let switcher = SwitcherSpy(error: .chineseUnavailable(.missingResource))
        let model = makeModel(
            scanner: ScannerStub(result: .success([eligible, missingChinese])),
            detector: detector,
            switcher: switcher
        )
        model.refresh()

        model.selectInstallation(id: missingChinese.id)
        model.requestSwitch(to: .simplifiedChinese)

        XCTAssertEqual(model.languageState, missingResourceState)
        XCTAssertEqual(
            switcher.calls,
            [SwitchCall(target: .simplifiedChinese, eligibility: .missingResource)]
        )
        XCTAssertEqual(model.alert, .chineseUnavailable(.missingResource))
    }

    func testScanFailureProducesTypedAlertAndStableEmptyState() {
        let model = makeModel(scanner: ScannerStub(result: .failure(TestFailure.scan)))

        model.refresh()

        XCTAssertEqual(model.installations, [])
        XCTAssertNil(model.selectedInstallationID)
        XCTAssertNil(model.languageState)
        XCTAssertEqual(model.runningProcesses, [])
        XCTAssertEqual(model.alert, .scanError("scan failed"))
        XCTAssertEqual(model.statusMessage, "无法扫描 After Effects：scan failed")
        XCTAssertFalse(model.isBusy)
    }

    func testNoInstallationBlocksSwitchWithoutCallingSwitcher() {
        let switcher = SwitcherSpy()
        let model = makeModel(
            scanner: ScannerStub(result: .success([])),
            switcher: switcher
        )
        model.refresh()

        model.requestSwitch(to: .english)

        XCTAssertEqual(model.alert, .noInstallation)
        XCTAssertEqual(model.statusMessage, "未找到可用的 After Effects 安装。")
        XCTAssertTrue(switcher.calls.isEmpty)
    }

    func testTypedSwitchErrorsMapToTypedAlerts() {
        let cases: [(LanguageSwitchError, AppAlert)] = [
            (
                .chineseUnavailable(.systemLanguageNotSimplifiedChinese("en-US")),
                .chineseUnavailable(.systemLanguageNotSimplifiedChinese("en-US"))
            ),
            (.unsafeMarkerType, .unsafeMarkerType),
            (.nonEmptyMarker, .nonEmptyMarker),
            (.fileOperation("permission denied"), .fileError("permission denied"))
        ]

        for (switchError, expectedAlert) in cases {
            let installation = makeInstallation(version: "26.0", path: "/Applications/AE 26.app")
            let switcher = SwitcherSpy(error: switchError)
            let model = makeModel(
                scanner: ScannerStub(result: .success([installation])),
                switcher: switcher
            )
            model.refresh()

            model.requestSwitch(to: .simplifiedChinese)

            XCTAssertEqual(model.alert, expectedAlert, "Failed to map \(switchError)")
        }
    }

    func testDismissAlertClearsThePresentedAlert() {
        let model = makeModel(scanner: ScannerStub(result: .failure(TestFailure.scan)))
        model.refresh()
        XCTAssertNotNil(model.alert)

        model.dismissAlert()

        XCTAssertNil(model.alert)
    }

    func testSceneActivationRefreshesRunningProcesses() {
        let process = RunningAEProcess(
            name: "Adobe After Effects Beta",
            bundleIdentifier: "com.adobe.AfterEffects.application"
        )
        let monitor = ProcessMonitorStub(running: [process])
        let model = makeModel(monitor: monitor)

        model.sceneBecameActive()

        XCTAssertEqual(model.runningProcesses, [process])
        XCTAssertEqual(monitor.callCount, 1)
    }

    func testLiveDependenciesCanRefreshWithoutMutatingTemporaryMarker() throws {
        let temporaryDirectory = try makeTemporaryApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let markerURL = temporaryDirectory.appendingPathComponent("ae_force_english.txt")
        let model = AppModel(
            markerURL: markerURL,
            scanner: AfterEffectsScanner(
                applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            ),
            detector: LanguageStateDetector(),
            switcher: LanguageSwitcher(
                markerURL: markerURL,
                clearApplicationLanguage: { _ in }
            ),
            processMonitor: NSWorkspaceProcessMonitor()
        )

        model.refresh()

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertFalse(model.isBusy)
        if model.installations.isEmpty {
            XCTAssertNil(model.selectedInstallationID)
            XCTAssertNil(model.languageState)
        } else {
            XCTAssertNotNil(model.selectedInstallationID)
            XCTAssertNotNil(model.languageState)
        }
    }

    private func makeModel(
        scanner: ScannerStub = ScannerStub(result: .success([])),
        detector: DetectorStub = DetectorStub(defaultState: .eligibleChinese),
        switcher: SwitcherSpy = SwitcherSpy(),
        monitor: ProcessMonitorStub = ProcessMonitorStub(running: [])
    ) -> AppModel {
        AppModel(
            markerURL: URL(fileURLWithPath: "/controlled-test-marker"),
            scanner: scanner,
            detector: detector,
            switcher: switcher,
            processMonitor: monitor
        )
    }

    private func makeInstallation(version: String, path: String) -> AEInstallation {
        AEInstallation(
            displayName: "Adobe After Effects \(version)",
            version: version,
            build: "1",
            bundleIdentifier: "com.adobe.AfterEffects.application",
            appURL: URL(fileURLWithPath: path),
            availableLocales: [.englishUS, .simplifiedChinese]
        )
    }
}

private extension LanguageState {
    static let eligibleChinese = LanguageState(
        effective: .simplifiedChinese,
        chineseEligibility: .available,
        markerExists: false
    )
}

private enum TestFailure: LocalizedError {
    case scan

    var errorDescription: String? { "scan failed" }
}

private final class ScannerStub: AfterEffectsScanning, @unchecked Sendable {
    var result: Result<[AEInstallation], Error>

    init(result: Result<[AEInstallation], Error>) {
        self.result = result
    }

    func scan() throws -> [AEInstallation] {
        try result.get()
    }
}

private final class DetectorStub: LanguageStateDetecting, @unchecked Sendable {
    private let states: [URL: LanguageState]
    private let defaultState: LanguageState
    private var statesInOrder: [LanguageState]
    private(set) var installationIDs: [URL] = []

    init(states: [URL: LanguageState] = [:], defaultState: LanguageState = .eligibleChinese) {
        self.states = states
        self.defaultState = defaultState
        self.statesInOrder = []
    }

    init(statesInOrder: [LanguageState]) {
        self.states = [:]
        self.defaultState = .eligibleChinese
        self.statesInOrder = statesInOrder
    }

    func detect(for installation: AEInstallation, markerURL: URL) -> LanguageState {
        installationIDs.append(installation.id)
        if !statesInOrder.isEmpty {
            return statesInOrder.removeFirst()
        }
        return states[installation.id] ?? defaultState
    }
}

private struct SwitchCall: Equatable {
    let target: TargetLanguage
    let eligibility: ChineseEligibility
}

private final class SwitcherSpy: LanguageSwitching, @unchecked Sendable {
    private(set) var calls: [SwitchCall] = []
    let error: LanguageSwitchError?

    init(error: LanguageSwitchError? = nil) {
        self.error = error
    }

    func `switch`(to target: TargetLanguage, chineseEligibility: ChineseEligibility) throws {
        calls.append(SwitchCall(target: target, eligibility: chineseEligibility))
        if let error {
            throw error
        }
    }
}

private final class ProcessMonitorStub: AfterEffectsProcessMonitoring, @unchecked Sendable {
    var running: [RunningAEProcess]
    private(set) var callCount = 0

    init(running: [RunningAEProcess]) {
        self.running = running
    }

    func runningAfterEffects() -> [RunningAEProcess] {
        callCount += 1
        return running
    }
}
