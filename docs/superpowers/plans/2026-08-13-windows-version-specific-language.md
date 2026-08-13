# Windows Version-Specific AE Language Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Detect every installed After Effects version and safely persist zh_CN or en_US for only the selected version.

**Architecture:** Replace global-marker-derived language state with a version preference boundary that locates, parses, backs up, atomically edits, verifies, and rolls back each version's Debug Database.txt. Keep installation discovery, preference I/O, legacy marker migration, and WPF orchestration in separate tested units. Expose all installations and an explicit selection in the ViewModel.

**Tech Stack:** .NET 8, C# 12, MSTest, WPF, PowerShell build tooling, Windows ICO resources.

## Global Constraints

- Never modify Program Files or require administrator rights.
- Never modify preferences while any AfterFX.exe process is running.
- Do not create a missing Debug Database.txt; require one normal start and exit first.
- Preserve encoding, BOM, newline style, unrelated lines, and the third/default column.
- Back up before mutation, atomically replace, read back, and roll back preferences and marker on failure.
- Refuse unsafe, non-empty, directory, and reparse-point legacy markers.
- Reuse Sources/AELanguageSwitcherApp/Resources/AppIconSource.png for Windows.
- Do not overwrite the desktop EXE; publish user deliverables to the configured outputs directory.
- Do not save or print tokens.

---

### Task 1: Version preference location and parsing

**Files:**
- Create: windows/src/AELanguageSwitcher.Core/VersionLanguagePreferences.cs
- Create: windows/tests/AELanguageSwitcher.Core.Tests/VersionLanguagePreferencesTests.cs
- Modify: windows/src/AELanguageSwitcher.Core/Domain.cs

**Interfaces:**
- Consumes: AEInstallation.Version and an injected After Effects preferences root.
- Produces: VersionLanguagePreferenceLocator.GetDatabasePath(AEInstallation), DebugDatabaseParser.Parse(byte[]), VersionLanguageState, and PreferenceFormatException.

- [ ] **Step 1: Write failing locator and parser tests**

Use literal fixtures proving 25.3.0x5 maps to 25.3/Debug Database.txt and 24.6.2 maps to 24.6/Debug Database.txt. Test UTF-8 BOM/no-BOM, CRLF/LF, en_US, zh_CN, blank, unknown, missing, duplicate, and malformed rows. The production mutation caught is choosing the wrong version folder or accepting an ambiguous language row.

- [ ] **Step 2: Run tests and verify RED**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter VersionLanguagePreferencesTests
~~~

Expected: compilation fails because the new types and EffectiveLanguage.Unknown do not exist.

- [ ] **Step 3: Implement minimal parser code**

Add EffectiveLanguage.Unknown and these contracts:

~~~csharp
public sealed record VersionLanguageState(
    EffectiveLanguage Effective,
    string RawLanguage,
    string DatabasePath,
    bool IsFallback);

public sealed record ParsedDebugDatabase(
    string Language,
    TextFileFormat Format,
    IReadOnlyList<string> Lines,
    int LanguageLineIndex);

public sealed record TextFileFormat(Encoding Encoding, bool HasBom, string NewLine);
~~~

The locator accepts numeric major/minor components only. The parser detects encoding/newlines, requires exactly one ApplicationLanguage row with at least three tab-separated columns, and maps only en_US and zh_CN as known.

- [ ] **Step 4: Verify GREEN and regression suite**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter VersionLanguagePreferencesTests
dotnet test windows/AELanguageSwitcher.Windows.sln
~~~

Expected: all tests pass.

- [ ] **Step 5: Commit**

~~~powershell
git add windows/src/AELanguageSwitcher.Core/Domain.cs windows/src/AELanguageSwitcher.Core/VersionLanguagePreferences.cs windows/tests/AELanguageSwitcher.Core.Tests/VersionLanguagePreferencesTests.cs
git commit -m "add version language preference parser"
~~~

### Task 2: Exact-version detection with CCX fallback

**Files:**
- Modify: windows/src/AELanguageSwitcher.Core/VersionLanguagePreferences.cs
- Modify: windows/src/AELanguageSwitcher.Core/LanguageDetection.cs
- Modify: windows/tests/AELanguageSwitcher.Core.Tests/VersionLanguagePreferencesTests.cs
- Modify: windows/tests/AELanguageSwitcher.Core.Tests/LanguageDetectionTests.cs

**Interfaces:**
- Produces IVersionLanguageDetector.Detect(AEInstallation) and IProductLanguageHistory.GetLatest(string productVersion).

- [ ] **Step 1: Write failing detection tests**

Prove the database value wins, blank values use only the newest exact-version CCX record, a 25.3 record never supplies 25.1, unknown stays Unknown, and a missing database returns a typed missing state rather than an OS-language guess.

