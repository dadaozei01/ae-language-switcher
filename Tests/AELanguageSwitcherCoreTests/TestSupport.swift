import Foundation

func makeTemporaryApplicationsDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func makeAppBundle(
    in applicationsURL: URL,
    name: String,
    displayName: String = "Adobe After Effects",
    version: String = "25.0",
    build: String = "1",
    bundleIdentifier: String = "com.adobe.AfterEffects.application",
    locales: [String] = []
) throws -> URL {
    let appURL = applicationsURL.appendingPathComponent(name, isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let info: [String: String] = [
        "CFBundleDisplayName": displayName,
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build
    ]
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    for locale in locales {
        let resourcePath: URL
        switch locale {
        case "zh_CN":
            resourcePath = contentsURL.appendingPathComponent("Resources/zh_CN.lproj", isDirectory: true)
        case "en_US":
            resourcePath = contentsURL.appendingPathComponent("Resources/Libraries/locale/en_US", isDirectory: true)
        default:
            continue
        }
        try FileManager.default.createDirectory(at: resourcePath, withIntermediateDirectories: true)
    }

    return appURL
}
