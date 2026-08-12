# Windows AE Language Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Windows 10/11 x64 WPF application that safely switches After Effects between Simplified Chinese and English, then publish a self-contained single-file executable from a public GitHub repository.

**Architecture:** A dependency-free .NET 8 core library owns installation discovery, eligibility, process checks, marker inspection, and safe mutations. A small WPF layer consumes one `MainViewModel`; all platform boundaries are expressed as narrow interfaces so core behavior can be tested with deterministic fakes. GitHub Actions runs Windows tests and creates the x64 executable and checksum for tagged releases.

**Tech Stack:** C# 12, .NET 8, WPF, MSTest, Microsoft.Win32 registry APIs, System.IO, GitHub Actions.

## Global Constraints

- Target Windows 10/11 x64 only.
- Release one self-contained, single-file `AE-Language-Switcher-Windows-x64.exe` that does not require a preinstalled .NET runtime.
- Do not modify Premiere Pro, Photoshop, Creative Cloud, Windows global language settings, or any AE installation directory.
- Do not request administrator privileges, start AE, terminate AE, or recursively delete any path.
- Use `Environment.SpecialFolder.MyDocuments`; never construct `%USERPROFILE%\Documents` manually.
- English is enabled only through the current user's `ae_force_english.txt` marker.
- Simplified Chinese requires both identifiable AE Chinese resources and a `zh-CN`/`zh-Hans` preferred Windows UI language.
- Reject directories, symbolic links, junctions, other reparse points, and non-empty marker files.
- Keep the existing macOS Swift package behavior and tests intact.
- Do not add an open-source license in this release.
- The Windows executable is unsigned; documentation must disclose the possible SmartScreen warning.

---

### Task 1: Repository hygiene and Windows solution skeleton

**Files:**
- Create: `.gitignore`
- Create: `windows/AELanguageSwitcher.Windows.sln`
- Create: `windows/src/AELanguageSwitcher.Core/AELanguageSwitcher.Core.csproj`
- Create: `windows/src/AELanguageSwitcher.Core/Domain.cs`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/AELanguageSwitcher.Core.Tests.csproj`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/DomainTests.cs`

**Interfaces:**
- Produces: `AELocale`, `EffectiveLanguage`, `TargetLanguage`, `ChineseEligibility`, `AEInstallation`, `LanguageState`, and `SemanticVersionComparer` in namespace `AELanguageSwitcher.Core`.
- Consumes: no Windows project types.

- [ ] **Step 1: Add repository exclusions**

Create `.gitignore` with exact entries:

```gitignore
.DS_Store
.build/
.superpowers/
outputs/
work/
windows/**/bin/
windows/**/obj/
windows/artifacts/
*.user
*.suo
```

- [ ] **Step 2: Create the solution and project files**

Use SDK-style projects targeting `net8.0` for core/tests. The test project references `MSTest.TestAdapter` and `MSTest.TestFramework` version `3.6.4`, sets `IsTestProject=true`, and references the core project. Add both projects to `windows/AELanguageSwitcher.Windows.sln`.

- [ ] **Step 3: Write failing domain tests**

Create tests that hand-derive the expected ordering:

```csharp
[TestMethod]
public void SemanticVersionsSortNumericallyDescending()
{
    var versions = new[] { "9.9", "26.0", "25.10", "25.2" };
    Array.Sort(versions, SemanticVersionComparer.Descending);
    CollectionAssert.AreEqual(new[] { "26.0", "25.10", "25.2", "9.9" }, versions);
}

[TestMethod]
public void InstallationIdentityUsesExecutablePath()
{
    var installation = new AEInstallation("After Effects", "26.0", @"C:\\AE\\Support Files\\AfterFX.exe", new HashSet<AELocale>());
    Assert.AreEqual(@"C:\\AE\\Support Files\\AfterFX.exe", installation.Id);
}
```

- [ ] **Step 4: Run tests and verify RED**

