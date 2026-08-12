import Foundation
import SwiftUI

public enum AppAlert: Equatable, Sendable {
    case afterEffectsRunning
    case noInstallation
    case chineseUnavailable(ChineseEligibility)
    case unsafeMarkerType
    case nonEmptyMarker
    case scanError(String)
    case fileError(String)
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var installations: [AEInstallation] = []
    @Published public private(set) var selectedInstallationID: URL? {
        didSet {
            guard selectedInstallationID != oldValue else { return }
            deriveLanguageStateForSelection()
        }
    }
    @Published public private(set) var languageState: LanguageState?
    @Published public private(set) var runningProcesses: [RunningAEProcess] = []
    @Published public private(set) var statusMessage = ""
    @Published public private(set) var isBusy = false
    @Published public private(set) var alert: AppAlert?

    private let markerURL: URL
    private let scanner: any AfterEffectsScanning
    private let detector: any LanguageStateDetecting
    private let switcher: any LanguageSwitching
    private let processMonitor: any AfterEffectsProcessMonitoring

    public init(
        markerURL: URL,
        scanner: any AfterEffectsScanning,
        detector: any LanguageStateDetecting,
        switcher: any LanguageSwitching,
        processMonitor: any AfterEffectsProcessMonitoring
    ) {
        self.markerURL = markerURL
        self.scanner = scanner
        self.detector = detector
        self.switcher = switcher
        self.processMonitor = processMonitor
    }

    public func refresh() {
        isBusy = true
        defer { isBusy = false }
        refreshState()
    }

    public func selectInstallation(id: URL) {
        guard installations.contains(where: { $0.id == id }) else { return }
        selectedInstallationID = id
    }

    public func dismissAlert() {
        alert = nil
    }

    public var primarySwitchTarget: TargetLanguage? {
        guard let languageState else { return nil }
        switch languageState.effective {
        case .simplifiedChinese:
            return .english
        case .english:
            return .simplifiedChinese
        case .systemDefault:
            return nil
        }
    }

    public var isPrimarySwitchEnabled: Bool {
        guard let primarySwitchTarget else { return false }
        return isSwitchActionEnabled(to: primarySwitchTarget)
    }

    public func isSwitchActionEnabled(to target: TargetLanguage) -> Bool {
        guard
            !isBusy,
            let selectedInstallationID,
            installations.contains(where: { $0.id == selectedInstallationID }),
            let languageState
        else {
            return false
        }

        switch target {
        case .english:
            return languageState.effective != .english
        case .simplifiedChinese:
            return languageState.effective != .simplifiedChinese
                && languageState.chineseEligibility == .available
        }
    }

    public func requestSwitch(to target: TargetLanguage) {
        isBusy = true
        defer { isBusy = false }

        alert = nil
        runningProcesses = processMonitor.runningAfterEffects()
        guard runningProcesses.isEmpty else {
            alert = .afterEffectsRunning
            statusMessage = "请先退出所有正在运行的 After Effects，再切换语言。"
            return
        }

        guard
            let selectedInstallationID,
            installations.contains(where: { $0.id == selectedInstallationID }),
            let languageState
        else {
            alert = .noInstallation
            statusMessage = "未找到可用的 After Effects 安装。"
            return
        }

        do {
            try switcher.switch(
                to: target,
                chineseEligibility: languageState.chineseEligibility
            )
            refreshState()
            guard alert == nil else { return }
            statusMessage = successMessage(for: target)
        } catch let switchError as LanguageSwitchError {
            apply(switchError)
        } catch {
            let description = error.localizedDescription
            alert = .fileError(description)
            statusMessage = "无法更新语言标记：\(description)"
        }
    }

    public func sceneBecameActive() {
        refresh()
    }

    private func refreshState() {
        let preservedPresentation = importantAlertPresentation
        alert = nil
        runningProcesses = processMonitor.runningAfterEffects()

        do {
            let scannedInstallations = try scanner.scan()
            installations = scannedInstallations
            let resolvedSelection = scannedInstallations.first?.id

            if selectedInstallationID == resolvedSelection {
                deriveLanguageStateForSelection()
            } else {
                selectedInstallationID = resolvedSelection
            }

            if let preservedPresentation {
                alert = preservedPresentation.alert
                statusMessage = preservedPresentation.statusMessage
                return
            }

            guard languageState != nil else {
                statusMessage = "未找到 After Effects 安装。"
                return
            }

            guard !applyDetectedChineseIneligibilityIfNeeded() else { return }
            statusMessage = "已就绪。"
        } catch {
            let description = error.localizedDescription
            installations = []
            selectedInstallationID = nil
            languageState = nil
            alert = .scanError(description)
            statusMessage = "无法扫描 After Effects：\(description)"
        }
    }

    private var importantAlertPresentation: (alert: AppAlert, statusMessage: String)? {
        guard let alert else { return nil }
        switch alert {
        case .afterEffectsRunning, .scanError, .fileError, .unsafeMarkerType, .nonEmptyMarker:
            return (alert, statusMessage)
        case .noInstallation, .chineseUnavailable:
            return nil
        }
    }

    private func deriveLanguageStateForSelection() {
        guard
            let selectedInstallationID,
            let selectedInstallation = installations.first(where: {
                $0.id == selectedInstallationID
            })
        else {
            languageState = nil
            return
        }

        languageState = detector.detect(
            for: selectedInstallation,
            markerURL: markerURL
        )
    }

    private func apply(_ error: LanguageSwitchError) {
        switch error {
        case let .chineseUnavailable(eligibility):
            applyChineseIneligibility(eligibility)
        case .unsafeMarkerType:
            alert = .unsafeMarkerType
            statusMessage = "语言标记路径不是普通文件，未做任何修改。"
        case .nonEmptyMarker:
            alert = .nonEmptyMarker
            statusMessage = "语言标记文件含有内容，未做任何修改。"
        case let .fileOperation(description):
            alert = .fileError(description)
            statusMessage = "无法更新语言标记：\(description)"
        }
    }

    private func applyDetectedChineseIneligibilityIfNeeded() -> Bool {
        guard alert == nil, let eligibility = languageState?.chineseEligibility else {
            return false
        }
        guard eligibility != .available else { return false }
        applyChineseIneligibility(eligibility)
        return true
    }

    private func applyChineseIneligibility(_ eligibility: ChineseEligibility) {
        alert = .chineseUnavailable(eligibility)
        switch eligibility {
        case .available:
            statusMessage = "暂时无法切换到简体中文，请重新扫描后再试。"
        case .missingResource:
            statusMessage = "无法切换到简体中文：所选 AE 缺少中文资源。"
        case let .systemLanguageNotSimplifiedChinese(language):
            statusMessage = "无法切换到简体中文：macOS 首选语言为 \(language)。"
        }
    }

    private func successMessage(for target: TargetLanguage) -> String {
        switch target {
        case .english:
            "已切换到 English。将在下次启动 After Effects 时生效。"
        case .simplifiedChinese:
            "已切换到简体中文。将在下次启动 After Effects 时生效。"
        }
    }
}
