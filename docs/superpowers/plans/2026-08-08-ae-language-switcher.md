# AE Language Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that detects installed After Effects versions and safely switches the current user's global AE UI language between Simplified Chinese and English.

**Architecture:** A dependency-free Swift Package separates a testable `AELanguageSwitcherCore` library from a SwiftUI executable. Core services scan app bundles, derive language state, mutate only the safe user-level marker file, and monitor running AE processes; an `AppModel` coordinates those services for a small single-window UI.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Foundation, Swift Package Manager, XCTest, shell packaging script, macOS 13+

## Global Constraints

- Platform: macOS 13 or later; no third-party dependencies.
- Scan all formal and Beta After Effects apps under `/Applications` while excluding Render Engine helpers.
- The `~/Documents/ae_force_english.txt` marker is global to the current user and affects every installed AE version.
- Never modify an After Effects application bundle or request administrator privileges.
- Never force-quit After Effects; block switching while any AE main app is running.
- Enable Simplified Chinese only when the selected AE contains `zh_CN` resources and the first macOS preferred language is Simplified Chinese.
- Automatically remove the marker only when it is a zero-byte regular file; reject directories, symbolic links, and non-empty files.
- Git commits in the steps are required when repository metadata is writable. In the current managed workspace, record the intended commit message if `.git` creation remains blocked.

## File Map

- `Package.swift`: Swift package, products, targets, and macOS floor; the executable target is added with the UI task.
- `Sources/AELanguageSwitcherCore/AEInstallation.swift`: installation and locale value types.
- `Sources/AELanguageSwitcherCore/AfterEffectsScanner.swift`: application discovery and bundle metadata parsing.
- `Sources/AELanguageSwitcherCore/LanguageState.swift`: effective language and Chinese eligibility derivation.
- `Sources/AELanguageSwitcherCore/LanguageSwitcher.swift`: safe marker-file creation and removal.
- `Sources/AELanguageSwitcherCore/AfterEffectsProcessMonitor.swift`: running AE detection protocol and AppKit implementation.
- `Sources/AELanguageSwitcherCore/AppModel.swift`: `@MainActor` observable orchestration state.
- `Sources/AELanguageSwitcherApp/AELanguageSwitcherApp.swift`: application entry point and dependencies.
- `Sources/AELanguageSwitcherApp/ContentView.swift`: single-window SwiftUI interface and alerts.
- `Sources/AELanguageSwitcherApp/Resources/Info.plist`: packaged app metadata.
- `Tests/AELanguageSwitcherCoreTests/TestSupport.swift`: temporary fixtures and test doubles.
- `Tests/AELanguageSwitcherCoreTests/AfterEffectsScannerTests.swift`: discovery and metadata tests.
- `Tests/AELanguageSwitcherCoreTests/LanguageStateTests.swift`: state derivation tests.
- `Tests/AELanguageSwitcherCoreTests/LanguageSwitcherTests.swift`: marker safety tests.
- `Tests/AELanguageSwitcherCoreTests/AppModelTests.swift`: orchestration and running-process tests.
- `scripts/package_app.sh`: release build and `.app` assembly.
- `README.md`: usage, Adobe limitation, build, signing, and distribution notes.

---

### Task 1: Package Skeleton and After Effects Scanner

**Files:**
- Create: `Package.swift`
- Create: `Sources/AELanguageSwitcherCore/AEInstallation.swift`
- Create: `Sources/AELanguageSwitcherCore/AfterEffectsScanner.swift`
- Create: `Tests/AELanguageSwitcherCoreTests/TestSupport.swift`
- Create: `Tests/AELanguageSwitcherCoreTests/AfterEffectsScannerTests.swift`

**Interfaces:**
- Produces: `struct AEInstallation: Identifiable, Equatable, Sendable`
- Produces: `protocol AfterEffectsScanning { func scan() throws -> [AEInstallation] }`
- Produces: `struct AfterEffectsScanner: AfterEffectsScanning`

