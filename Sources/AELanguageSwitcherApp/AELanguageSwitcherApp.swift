import AELanguageSwitcherCore
import SwiftUI

@main
@MainActor
struct AELanguageSwitcherApp: App {
    @StateObject private var model: AppModel

    init() {
        let afterEffectsBundleIdentifier = "com.adobe.AfterEffects.application"
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let markerURL = documentsURL.appendingPathComponent("ae_force_english.txt")
        let preferredLanguageProvider = SystemPreferredLanguageProvider()
        let detector = LanguageStateDetector(
            preferredLanguageProvider: preferredLanguageProvider
        )

        _model = StateObject(
            wrappedValue: AppModel(
                markerURL: markerURL,
                scanner: AfterEffectsScanner(applicationsURL: applicationsURL),
                detector: detector,
                switcher: LanguageSwitcher(
                    markerURL: markerURL,
                    applicationBundleIdentifier: afterEffectsBundleIdentifier
                ),
                processMonitor: NSWorkspaceProcessMonitor()
            )
        )
    }

    var body: some Scene {
        Window("AE 中英文切换器", id: "main") {
            ContentView(model: model)
                .frame(width: 420, height: 260)
        }
        .windowResizability(.contentSize)
    }
}