Run on Windows or a Windows GitHub Actions runner:

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter DomainTests
```

Expected: compilation fails because the domain types do not exist.

- [ ] **Step 5: Implement minimal domain types**

Define immutable records/enums and a comparer that splits on `.` and compares integer components with missing components treated as zero:

```csharp
public enum AELocale { EnglishUS, SimplifiedChinese }
public enum EffectiveLanguage { English, SimplifiedChinese, SystemDefault }
public enum TargetLanguage { English, SimplifiedChinese }
public enum ChineseEligibility { Available, MissingResource, SystemLanguageNotSimplifiedChinese }

public sealed record AEInstallation(
    string DisplayName,
    string Version,
    string ExecutablePath,
    IReadOnlySet<AELocale> AvailableLocales)
{
    public string Id => ExecutablePath;
}

public sealed record LanguageState(
    EffectiveLanguage Effective,
    ChineseEligibility ChineseEligibility,
    bool MarkerExists,
    string PreferredLanguage);
```

- [ ] **Step 6: Run domain tests and commit**

Run `dotnet test windows/AELanguageSwitcher.Windows.sln --filter DomainTests`. Expected: PASS.

```bash
git add .gitignore windows/AELanguageSwitcher.Windows.sln windows/src/AELanguageSwitcher.Core windows/tests/AELanguageSwitcher.Core.Tests
git commit -m "build Windows core skeleton"
```

### Task 2: Discover and rank After Effects installations

**Files:**
- Create: `windows/src/AELanguageSwitcher.Core/InstallationScanner.cs`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/InstallationScannerTests.cs`

**Interfaces:**
- Produces: `IInstallationSource.GetCandidates()`, `IExecutableMetadata.Read(string)`, and `InstallationScanner.Scan()`.
- Consumes: `AEInstallation`, `AELocale`, and `SemanticVersionComparer` from Task 1.

- [ ] **Step 1: Write failing scanner tests with controlled candidates**

Use fake sources and metadata to test all observable behavior:

```csharp
[TestMethod]
public void ScanDeduplicatesFiltersAndSortsCandidates()
{
    var source = new CandidateSourceFake(
        @"C:\\Adobe\\Adobe After Effects 25",
        @"C:\\Adobe\\Adobe After Effects 26",
        @"C:\\Adobe\\Adobe After Effects Render Engine 27",
        @"C:\\Adobe\\Adobe After Effects 26");
    var metadata = new ExecutableMetadataFake()
        .Add(@"C:\\Adobe\\Adobe After Effects 25\\Support Files\\AfterFX.exe", "After Effects", "25.2")
        .Add(@"C:\\Adobe\\Adobe After Effects 26\\Support Files\\AfterFX.exe", "After Effects", "26.0");

    var result = new InstallationScanner(source, metadata, new ResourceProbeFake()).Scan();

    CollectionAssert.AreEqual(new[] { "26.0", "25.2" }, result.Select(x => x.Version).ToArray());
}
```

Add separate tests proving malformed candidates are ignored, Render Engine is excluded case-insensitively, and `zh_CN`/`en_US` resource probes populate locales.

- [ ] **Step 2: Run scanner tests and verify RED**