- [ ] **Step 1: Add the Swift package and scanner failure tests**

Define `Package.swift` with macOS 13, library target `AELanguageSwitcherCore`, and test target `AELanguageSwitcherCoreTests`. The executable product and target are added in Task 5 after its source directory exists. In the scanner tests, build fake bundles under a temporary `Applications` directory and assert that:

```swift
let installs = try AfterEffectsScanner(applicationsURL: fixture.applicationsURL).scan()
XCTAssertEqual(installs.map(\.version), ["26.0.0", "25.6.2"])
XCTAssertFalse(installs.contains { $0.appURL.lastPathComponent.contains("Render Engine") })
XCTAssertEqual(installs.first?.build, "26.0.0.67")
XCTAssertEqual(installs.first?.availableLocales, [.englishUS, .simplifiedChinese])
```

The fixture must create `Contents/Info.plist`, `Contents/Resources/zh_CN.lproj`, and `Contents/Resources/Libraries/locale/en_US` using `FileManager`.

- [ ] **Step 2: Run scanner tests and verify the expected compile failure**

Run: `xcrun swift test --filter AfterEffectsScannerTests`

Expected: FAIL because `AEInstallation` and `AfterEffectsScanner` do not exist.

- [ ] **Step 3: Implement installation models and scanning**

Use these public shapes:

```swift
public enum AELocale: String, Hashable, Sendable { case englishUS = "en_US"; case simplifiedChinese = "zh_CN" }

public struct AEInstallation: Identifiable, Equatable, Sendable {
    public var id: URL { appURL }
    public let displayName: String
    public let version: String
    public let build: String
    public let bundleIdentifier: String
    public let appURL: URL
    public let availableLocales: Set<AELocale>
}

public protocol AfterEffectsScanning: Sendable {
    func scan() throws -> [AEInstallation]
}
```

`AfterEffectsScanner.scan()` recursively enumerates no deeper than two directory levels below its injected `applicationsURL`, accepts bundle names beginning with `Adobe After Effects` and ending in `.app`, rejects names containing `Render Engine`, reads `Info.plist`, verifies `CFBundleIdentifier == "com.adobe.AfterEffects.application"`, detects locale resource paths, and sorts using numeric dot-separated version components descending.

- [ ] **Step 4: Run scanner tests**

Run: `xcrun swift test --filter AfterEffectsScannerTests`

Expected: PASS, including malformed bundle omission and Beta discovery.

- [ ] **Step 5: Commit scanner deliverable**

Run: `git add Package.swift Sources/AELanguageSwitcherCore Tests/AELanguageSwitcherCoreTests && git commit -m "feat: detect installed After Effects versions"`

---

### Task 2: Language State Detection

**Files:**
- Create: `Sources/AELanguageSwitcherCore/LanguageState.swift`
- Create: `Tests/AELanguageSwitcherCoreTests/LanguageStateTests.swift`

**Interfaces:**
- Consumes: `AEInstallation.availableLocales`
- Produces: `enum EffectiveLanguage`, `struct LanguageState`, `protocol PreferredLanguageProviding`, `struct LanguageStateDetector`

- [ ] **Step 1: Write failing state-table tests**

Create table-driven XCTest cases for these exact outcomes:

```swift
XCTAssertEqual(detect(markerExists: true, preferred: "zh-Hans-CN", locales: [.simplifiedChinese, .englishUS]).effective, .english)
XCTAssertEqual(detect(markerExists: false, preferred: "zh-Hans-CN", locales: [.simplifiedChinese, .englishUS]).effective, .simplifiedChinese)
XCTAssertEqual(detect(markerExists: false, preferred: "en-US", locales: [.simplifiedChinese, .englishUS]).effective, .systemDefault("en-US"))
XCTAssertEqual(detect(markerExists: false, preferred: "zh-Hans-CN", locales: [.englishUS]).chineseEligibility, .missingResource)
```