- [ ] **Step 2: Verify RED**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter "LanguageDetectionTests|VersionLanguagePreferencesTests"
~~~

Expected: compilation fails because the new detector and history interfaces do not exist.

- [ ] **Step 3: Implement detection**

~~~csharp
public interface IVersionLanguageDetector
{
    VersionLanguageState Detect(AEInstallation installation);
}

public interface IProductLanguageHistory
{
    string? GetLatest(string productVersion);
}
~~~

The live reader scans AEFT JSON filenames under the user's Adobe/CCX Welcome directory, extracts version and locale from AEFT-25-3-en_US-<id>.json, matches normalized major/minor exactly, and chooses the newest matching file. It does not parse unrelated logs.

- [ ] **Step 4: Verify GREEN and commit**

Run filtered and full solution tests, then commit the four files with message "detect language for each AE version".

### Task 3: Transactional preference write and marker migration

**Files:**
- Create: windows/src/AELanguageSwitcher.Core/VersionLanguageSwitcher.cs
- Create: windows/tests/AELanguageSwitcher.Core.Tests/VersionLanguageSwitcherTests.cs
- Modify: windows/src/AELanguageSwitcher.Core/MarkerSwitcher.cs
- Modify: windows/tests/AELanguageSwitcher.Core.Tests/MarkerSwitcherTests.cs

**Interfaces:**
- Produces IVersionLanguageSwitcher.Switch(AEInstallation, TargetLanguage) and ILegacyMarkerTransaction.Commit().

- [ ] **Step 1: Write failing rewrite tests**

With real temporary files, prove only column two changes, column three and unrelated lines remain unchanged, BOM/newlines are preserved, a timestamped backup exists, and read-back matches. Inject failures after backup, marker migration, replace, and before verification; every case must restore database and marker.

- [ ] **Step 2: Write failing marker transaction tests**

Test absent marker as no-op, zero-byte regular marker moving to unique quarantine, commit retaining quarantine, rollback restoring the marker, and non-empty/directory/reparse markers refusing mutation.

- [ ] **Step 3: Verify RED**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter "VersionLanguageSwitcherTests|MarkerSwitcherTests"
~~~

Expected: compilation fails because transactional interfaces do not exist.

- [ ] **Step 4: Implement minimal transaction**

~~~csharp
public interface IVersionLanguageSwitcher
{
    VersionLanguageState Switch(AEInstallation installation, TargetLanguage target);
}

public interface ILegacyMarkerTransaction : IDisposable
{
    void Commit();
}
~~~

Write the replacement beside the original, flush to disk, use File.Replace, parse the result, and restore the timestamped backup if verification fails. Convert MarkerSwitcher into the focused legacy migrator and remove global marker switching from live wiring.

- [ ] **Step 5: Verify GREEN and commit**

Run filtered and full tests. Commit with message "switch selected AE version language safely".

### Task 4: Multi-version ViewModel

**Files:**
- Modify: windows/src/AELanguageSwitcher.Core/MainViewModel.cs
- Modify: windows/tests/AELanguageSwitcher.Core.Tests/MainViewModelTests.cs

**Interfaces:**
- Produces Installations, writable SelectedInstallation, SwitchToChineseCommand, SwitchToEnglishCommand, and version/resource/status display properties.

- [ ] **Step 1: Write failing ViewModel tests**

Prove all versions appear in descending order, highest is initially selected, refresh preserves the same executable path, a missing selection falls back, selection changes detect without writing, the current-language button disables, Unknown enables both available targets, missing locale disables only its target, and running AE causes zero mutations.

- [ ] **Step 2: Verify RED**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter MainViewModelTests
~~~

Expected: compilation fails because the new collection, selection setter, and commands do not exist.

- [ ] **Step 3: Implement minimal ViewModel behavior**

~~~csharp
public IReadOnlyList<AEInstallation> Installations { get; private set; }
public AEInstallation? SelectedInstallation { get; set; }
public ICommand SwitchToChineseCommand { get; }
public ICommand SwitchToEnglishCommand { get; }
public string SelectedVersionLabel { get; }
public string InstallationPath { get; }
public string ResourceStatus { get; }
~~~

Refresh stores the previous executable path and restores it case-insensitively. Switching checks processes immediately before mutation, invokes only the selected version switcher, rereads, and reports success only when the read-back language matches.

- [ ] **Step 4: Verify GREEN and commit**

Run filtered and full tests. Commit with message "add multi-version Windows language controls".

### Task 5: WPF layout and live wiring

**Files:**
- Modify: windows/src/AELanguageSwitcher.App/App.xaml.cs
- Modify: windows/src/AELanguageSwitcher.App/MainWindow.xaml
- Modify: windows/src/AELanguageSwitcher.App/MainWindow.xaml.cs
- Modify: windows/src/AELanguageSwitcher.App/WpfUserDialog.cs
- Create: windows/tests/AELanguageSwitcher.Core.Tests/WpfResourceTests.cs

