import AppKit
import Foundation

public struct RunningAEProcess: Equatable, Sendable {
    public let name: String
    public let bundleIdentifier: String

    public init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

public protocol AfterEffectsProcessMonitoring: Sendable {
    func runningAfterEffects() -> [RunningAEProcess]
}

public struct NSWorkspaceProcessMonitor: AfterEffectsProcessMonitoring {
    private static let afterEffectsBundleIdentifier = "com.adobe.AfterEffects.application"

    public init() {}

    public func runningAfterEffects() -> [RunningAEProcess] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.bundleIdentifier == Self.afterEffectsBundleIdentifier else {
                return nil
            }

            let name = application.localizedName ?? Self.afterEffectsBundleIdentifier
            guard name.range(of: "Render Engine", options: .caseInsensitive) == nil else {
                return nil
            }

            return RunningAEProcess(
                name: name,
                bundleIdentifier: Self.afterEffectsBundleIdentifier
            )
        }
    }
}