Also test `zh-Hans`, `zh_CN`, and `zh-Hans-CN` as Simplified Chinese, while rejecting `zh-Hant` and `zh-TW`.

- [ ] **Step 2: Verify the state tests fail**

Run: `xcrun swift test --filter LanguageStateTests`

Expected: FAIL because the language state types are undefined.

- [ ] **Step 3: Implement deterministic language derivation**

Expose:

```swift
public enum EffectiveLanguage: Equatable, Sendable {
    case english
    case simplifiedChinese
    case systemDefault(String)
}

public enum ChineseEligibility: Equatable, Sendable {
    case available
    case systemLanguageNotSimplifiedChinese(String)
    case missingResource
}

public struct LanguageState: Equatable, Sendable {
    public let effective: EffectiveLanguage
    public let chineseEligibility: ChineseEligibility
    public let markerExists: Bool
}
```

`LanguageStateDetector.detect(for:markerURL:)` uses an injected preferred-language provider and file metadata provider. It treats any existing marker as English but leaves unsafe path classification for the switcher.

- [ ] **Step 4: Run all core tests**

Run: `xcrun swift test`

Expected: PASS.

- [ ] **Step 5: Commit language detection**

Run: `git add Sources/AELanguageSwitcherCore/LanguageState.swift Tests/AELanguageSwitcherCoreTests/LanguageStateTests.swift && git commit -m "feat: derive AE language state"`

---

### Task 3: Safe Language Switching

**Files:**
- Create: `Sources/AELanguageSwitcherCore/LanguageSwitcher.swift`
- Create: `Tests/AELanguageSwitcherCoreTests/LanguageSwitcherTests.swift`
- Modify: `Tests/AELanguageSwitcherCoreTests/TestSupport.swift`

**Interfaces:**
- Consumes: `LanguageState`, `ChineseEligibility`
- Produces: `enum TargetLanguage`, `enum LanguageSwitchError`, `struct LanguageSwitcher`

- [ ] **Step 1: Write failing file-safety tests**

Use a temporary `Documents` directory and verify:

```swift
try switcher.switch(to: .english, chineseEligibility: .available)
XCTAssertTrue(fileManager.fileExists(atPath: marker.path))
XCTAssertEqual(try Data(contentsOf: marker).count, 0)

try switcher.switch(to: .simplifiedChinese, chineseEligibility: .available)
XCTAssertFalse(fileManager.fileExists(atPath: marker.path))
```

Add tests asserting typed failures for a non-empty regular file, a directory, a symbolic link, unavailable Chinese, and a destination whose parent path does not exist. Verify existing marker content is never overwritten when switching to English.

- [ ] **Step 2: Verify switching tests fail**

Run: `xcrun swift test --filter LanguageSwitcherTests`

Expected: FAIL because `LanguageSwitcher` is undefined.

- [ ] **Step 3: Implement the guarded marker mutation**

Use these signatures:

```swift
public enum TargetLanguage: Sendable { case english, simplifiedChinese }

public enum LanguageSwitchError: LocalizedError, Equatable {
    case chineseUnavailable(ChineseEligibility)
    case unsafeMarkerType
    case nonEmptyMarker
    case fileOperation(String)
}

public struct LanguageSwitcher: Sendable {
    public init(markerURL: URL, fileManager: FileManager = .default)
    public func switch(to target: TargetLanguage, chineseEligibility: ChineseEligibility) throws
}
```

For English, inspect the destination with `lstat`, reject symlinks and non-regular types, and create an empty file atomically only when absent. For Chinese, require `.available`, use `lstat`, require a zero-byte regular file, then remove exactly that URL. Translate Cocoa/POSIX errors into `.fileOperation(error.localizedDescription)`.

- [ ] **Step 4: Run switching and full test suites**

Run: `xcrun swift test --filter LanguageSwitcherTests && xcrun swift test`

Expected: PASS.

- [ ] **Step 5: Commit switching behavior**

Run: `git add Sources/AELanguageSwitcherCore/LanguageSwitcher.swift Tests/AELanguageSwitcherCoreTests && git commit -m "feat: switch AE language safely"`