Run:

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter InstallationScannerTests
```

Expected: compilation fails because scanner interfaces and types do not exist.

- [ ] **Step 3: Implement scanner boundaries**

Define:

```csharp
public interface IInstallationSource { IEnumerable<string> GetCandidates(); }
public interface IExecutableMetadata { ExecutableMetadata? Read(string executablePath); }
public interface IResourceProbe { IReadOnlySet<AELocale> Detect(string installationDirectory); }
public sealed record ExecutableMetadata(string DisplayName, string Version);
```

`InstallationScanner.Scan()` must normalize full paths, deduplicate with `StringComparer.OrdinalIgnoreCase`, append `Support Files\AfterFX.exe`, ignore candidate-level exceptions, and sort with the numeric comparer.

- [ ] **Step 4: Implement live registry and directory sources**

Add `WindowsInstallationSource` in the same file. Read both `RegistryView.Registry64` and `RegistryView.Registry32` under:

```text
SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
```

Accept entries whose `DisplayName` starts with `Adobe After Effects` and whose `InstallLocation` is non-empty. Add fallback directories beneath `%ProgramFiles%\Adobe` and `%ProgramFiles(x86)%\Adobe`. Candidate enumeration must be read-only and tolerate missing registry keys and inaccessible directories.

Use `FileVersionInfo.GetVersionInfo` for live executable metadata. Resource probing checks case-insensitively for `zh_CN` and `en_US` under known immediate descendants of `Support Files`, including `Dictionaries`, `AMT`, and `Resources`; it never recurses outside the selected installation.

- [ ] **Step 5: Run scanner tests and commit**

Run `dotnet test windows/AELanguageSwitcher.Windows.sln --filter InstallationScannerTests`. Expected: PASS.

```bash
git add windows/src/AELanguageSwitcher.Core/InstallationScanner.cs windows/tests/AELanguageSwitcher.Core.Tests/InstallationScannerTests.cs
git commit -m "add Windows AE discovery"
```

### Task 3: Detect language eligibility and running AE processes

**Files:**
- Create: `windows/src/AELanguageSwitcher.Core/LanguageDetection.cs`
- Create: `windows/src/AELanguageSwitcher.Core/ProcessMonitor.cs`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/LanguageDetectionTests.cs`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/ProcessMonitorTests.cs`

**Interfaces:**
- Produces: `ILanguageEnvironment`, `LanguageStateDetector.Detect(AEInstallation)`, `IAfterEffectsProcessMonitor.IsRunning()`.
- Consumes: domain types from Task 1.

- [ ] **Step 1: Write failing language-state tests**

Use a fake environment exposing `MarkerExists` and `PreferredLanguages`. Include literal expectations for:

```csharp
[DataRow(true, "zh-CN", true, EffectiveLanguage.English, ChineseEligibility.Available)]
[DataRow(false, "zh-CN", true, EffectiveLanguage.SimplifiedChinese, ChineseEligibility.Available)]
[DataRow(false, "en-US", true, EffectiveLanguage.SystemDefault, ChineseEligibility.SystemLanguageNotSimplifiedChinese)]
[DataRow(false, "zh-CN", false, EffectiveLanguage.SystemDefault, ChineseEligibility.MissingResource)]
```

Also prove `zh-Hans`, `zh-Hans-CN`, and `zh_CN` are accepted, while `zh-TW` and `zh-Hant` are rejected.

- [ ] **Step 2: Write failing process tests**

Inject process names and verify only exact `AfterFX` (case-insensitive) blocks switching; `aerender`, Premiere, and Photoshop do not.

- [ ] **Step 3: Run tests and verify RED**

Run:

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter "LanguageDetectionTests|ProcessMonitorTests"
```

Expected: compilation fails because detector and monitor types do not exist.

- [ ] **Step 4: Implement detector and live providers**

Define `ILanguageEnvironment.MarkerExists`, `ILanguageEnvironment.PreferredLanguages`, and `WindowsLanguageEnvironment`. Read the marker from `Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments)` and preferred languages from `CultureInfo.CurrentUICulture.Name` followed by `InstalledUICulture.Name`, deduplicated case-insensitively.

`LanguageStateDetector` uses the first language and the selected installation's locale set. Marker existence takes precedence over eligibility.

Define `IProcessSnapshot.GetProcessNames()` and `AfterEffectsProcessMonitor.IsRunning()`; live implementation uses `Process.GetProcesses()` and disposes every process object.

- [ ] **Step 5: Run tests and commit**

Run the filtered command from Step 3. Expected: PASS.

```bash
git add windows/src/AELanguageSwitcher.Core/LanguageDetection.cs windows/src/AELanguageSwitcher.Core/ProcessMonitor.cs windows/tests/AELanguageSwitcher.Core.Tests/LanguageDetectionTests.cs windows/tests/AELanguageSwitcher.Core.Tests/ProcessMonitorTests.cs
git commit -m "add Windows language detection"
```

