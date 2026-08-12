# AE Language Switcher Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the detailed two-button window with a compact one-button language toggle and ship the provided purple “中 / En” artwork as the macOS application icon.

**Architecture:** Keep scanner, process-monitor, language-state, and safe marker-mutation services unchanged. Add a small testable primary-action projection to `AppModel`, rebuild `ContentView` around it, and generate a standard `.icns` through a dedicated asset script consumed by the package script.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, XCTest, Swift Package Manager, `sips`, `iconutil`, `codesign`, macOS 13+

## Global Constraints

- Preserve the existing safe marker mutation and fresh running-AE process check.
- Do not expose version, build, path, locale-resource, or running-process detail rows in the main window.
- Show one dynamic primary button, a read-only `中文 | English` status at top right, and `重新扫描`.
- Keep an otherwise relevant action clickable while AE runs so the existing exit-AE alert remains reachable.
- Use the user-provided icon artwork without creatively changing its composition.
- Build deliverables only under `/Users/dadaozei/Documents/Codex/2026-08-08/xie/outputs`.
- Git metadata is unavailable; record intended commits instead of attempting Git operations.

---

### Task 1: Testable Single-Button Action Projection

**Files:**
- Modify: `Sources/AELanguageSwitcherCore/AppModel.swift`
- Modify: `Tests/AELanguageSwitcherCoreTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `LanguageState.effective`, `TargetLanguage`, `isSwitchActionEnabled(to:)`
- Produces: `public var primarySwitchTarget: TargetLanguage?`, `public var isPrimarySwitchEnabled: Bool`

- [ ] **Step 1: Add failing projection tests**

Add exact cases:

```swift
XCTAssertEqual(chineseModel.primarySwitchTarget, .english)
XCTAssertEqual(englishModel.primarySwitchTarget, .simplifiedChinese)
XCTAssertNil(unscannedModel.primarySwitchTarget)
XCTAssertNil(systemDefaultModel.primarySwitchTarget)
```

Also assert a running AE process does not by itself disable an otherwise relevant primary action, while `requestSwitch` still makes zero switch calls and sets `.afterEffectsRunning`.

- [ ] **Step 2: Run focused test and verify RED**

Run: `xcrun swift test --filter AppModelTests`

Expected: compile failure because the projection properties do not exist.

- [ ] **Step 3: Implement minimal projection**

```swift
public var primarySwitchTarget: TargetLanguage? {
    guard let languageState else { return nil }
    switch languageState.effective {
    case .simplifiedChinese: return .english
    case .english: return .simplifiedChinese
    case .systemDefault: return nil
    }
}

public var isPrimarySwitchEnabled: Bool {
    guard let primarySwitchTarget else { return false }
    return isSwitchActionEnabled(to: primarySwitchTarget)
}
```

Do not change `requestSwitch`, process checking, or switcher services.

- [ ] **Step 4: Run focused and full suites**

Run: `xcrun swift test --filter AppModelTests && xcrun swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 5: Record intended commit**

Record `feat: add primary language toggle projection`.

---

### Task 2: Compact SwiftUI Window

**Files:**
- Modify: `Sources/AELanguageSwitcherApp/ContentView.swift`
- Modify: `Sources/AELanguageSwitcherApp/AELanguageSwitcherApp.swift`

**Interfaces:**
- Consumes: `AppModel.primarySwitchTarget`, `AppModel.isPrimarySwitchEnabled`, existing alerts and refresh
- Produces: compact 420×260 point single-window UI

- [ ] **Step 1: Replace detailed content hierarchy**

Remove the scroll view, global warning, picker, detail rows, two-button row, eligibility paragraph, and help button. Build one `VStack` containing:

```swift
HStack { Text("AE 语言切换"); Spacer(); languageStatus }
Spacer()
primarySwitchButton
Spacer()
HStack { compactStatus; Spacer(); Button("重新扫描") { model.refresh() } }
```

Use a softly tinted rounded container for the main action and standard macOS colors that work in dark mode.

- [ ] **Step 2: Implement exact state presentation**