---

### Task 4: Process Monitoring and App Model

**Files:**
- Create: `Sources/AELanguageSwitcherCore/AfterEffectsProcessMonitor.swift`
- Create: `Sources/AELanguageSwitcherCore/AppModel.swift`
- Create: `Tests/AELanguageSwitcherCoreTests/AppModelTests.swift`
- Modify: `Tests/AELanguageSwitcherCoreTests/TestSupport.swift`

**Interfaces:**
- Consumes: `AfterEffectsScanning`, `LanguageStateDetector`, `LanguageSwitcher`
- Produces: `protocol AfterEffectsProcessMonitoring`, `struct RunningAEProcess`, `@MainActor final class AppModel`

- [ ] **Step 1: Write failing orchestration tests**

Inject scanner, language detector, switcher spy, and process monitor doubles. Assert that refresh selects the highest version, switching is blocked while an AE process runs, successful switching refreshes state, and failed scanning produces a user-visible message without crashing.

```swift
await model.refresh()
XCTAssertEqual(model.installations.first?.version, "26.0.0")
XCTAssertEqual(model.selectedInstallationID, fixture26.appURL)

monitor.running = [RunningAEProcess(name: "Adobe After Effects 2026", bundleIdentifier: "com.adobe.AfterEffects.application")]
await model.requestSwitch(to: .english)
XCTAssertEqual(model.alert, .afterEffectsRunning)
XCTAssertEqual(switcherSpy.calls.count, 0)
```

- [ ] **Step 2: Verify model tests fail**

Run: `xcrun swift test --filter AppModelTests`

Expected: FAIL because monitoring and model types are undefined.

- [ ] **Step 3: Implement process monitoring and observable state**

Define:

```swift
public struct RunningAEProcess: Equatable, Sendable {
    public let name: String
    public let bundleIdentifier: String
}

public protocol AfterEffectsProcessMonitoring: Sendable {
    func runningAfterEffects() -> [RunningAEProcess]
}
```

The AppKit implementation filters `NSWorkspace.shared.runningApplications` by AE bundle identifier and excludes names containing `Render Engine`. `AppModel` publishes installations, selection, language state, running processes, status text, busy state, and a typed alert. `requestSwitch(to:)` checks processes first, checks installation availability, calls the switcher, then refreshes. `sceneBecameActive()` calls refresh.

- [ ] **Step 4: Run model and full tests**

Run: `xcrun swift test --filter AppModelTests && xcrun swift test`

Expected: PASS.

- [ ] **Step 5: Commit orchestration**

Run: `git add Sources/AELanguageSwitcherCore Tests/AELanguageSwitcherCoreTests && git commit -m "feat: coordinate AE detection and switching"`

---

### Task 5: Native SwiftUI Interface

**Files:**
- Create: `Sources/AELanguageSwitcherApp/AELanguageSwitcherApp.swift`
- Create: `Sources/AELanguageSwitcherApp/ContentView.swift`
- Create: `Sources/AELanguageSwitcherApp/Resources/Info.plist`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `AppModel` published state and `requestSwitch(to:)`
- Produces: executable product `AELanguageSwitcherApp`

- [ ] **Step 1: Add a smoke test for default dependencies**

Add `AppModelTests.testLiveDependenciesCanScanWithoutMutation`, constructing live dependencies with `/Applications` and a temporary marker URL. Call refresh and assert it finishes with either installations or the defined empty state; the test must never call switching.

- [ ] **Step 2: Run the smoke test before adding the executable UI**

Run: `xcrun swift test --filter testLiveDependenciesCanScanWithoutMutation`

Expected: PASS for core code; no executable target exists yet.

- [ ] **Step 3: Implement the single-window UI**

First add the `AELanguageSwitcherApp` executable product and target to `Package.swift`, depending on `AELanguageSwitcherCore`. `AELanguageSwitcherApp` then creates live dependencies using `/Applications`, `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]`, `UserDefaults.standard.stringArray(forKey: "AppleLanguages")`, and `NSWorkspaceProcessMonitor`.