- [ ] **Step 1: Write a failing XAML behavior test**

Load MainWindow.xaml as XML. Assert one ComboBox binds ItemsSource=Installations and SelectedItem=SelectedInstallation, and two buttons bind the two target commands. This catches removal of required controls without testing WPF framework behavior.

- [ ] **Step 2: Verify RED**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter WpfResourceTests
~~~

Expected: test fails because the current XAML lacks the selector and two target buttons.

- [ ] **Step 3: Implement layout and wiring**

Use a resizable minimum 520x390 window with a labeled version ComboBox, read-only version/path/resource/status rows, two equal target buttons, and rescan. Keep Chinese accessible names. Replace old marker language services with the preference locator, detector, marker migrator, and version switcher.

- [ ] **Step 4: Verify GREEN and commit**

Run the XAML test and full suite. Commit with message "update Windows multi-version interface".

### Task 6: Reuse the macOS icon

**Files:**
- Create: scripts/make_windows_icon.ps1
- Create: windows/src/AELanguageSwitcher.App/Resources/AppIcon.ico
- Modify: windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj
- Modify: windows/src/AELanguageSwitcher.App/MainWindow.xaml
- Create: windows/tests/AELanguageSwitcher.Core.Tests/WindowsIconTests.cs

- [ ] **Step 1: Write a failing icon test**

Parse the ICO header and require square 16, 32, 48, and 256 pixel frames. Parse project/XAML XML and require ApplicationIcon=Resources/AppIcon.ico plus the window icon URI.

- [ ] **Step 2: Verify RED**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter WindowsIconTests
~~~

Expected: fail because the ICO and references do not exist.

- [ ] **Step 3: Generate and wire the icon**

Create a repeatable PowerShell wrapper using the bundled workspace Python/Pillow runtime. Resize AppIconSource.png to 16, 24, 32, 48, 64, 128, and 256 pixels with Lanczos and save one ICO. Add it as a WPF Resource and ApplicationIcon without altering source artwork.

- [ ] **Step 4: Verify GREEN and commit**

~~~powershell
powershell -ExecutionPolicy Bypass -File scripts/make_windows_icon.ps1
dotnet test windows/AELanguageSwitcher.Windows.sln --filter WindowsIconTests
dotnet test windows/AELanguageSwitcher.Windows.sln
~~~

Commit with message "reuse macOS icon for Windows app".

### Task 7: Documentation, build, and deliverables

**Files:**
- Modify: README.md
- Modify: MAINTENANCE.md
- Build: windows/artifacts/win-x64/AE-Language-Switcher.exe
- Deliver: outputs/AE-Language-Switcher-win-x64.exe
- Deliver: outputs/AE-Language-Switcher-win-x64.exe.sha256

- [ ] **Step 1: Update documentation**

Document multi-version selection, ApplicationLanguage persistence, internal-preference caveat, mandatory AE shutdown, backup/rollback, global marker migration, normal-launch persistence, and Adobe update/reset limitations. Remove obsolete Windows claims based only on marker and OS language.

- [ ] **Step 2: Run complete verification**

~~~powershell
dotnet test windows/AELanguageSwitcher.Windows.sln -c Release
git diff --check
rg -n "TB[D]|PLACEHOLD[E]R" README.md MAINTENANCE.md windows scripts
~~~

Expected: tests pass, diff check is clean, placeholder scan has no matches.

- [ ] **Step 3: Build and publish**

~~~powershell
dotnet build windows/AELanguageSwitcher.Windows.sln -c Release
dotnet publish windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -o windows/artifacts/win-x64
~~~

Expected: both exit zero and one self-contained AE-Language-Switcher.exe is present.

- [ ] **Step 4: Generate and verify checksum**

Compute SHA-256 with Get-FileHash, write lowercase hash plus filename to the .sha256 file, reread it, and independently recompute the hash. Values must match.

- [ ] **Step 5: Smoke-test without changing AE**

Launch the published switcher, wait for its main window, confirm it remains alive for two seconds, then close only the switcher. Do not click language buttons.

- [ ] **Step 6: Copy deliverables without touching Desktop**

Copy the EXE/checksum to the configured outputs directory. Verify the desktop EXE still has SHA-256 F2AC167E2ACC867E527D4793AF1134EEBD0452334ED08D762594759C30234AA7.

- [ ] **Step 7: Commit and report**

Commit documentation with message "document version-specific Windows switching". Report test count, build/publish status, output links, EXE size/hash, commits, clean/dirty Git state, desktop preservation, and that the running AE 2025 must be closed before an actual language switch.