Top right always shows both `中文` and `English`; the active item gets a small circle, semibold text, and purple/indigo accent. The inactive item is gray. Detection and system-default states highlight neither.

Primary labels:

- Target `.english`: `切换到 English`
- Target `.simplifiedChinese`: `切换到中文`
- Busy without target: `正在扫描…`
- No installation: `未检测到 After Effects`
- Other indeterminate state: `无法确定当前语言`

Click calls `model.requestSwitch(to:)`. Disable only for no target, unavailable target, no installation, or busy state. Running AE remains click-to-alert.

- [ ] **Step 3: Preserve alerts and lifecycle**

Keep the exhaustive Chinese alert mapping, first-load `.task`, active-scene refresh, and dismissal binding. Bottom status is one quiet line.

- [ ] **Step 4: Resize and verify build**

Change the singleton window frame to `minWidth: 420, minHeight: 260`.

Run: `xcrun swift build -c debug && xcrun swift test`

Expected: build and tests pass.

- [ ] **Step 5: Record intended commit**

Record `feat: simplify AE language switcher interface`.

---

### Task 3: App Icon, Packaging, and Verification

**Files:**
- Copy: `/var/folders/zy/n5kt51xx3yz_0qxd48rmfdkm0000gn/T/codex-clipboard-dc371cb5-8c95-4714-b4cd-b7d5cb1974dd.png` → `Sources/AELanguageSwitcherApp/Resources/AppIconSource.png`
- Create: `scripts/make_app_icon.sh`
- Create: `Sources/AELanguageSwitcherApp/Resources/AppIcon.icns`
- Modify: `Sources/AELanguageSwitcherApp/Resources/Info.plist`
- Modify: `scripts/package_app.sh`
- Modify: `README.md`
- Rebuild: `outputs/AE中英文切换器.app`

**Interfaces:**
- Consumes: square source PNG
- Produces: `AppIcon.icns`, referenced by `CFBundleIconFile` and embedded under `Contents/Resources`

- [ ] **Step 1: Preserve source and generate iconset**

Copy the provided PNG byte-for-byte. `scripts/make_app_icon.sh` uses `set -euo pipefail`, resolves the root, validates a square source, creates a temporary iconset, and uses `sips -z` for:

```text
icon_16x16.png 16×16
icon_16x16@2x.png 32×32
icon_32x32.png 32×32
icon_32x32@2x.png 64×64
icon_128x128.png 128×128
icon_128x128@2x.png 256×256
icon_256x256.png 256×256
icon_256x256@2x.png 512×512
icon_512x512.png 512×512
icon_512x512@2x.png 1024×1024
```

Run `iconutil -c icns` to produce `Resources/AppIcon.icns`. Clean only the script-created temporary directory.

- [ ] **Step 2: Wire icon metadata and package resource**

Add:

```xml
<key>CFBundleExecutable</key><string>AE中英文切换器</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
```

Update `package_app.sh` to run the icon script, create `Contents/Resources`, and copy `AppIcon.icns` before signing.

- [ ] **Step 3: Update documentation**

Document the compact UI, one-button behavior, icon source, `bash scripts/make_app_icon.sh`, and packaging command while retaining safety/distribution notes.

- [ ] **Step 4: Run complete verification**

Run each command and require exit 0:

```bash
xcrun swift test
bash scripts/package_app.sh
plutil -lint 'outputs/AE中英文切换器.app/Contents/Info.plist'
codesign --verify --deep --strict 'outputs/AE中英文切换器.app'
test -f 'outputs/AE中英文切换器.app/Contents/Resources/AppIcon.icns'
```

- [ ] **Step 5: Perform read-only launch check**

Launch only the packaged tool without clicking the switch button. Confirm its exact executable runs, terminate only that tool normally, and confirm the real marker state is unchanged.

- [ ] **Step 6: Record artifact**

Record `build: add app icon and package compact UI`; deliver `/Users/dadaozei/Documents/Codex/2026-08-08/xie/outputs/AE中英文切换器.app`.