`ContentView` must render:

- Header `AE 中英文切换器` and a colored effective-language badge.
- Version `Picker` bound to `selectedInstallationID`.
- Detail rows for version, build, path, `zh_CN`, `en_US`, and running status.
- Warning text `语言设置会影响当前用户的全部 AE 版本。`
- Buttons `切换到中文` and `Switch to English`, disabled for current language, missing AE, unavailable Chinese, or busy state.
- `重新扫描` and `帮助` controls.
- Alerts for running AE, unsafe marker, missing Chinese prerequisites, and file errors.
- `scenePhase` refresh when the app becomes active.

Set the window to a fixed minimum size of 560×460 points, use standard macOS controls, and avoid custom assets in the first release.

- [ ] **Step 4: Build and manually launch from SwiftPM**

Run: `xcrun swift build -c debug`

Expected: build succeeds and `.build/debug/AELanguageSwitcherApp` exists. Launch it from Finder or Terminal, verify the current machine shows AE `26.0.0`, build `26.0.0.67`, both locales, and Simplified Chinese without modifying the marker.

- [ ] **Step 5: Commit the UI**

Run: `git add Sources/AELanguageSwitcherApp Package.swift && git commit -m "feat: add native AE language switcher UI"`

---

### Task 6: App Packaging, Documentation, and Final Verification

**Files:**
- Create: `scripts/package_app.sh`
- Create: `README.md`
- Create during build: `outputs/AE中英文切换器.app`

**Interfaces:**
- Consumes: release executable `AELanguageSwitcherApp` and `Info.plist`
- Produces: double-clickable unsigned `.app` bundle

- [ ] **Step 1: Write the packaging script and documentation**

The script must use `set -euo pipefail`, resolve the repository root, run `xcrun swift build -c release`, recreate only the explicit path `outputs/AE中英文切换器.app`, copy the executable to `Contents/MacOS/AE中英文切换器`, copy `Info.plist`, and apply ad-hoc signing:

```bash
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
```

`README.md` documents supported macOS/AE behavior, the global marker limitation, safe-file rules, build/test/package commands, unsigned distribution warning, and later Developer ID commands using shell environment variables such as `$DEVELOPER_ID_APPLICATION` rather than fabricated identities.

- [ ] **Step 2: Run the complete automated suite**

Run: `xcrun swift test`

Expected: every XCTest passes with zero failures.

- [ ] **Step 3: Package and inspect the app**

Run: `bash scripts/package_app.sh`

Expected: `outputs/AE中英文切换器.app/Contents/MacOS/AE中英文切换器` exists and `codesign --verify --deep --strict` exits 0.

Run: `plutil -lint 'outputs/AE中英文切换器.app/Contents/Info.plist' && codesign -dv --verbose=2 'outputs/AE中英文切换器.app'`

Expected: plist is valid; the signature reports ad-hoc signing.

- [ ] **Step 4: Perform read-only real-machine acceptance checks**

Launch the packaged app without clicking either language button. Verify:

- AE 2026 is listed as `26.0.0` / `26.0.0.67`.
- `zh_CN` and `en_US` are available.
- macOS first language is shown as Simplified Chinese.
- Current language is Simplified Chinese when the marker is absent.
- The UI states that switching affects all AE versions.

Then start AE, return to the tool, and verify both switch actions produce the exit-AE alert and do not change the marker.

- [ ] **Step 5: Commit packaging and docs**

Run: `git add scripts/package_app.sh README.md Sources/AELanguageSwitcherApp/Resources/Info.plist && git commit -m "build: package AE language switcher app"`

- [ ] **Step 6: Record final verification evidence**

Save the exact `swift test`, `codesign --verify`, plist lint, and real-machine scan results in the task handoff. Do not claim switching was exercised against the real user marker unless the user explicitly clicked it.