### Task 4: Implement race-resistant marker switching

**Files:**
- Create: `windows/src/AELanguageSwitcher.Core/MarkerSwitcher.cs`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/MarkerSwitcherTests.cs`

**Interfaces:**
- Produces: `ILanguageSwitcher.Switch(TargetLanguage, ChineseEligibility)`, `LanguageSwitchException`, and `MarkerSwitcher`.
- Consumes: `TargetLanguage` and `ChineseEligibility` from Task 1.

- [ ] **Step 1: Write failing English marker tests**

Use a fresh temporary Documents directory for each test. Verify English creates a zero-byte file, repeated English is idempotent, an existing non-empty regular file is preserved, and directory/reparse-point marker paths throw typed errors without modifying targets.

```csharp
[TestMethod]
public void EnglishCreatesZeroByteMarker()
{
    var marker = Path.Combine(_documents, "ae_force_english.txt");
    new MarkerSwitcher(marker).Switch(TargetLanguage.English, ChineseEligibility.Available);
    Assert.AreEqual(0, new FileInfo(marker).Length);
}
```

- [ ] **Step 2: Write failing Chinese marker tests**

Verify Chinese removes only a zero-byte ordinary file; no marker is idempotent; non-empty files, directories, symbolic links, and junctions remain; unavailable eligibility throws before mutation. Add a controlled hook that replaces the checked marker before deletion and assert the replacement survives.

- [ ] **Step 3: Run marker tests and verify RED**

Run:

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter MarkerSwitcherTests
```

Expected: compilation fails because marker switching types do not exist.

- [ ] **Step 4: Implement safe inspection and creation**

Inspect with `File.GetAttributes` using `FileAttributes.ReparsePoint` and `FileAttributes.Directory`. English creation uses:

```csharp
using var stream = new FileStream(markerPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
```

Treat `IOException` caused by a competing creator as a retry, then reinspect. Existing ordinary files are left unchanged.

- [ ] **Step 5: Implement safe Chinese removal**

Open the marker with `FileMode.Open`, `FileAccess.Read`, and `FileShare.None`; reject nonzero length. Reinspect attributes and file length immediately before deletion. If identity or type changes, throw `LanguageSwitchException` and do not call recursive APIs. Delete only with `File.Delete(markerPath)`.

Map failures to exact codes: `ChineseUnavailable`, `UnsafeMarkerType`, `NonEmptyMarker`, and `FileOperation`.

- [ ] **Step 6: Run marker tests and commit**

Run `dotnet test windows/AELanguageSwitcher.Windows.sln --filter MarkerSwitcherTests`. Expected: PASS.

```bash
git add windows/src/AELanguageSwitcher.Core/MarkerSwitcher.cs windows/tests/AELanguageSwitcher.Core.Tests/MarkerSwitcherTests.cs
git commit -m "add safe Windows marker switching"
```

### Task 5: Orchestrate application state in a testable view model

**Files:**
- Create: `windows/src/AELanguageSwitcher.Core/MainViewModel.cs`
- Create: `windows/tests/AELanguageSwitcher.Core.Tests/MainViewModelTests.cs`

**Interfaces:**
- Produces: `MainViewModel.Refresh()`, `MainViewModel.RequestSwitch()`, bindable state properties, and `IUserDialog.Show(string, string)`.
- Consumes: `InstallationScanner`, `LanguageStateDetector`, `IAfterEffectsProcessMonitor`, and `ILanguageSwitcher` from Tasks 2–4.

- [ ] **Step 1: Write failing orchestration tests**

Use fakes to verify:

- refresh selects the highest installation and derives language state;
- no installation disables the primary action;
- simplified Chinese state targets English and English targets Chinese;
- a running AE process blocks the switcher call;
- successful switch refreshes and shows the success status;
- typed switch errors map to the matching Chinese dialog text;
- refresh never calls the switcher.

Example assertion:

