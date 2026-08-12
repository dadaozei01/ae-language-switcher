import AELanguageSwitcherCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasStarted = false
    @State private var isRefreshing = false

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { model.alert != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissAlert()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 32) {
                header
                primarySwitchButton
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
                .padding(.horizontal, 24)
                .frame(height: 58)
        }
        .frame(width: 420, height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            startRefresh()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, hasStarted else { return }
            startRefresh()
        }
        .alert(
            currentAlert.title,
            isPresented: alertIsPresented,
            actions: {
                Button("好", role: .cancel) {
                    model.dismissAlert()
                }
            },
            message: {
                Text(currentAlert.message)
            }
        )
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("AE 语言切换")
                .font(.title2.bold())

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                languageStatus("中文", isActive: activeLanguage == .simplifiedChinese)
                Text("|")
                    .foregroundStyle(.tertiary)
                languageStatus("English", isActive: activeLanguage == .english)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(languageAccessibilityLabel)
        }
    }

    private func languageStatus(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            if isActive {
                Circle()
                    .fill(Color.indigo)
                    .frame(width: 7, height: 7)
            }

            Text(title)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.indigo : Color.secondary)
        }
    }

    private var primarySwitchButton: some View {
        Button(primaryButtonTitle) {
            guard let target = model.primarySwitchTarget else { return }
            model.requestSwitch(to: target)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.indigo)
        .frame(maxWidth: .infinity)
        .disabled(
            !model.isPrimarySwitchEnabled
                || model.installations.isEmpty
                || isRefreshInProgress
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if isRefreshInProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button("重新扫描") {
                startRefresh()
            }
            .disabled(isRefreshInProgress)
        }
    }

    private var isRefreshInProgress: Bool {
        isRefreshing || model.isBusy
    }

    private func startRefresh() {
        guard !isRefreshInProgress else { return }
        isRefreshing = true

        Task { @MainActor in
            await Task.yield()
            model.refresh()
            isRefreshing = false
        }
    }

    private var activeLanguage: TargetLanguage? {
        guard let effective = model.languageState?.effective else { return nil }
        switch effective {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .systemDefault:
            return nil
        }
    }

    private var primaryButtonTitle: String {
        switch model.primarySwitchTarget {
        case .english:
            return "切换到 English"
        case .simplifiedChinese:
            return "切换到中文"
        case nil where isRefreshInProgress:
            return "正在扫描…"
        case nil where model.installations.isEmpty:
            return "未检测到 After Effects"
        case nil:
            return "无法确定当前语言"
        }
    }

    private var languageAccessibilityLabel: String {
        switch activeLanguage {
        case .simplifiedChinese:
            return "当前语言：中文"
        case .english:
            return "当前语言：English"
        case nil:
            return "当前语言无法确定"
        }
    }

    private var currentAlert: AlertPresentation {
        guard let alert = model.alert else {
            return AlertPresentation(title: "提示", message: "")
        }
        switch alert {
        case .afterEffectsRunning:
            return AlertPresentation(
                title: "After Effects 正在运行",
                message: "请先退出所有正在运行的 After Effects，然后再切换语言。本应用不会强制退出任何进程。"
            )
        case .noInstallation:
            return AlertPresentation(
                title: "未找到 After Effects",
                message: "没有可用于切换语言的 After Effects 安装。请安装后重新扫描。"
            )
        case let .chineseUnavailable(eligibility):
            switch eligibility {
            case .available:
                return AlertPresentation(
                    title: "暂时无法切换",
                    message: "请重新扫描状态后再试。"
                )
            case .missingResource:
                return AlertPresentation(
                    title: "缺少中文资源",
                    message: "所选 After Effects 未安装简体中文资源。请通过 Creative Cloud 安装中文版本。"
                )
            case let .systemLanguageNotSimplifiedChinese(language):
                return AlertPresentation(
                    title: "系统语言不符合要求",
                    message: "当前首选语言为 \(language)。请先在 macOS“语言与地区”中将简体中文设为首选语言。"
                )
            }
        case .unsafeMarkerType:
            return AlertPresentation(
                title: "语言标记路径不安全",
                message: "ae_force_english.txt 不是普通文件。为保护数据，本应用未做任何修改，请手动检查该路径。"
            )
        case .nonEmptyMarker:
            return AlertPresentation(
                title: "语言标记文件含有内容",
                message: "为避免删除用户数据，本应用不会移除非空的 ae_force_english.txt。请手动检查该文件。"
            )
        case let .scanError(description):
            return AlertPresentation(
                title: "扫描失败",
                message: "无法扫描 After Effects：\(description)"
            )
        case let .fileError(description):
            return AlertPresentation(
                title: "文件操作失败",
                message: "无法更新语言标记：\(description)"
            )
        }
    }
}

private struct AlertPresentation {
    let title: String
    let message: String
}
