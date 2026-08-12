import Darwin
import CoreFoundation
import Foundation

public enum TargetLanguage: Equatable, Sendable {
    case english
    case simplifiedChinese
}

public enum LanguageSwitchError: LocalizedError, Equatable {
    case chineseUnavailable(ChineseEligibility)
    case unsafeMarkerType
    case nonEmptyMarker
    case fileOperation(String)

    public var errorDescription: String? {
        switch self {
        case .chineseUnavailable:
            "Simplified Chinese is unavailable for this After Effects installation."
        case .unsafeMarkerType:
            "The language marker is not a regular file."
        case .nonEmptyMarker:
            "The language marker is not empty."
        case let .fileOperation(description):
            description
        }
    }
}

public protocol LanguageSwitching: Sendable {
    func `switch`(to target: TargetLanguage, chineseEligibility: ChineseEligibility) throws
}

public struct LanguageSwitcher: LanguageSwitching, Sendable {
    private let markerURL: URL
    private let applicationBundleIdentifier: String
    private let clearApplicationLanguage: @Sendable (String) throws -> Void
    private let beforeMarkerDeletion: @Sendable () -> Void
    private let beforeQuarantineRename: @Sendable () -> Void

    public init(
        markerURL: URL,
        applicationBundleIdentifier: String,
        fileManager: FileManager = .default
    ) {
        self.markerURL = markerURL
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.clearApplicationLanguage = { bundleIdentifier in
            try ApplicationLanguagePreferences.clear(for: bundleIdentifier)
        }
        self.beforeMarkerDeletion = {}
        self.beforeQuarantineRename = {}
        // Retained for the required public interface. Marker mutations use POSIX
        // descriptor operations because FileManager removal is recursive for directories.
        _ = fileManager
    }

    init(
        markerURL: URL,
        applicationBundleIdentifier: String = "com.adobe.AfterEffects.application",
        clearApplicationLanguage: @escaping @Sendable (String) throws -> Void = { _ in },
        beforeMarkerDeletion: @escaping @Sendable () -> Void
    ) {
        self.markerURL = markerURL
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.clearApplicationLanguage = clearApplicationLanguage
        self.beforeMarkerDeletion = beforeMarkerDeletion
        self.beforeQuarantineRename = {}
    }

    init(
        markerURL: URL,
        applicationBundleIdentifier: String = "com.adobe.AfterEffects.application",
        clearApplicationLanguage: @escaping @Sendable (String) throws -> Void = { _ in },
        beforeQuarantineRename: @escaping @Sendable () -> Void
    ) {
        self.markerURL = markerURL
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.clearApplicationLanguage = clearApplicationLanguage
        self.beforeMarkerDeletion = {}
        self.beforeQuarantineRename = beforeQuarantineRename
    }

    init(
        markerURL: URL,
        applicationBundleIdentifier: String = "com.adobe.AfterEffects.application",
        clearApplicationLanguage: @escaping @Sendable (String) throws -> Void
    ) {
        self.markerURL = markerURL
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.clearApplicationLanguage = clearApplicationLanguage
        self.beforeMarkerDeletion = {}
        self.beforeQuarantineRename = {}
    }

    public func `switch`(to target: TargetLanguage, chineseEligibility: ChineseEligibility) throws {
        switch target {
        case .english:
            try enableEnglish()
        case .simplifiedChinese:
            try enableSimplifiedChinese(when: chineseEligibility)
        }
    }

    private func enableEnglish() throws {
        try clearApplicationLanguage(applicationBundleIdentifier)
        while true {
            switch try markerKind() {
            case .regular:
                return
            case .unsafe:
                throw LanguageSwitchError.unsafeMarkerType
            case .absent:
                if try createEmptyMarkerAtomically() {
                    return
                }
            }
        }
    }

    private func enableSimplifiedChinese(when eligibility: ChineseEligibility) throws {
        guard eligibility == .available else {
            throw LanguageSwitchError.chineseUnavailable(eligibility)
        }

        try clearApplicationLanguage(applicationBundleIdentifier)
        try removeZeroByteMarker()
    }

    private func markerKind() throws -> MarkerKind {
        var status = stat()
        if Darwin.lstat(markerURL.path, &status) == 0 {
            let fileType = status.st_mode & S_IFMT
            if fileType == S_IFREG {
                return .regular(UInt64(status.st_size))
            }
            return .unsafe
        }

        if Darwin.errno == ENOENT {
            return .absent
        }
        throw fileOperationError()
    }

    private func createEmptyMarkerAtomically() throws -> Bool {
        let descriptor = Darwin.open(markerURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if Darwin.errno == EEXIST {
                return false
            }
            throw fileOperationError()
        }

        guard Darwin.close(descriptor) == 0 else {
            throw fileOperationError()
        }
        return true
    }

    private func removeZeroByteMarker() throws {
        let parentURL = markerURL.deletingLastPathComponent()
        let parentDescriptor = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY)
        guard parentDescriptor >= 0 else {
            throw fileOperationError()
        }
        defer { _ = Darwin.close(parentDescriptor) }