```csharp
viewModel.Refresh();
viewModel.RequestSwitch();
Assert.AreEqual(0, switcher.CallCount);
Assert.AreEqual("After Effects 正在运行", dialog.LastTitle);
```

- [ ] **Step 2: Run view-model tests and verify RED**

Run:

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln --filter MainViewModelTests
```

Expected: compilation fails because `MainViewModel` does not exist.

- [ ] **Step 3: Implement `MainViewModel`**

Implement `INotifyPropertyChanged`. Expose `LanguageLabel`, `PrimaryButtonText`, `StatusMessage`, `CanSwitch`, `IsBusy`, and `RefreshCommand`/`SwitchCommand`. Keep operations synchronous because scans are bounded local I/O; use `try/finally` to restore `IsBusy`.

Before mutation, call `IsRunning()` again. Pass the detected eligibility into `ILanguageSwitcher.Switch`, refresh after success, and never infer success from a button click alone.

- [ ] **Step 4: Run view-model and full core tests, then commit**

Run:

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln
```

Expected: all core tests PASS.

```bash
git add windows/src/AELanguageSwitcher.Core/MainViewModel.cs windows/tests/AELanguageSwitcher.Core.Tests/MainViewModelTests.cs
git commit -m "add Windows app orchestration"
```

### Task 6: Build the WPF application and single-file publish profile

**Files:**
- Create: `windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj`
- Create: `windows/src/AELanguageSwitcher.App/App.xaml`
- Create: `windows/src/AELanguageSwitcher.App/App.xaml.cs`
- Create: `windows/src/AELanguageSwitcher.App/MainWindow.xaml`
- Create: `windows/src/AELanguageSwitcher.App/MainWindow.xaml.cs`
- Create: `windows/src/AELanguageSwitcher.App/WpfUserDialog.cs`
- Create: `windows/src/AELanguageSwitcher.App/Properties/PublishProfiles/win-x64.pubxml`
- Create: `windows/src/AELanguageSwitcher.App/Resources/AppIcon.ico`
- Modify: `windows/AELanguageSwitcher.Windows.sln`

**Interfaces:**
- Produces: runnable WPF app and published `AE-Language-Switcher-Windows-x64.exe`.
- Consumes: `MainViewModel` and live core providers from Tasks 2–5.

- [ ] **Step 1: Create the WPF project and publish properties**

Target `net8.0-windows`, set `UseWPF=true`, `OutputType=WinExe`, `RuntimeIdentifier=win-x64`, `SelfContained=true`, `PublishSingleFile=true`, `IncludeNativeLibrariesForSelfExtract=true`, `PublishTrimmed=false`, `AssemblyName=AE-Language-Switcher-Windows-x64`, and reference the core project.

- [ ] **Step 2: Wire live dependencies in `App.xaml.cs`**

Resolve Documents with `Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments)`, construct the scanner, detector, process monitor, marker switcher, dialog, and view model, then assign it as the window `DataContext`. Throw a user-visible startup error if Documents resolves to an empty path.

- [ ] **Step 3: Implement the compact XAML layout**

Create a fixed 420×260 system window with:

```xml
<Grid Margin="24">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/>
    <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>
  <DockPanel Grid.Row="0">
    <TextBlock Text="AE 语言切换" FontSize="22" FontWeight="SemiBold"/>
    <TextBlock Text="{Binding LanguageLabel}" HorizontalAlignment="Right"/>
  </DockPanel>
  <Button Grid.Row="1" Width="220" Height="44" HorizontalAlignment="Center" VerticalAlignment="Center"
          Content="{Binding PrimaryButtonText}" Command="{Binding SwitchCommand}"/>
  <DockPanel Grid.Row="2">
    <TextBlock Text="{Binding StatusMessage}" TextTrimming="CharacterEllipsis"/>
    <Button Content="重新扫描" Command="{Binding RefreshCommand}" HorizontalAlignment="Right"/>
  </DockPanel>
</Grid>
```

Set accessible names, keyboard focus, system font inheritance, and DPI-aware defaults. Refresh on `Loaded` and window activation without running concurrent refreshes.

