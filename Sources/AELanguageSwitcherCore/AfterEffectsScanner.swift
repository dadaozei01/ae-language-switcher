import Foundation

public protocol AfterEffectsScanning: Sendable {
    func scan() throws -> [AEInstallation]
}

public struct AfterEffectsScanner: AfterEffectsScanning {
    private static let afterEffectsBundleIdentifier = "com.adobe.AfterEffects.application"
    private let applicationsURL: URL

    public init(applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)) {
        self.applicationsURL = applicationsURL
    }

    public func scan() throws -> [AEInstallation] {
        guard let enumerator = FileManager.default.enumerator(
            at: applicationsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var installations: [AEInstallation] = []
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level > 2 {
                enumerator.skipDescendants()
                continue
            }

            guard isAfterEffectsApp(url) else {
                if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
                continue
            }

            enumerator.skipDescendants()
            if let installation = installation(at: url) {
                installations.append(installation)
            }
        }

        return installations.sorted { left, right in
            let comparison = compareVersions(left.version, right.version)
            if comparison == .orderedSame {
                return left.appURL.path < right.appURL.path
            }
            return comparison == .orderedDescending
        }
    }

    private func isAfterEffectsApp(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasSuffix(".app")
            && name.hasPrefix("Adobe After Effects")
            && name.range(of: "Render Engine", options: .caseInsensitive) == nil
    }

    private func installation(at appURL: URL) -> AEInstallation? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let displayName = info["CFBundleDisplayName"] as? String,
            let version = info["CFBundleShortVersionString"] as? String,
            let build = info["CFBundleVersion"] as? String,
            let bundleIdentifier = info["CFBundleIdentifier"] as? String,
            bundleIdentifier == Self.afterEffectsBundleIdentifier
        else {
            return nil
        }

        var availableLocales: Set<AELocale> = []
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        if FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("zh_CN.lproj").path) {
            availableLocales.insert(.simplifiedChinese)
        }
        if FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("Libraries/locale/en_US").path) {
            availableLocales.insert(.englishUS)
        }

        return AEInstallation(
            displayName: displayName,
            version: version,
            build: build,
            bundleIdentifier: bundleIdentifier,
            appURL: appURL,
            availableLocales: availableLocales
        )
    }

    private func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftComponents = left.split(separator: ".").map { Int($0) ?? 0 }
        let rightComponents = right.split(separator: ".").map { Int($0) ?? 0 }
        let componentCount = max(leftComponents.count, rightComponents.count)

        for index in 0..<componentCount {
            let leftComponent = index < leftComponents.count ? leftComponents[index] : 0
            let rightComponent = index < rightComponents.count ? rightComponents[index] : 0
            if leftComponent != rightComponent {
                return leftComponent < rightComponent ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}