        let markerName = markerURL.lastPathComponent
        let markerDescriptor = Darwin.openat(
            parentDescriptor,
            markerName,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK
        )
        guard markerDescriptor >= 0 else {
            if Darwin.errno == ENOENT {
                return
            }
            if Darwin.errno == ELOOP {
                throw LanguageSwitchError.unsafeMarkerType
            }
            throw fileOperationError()
        }
        defer { _ = Darwin.close(markerDescriptor) }

        var openedStatus = stat()
        guard Darwin.fstat(markerDescriptor, &openedStatus) == 0 else {
            throw fileOperationError()
        }
        guard isRegularFile(openedStatus) else {
            throw LanguageSwitchError.unsafeMarkerType
        }
        guard openedStatus.st_size == 0 else {
            throw LanguageSwitchError.nonEmptyMarker
        }

        beforeMarkerDeletion()

        var entryStatus = stat()
        guard Darwin.fstatat(parentDescriptor, markerName, &entryStatus, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw markerIdentityChangedError()
        }
        guard isRegularFile(entryStatus), entryStatus.st_size == 0,
              entryStatus.st_dev == openedStatus.st_dev,
              entryStatus.st_ino == openedStatus.st_ino else {
            throw markerIdentityChangedError()
        }

        beforeQuarantineRename()

        guard let quarantineName = try moveMarkerToQuarantine(
            named: markerName,
            in: parentDescriptor
        ) else {
            return
        }

        var quarantinedStatus = stat()
        guard Darwin.fstatat(
            parentDescriptor,
            quarantineName,
            &quarantinedStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            throw markerReplacementRecoveryError(
                at: parentURL.appendingPathComponent(quarantineName)
            )
        }

        guard isRegularFile(quarantinedStatus), quarantinedStatus.st_size == 0,
              quarantinedStatus.st_dev == openedStatus.st_dev,
              quarantinedStatus.st_ino == openedStatus.st_ino else {
            try restoreReplacement(
                named: quarantineName,
                to: markerName,
                in: parentDescriptor,
                parentURL: parentURL
            )
            throw markerIdentityChangedError()
        }

        // Retain the validated zero-byte marker under its unique quarantine name.
        // It no longer affects After Effects, and avoiding a later pathname unlink
        // prevents a substituted object from ever being deleted.
    }

    private func moveMarkerToQuarantine(named markerName: String, in parentDescriptor: Int32) throws -> String? {
        for _ in 0..<16 {
            let quarantineName = ".ae-language-switcher-\(UUID().uuidString).quarantine"
            if Darwin.renameatx_np(
                parentDescriptor,
                markerName,
                parentDescriptor,
                quarantineName,
                UInt32(RENAME_EXCL)
            ) == 0 {
                return quarantineName
            }

            switch Darwin.errno {
            case EEXIST:
                continue
            case ENOENT:
                return nil
            default:
                throw fileOperationError()
            }
        }
        throw fileOperationError()
    }

    private func restoreReplacement(
        named quarantineName: String,
        to markerName: String,
        in parentDescriptor: Int32,
        parentURL: URL
    ) throws {
        if Darwin.renameatx_np(
            parentDescriptor,
            quarantineName,
            parentDescriptor,
            markerName,
            UInt32(RENAME_EXCL)
        ) == 0 {
            return
        }
        throw markerReplacementRecoveryError(
            at: parentURL.appendingPathComponent(quarantineName)
        )
    }

    private func isRegularFile(_ status: stat) -> Bool {
        status.st_mode & S_IFMT == S_IFREG
    }

    private func markerIdentityChangedError() -> LanguageSwitchError {
        .fileOperation("The language marker changed before it could be removed.")
    }

    private func markerReplacementRecoveryError(at recoveryURL: URL) -> LanguageSwitchError {
        .fileOperation(
            "The language marker changed before it could be removed. " +
                "The replacement was retained at \(recoveryURL.path)."
        )
    }

    private func fileOperationError() -> LanguageSwitchError {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno))
        return .fileOperation(error.localizedDescription)
    }
}

private enum MarkerKind {
    case absent
    case regular(UInt64)
    case unsafe
}

enum ApplicationLanguagePreferences {
    static func target(for bundleIdentifier: String) -> TargetLanguage? {
        guard
            let languages = CFPreferencesCopyAppValue(
                "AppleLanguages" as CFString,
                bundleIdentifier as CFString
            ) as? [String],
            let language = languages.first
        else {
            return nil
        }

        if language.hasPrefix("en") {
            return .english
        }
        if language == "zh_CN" || language.hasPrefix("zh-Hans") {
            return .simplifiedChinese
        }
        return nil
    }

    static func clear(for bundleIdentifier: String) throws {
        CFPreferencesSetAppValue(
            "AppleLanguages" as CFString,
            nil,
            bundleIdentifier as CFString
        )
        guard CFPreferencesAppSynchronize(bundleIdentifier as CFString) else {
            throw LanguageSwitchError.fileOperation(
                "Unable to save the After Effects application language preference."
            )
        }
    }
}