- [ ] **Step 4: Build and publish on Windows**

Run:

```powershell
dotnet build windows/AELanguageSwitcher.Windows.sln -c Release
dotnet publish windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o windows/artifacts/publish
```

Expected: build succeeds and `windows/artifacts/publish/AE-Language-Switcher-Windows-x64.exe` exists with no adjacent runtime dependency required.

- [ ] **Step 5: Smoke-test the published process and commit**

On a Windows runner, launch the executable, wait for the main window, assert the process remains alive for at least two seconds, then close it. This proves the single file starts without a separately installed .NET runtime.

```bash
git add windows/src/AELanguageSwitcher.App windows/AELanguageSwitcher.Windows.sln
git commit -m "add Windows WPF application"
```

### Task 7: Documentation, CI, GitHub repository, and release

**Files:**
- Create: `.github/workflows/windows.yml`
- Create: `.github/release-notes/v1.0.0.md`
- Modify: `README.md`
- Modify: `MAINTENANCE.md`

**Interfaces:**
- Produces: public repository, CI checks, tagged GitHub Release, executable asset, and SHA-256 asset.
- Consumes: solution and publish output from Tasks 1–6.

- [ ] **Step 1: Update documentation**

Rewrite README sections to present both platforms, exact marker locations, safety guarantees, Windows requirements, download instructions, source build commands, checksum verification, and this warning:

```text
Windows 版本目前没有 Authenticode 代码签名。SmartScreen 可能显示“未知发布者”；请从本仓库 Release 下载并核对 SHA-256。
```

Update `MAINTENANCE.md` with Windows architecture, build commands, GitHub workflow, and release procedure. Do not claim signing, notarization, Store review, or per-version switching.

- [ ] **Step 2: Create the Windows workflow**

Use `windows-latest`, `actions/checkout@v4`, and `actions/setup-dotnet@v4` with `.NET 8.x`. For pushes and pull requests, restore and run `dotnet test`. For tags matching `v*`, publish to `windows/artifacts/publish`, compute:

```powershell
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  AE-Language-Switcher-Windows-x64.exe" | Set-Content "$exe.sha256" -Encoding ascii
```

Create the release with `softprops/action-gh-release@v2`, the checked-in notes file, and both assets. Set workflow `contents: write` only at job level for the tagged release job.

- [ ] **Step 3: Run final local source checks**

Run macOS tests:

```bash
xcrun swift test
```

Run a repository scan:

```bash
git status --short
git diff --check
rg -n "TBD|TODO|PLACEHOLDER" README.md MAINTENANCE.md windows .github
```

Expected: macOS tests pass; no whitespace errors or placeholders; only intentional files are staged.

- [ ] **Step 4: Commit the complete import**

Explicitly stage existing macOS source/docs/scripts plus Windows/docs/workflow, excluding generated output and caches:

```bash
git add .gitignore .github MAINTENANCE.md Package.swift README.md Sources Tests docs scripts windows
git commit -m "add Windows AE language switcher"
```

- [ ] **Step 5: Validate on GitHub Actions before release**

Install GitHub CLI if absent, authenticate the user's account, create the public repository, add `origin`, and push `main`. Wait for the Windows workflow to complete successfully. If the workflow fails, inspect its logs, fix the root cause, rerun the relevant tests once, commit, and push.

- [ ] **Step 6: Tag and publish v1.0.0**

After the Windows test/build workflow is green:

```bash
git tag -a v1.0.0 -m "Windows x64 release"
git push origin v1.0.0
```

Wait for the release workflow. Verify the GitHub Release contains exactly `AE-Language-Switcher-Windows-x64.exe` and `AE-Language-Switcher-Windows-x64.exe.sha256`, and that the checksum matches the downloaded executable.

- [ ] **Step 7: Report the release**

Provide the repository URL, Release URL, tag, commit, Windows Actions result, macOS test count, Windows test count, executable size, SHA-256, and unsigned SmartScreen caveat.

