# Windows Dual Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce and publish a compressed self-contained Windows EXE and a small framework-dependent Lite EXE with identical AE switching behavior.

**Architecture:** Keep one WPF project and vary only `dotnet publish` properties. A repository PowerShell packaging script is the single source of truth for both builds, canonical filenames, checksums, and size guards; GitHub Actions and local releases call that script instead of duplicating commands.

**Tech Stack:** C# 12, .NET 8, WPF, PowerShell 7, GitHub Actions

## Global Constraints

- The recommended file is `AE-Language-Switcher-win-x64.exe`, self-contained, single-file, compressed, and not trimmed.
- The Lite file is `AE-Language-Switcher-win-x64-lite.exe`, framework-dependent, single-file, and requires Microsoft .NET 8 Desktop Runtime x64.
- Both variants use the same source, version, behavior, and `Resources/AppIcon.ico`.
- Each EXE has an ASCII `.sha256` file containing a lowercase hash, two spaces, its exact filename, and a final newline.
- Language detection, preference mutation, backup, verification, and rollback behavior must not change.
- Local deliverables go to the task `outputs` directory and must not overwrite the user's Desktop copy.

---

### Task 1: Reproducible Dual-Package Script

**Files:**
- Create: `scripts/package_windows.ps1`
- Modify: `windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj`

**Interfaces:**
- Consumes: `dotnet publish`, `windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj`, and optional `-OutputDirectory <string>`.
- Produces: `scripts/package_windows.ps1 [-OutputDirectory <path>]`, two canonical EXEs, and two canonical checksum files.

- [ ] **Step 1: Add compression as the recommended project's default publish behavior**

Add this property beside the current single-file properties:

```xml
<EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
```

Keep `<PublishTrimmed>false</PublishTrimmed>` unchanged.

- [ ] **Step 2: Write a packaging script that fails before both artifacts exist**

Create `scripts/package_windows.ps1` with strict error handling, resolve the repository from `$PSScriptRoot`, default output to `windows/artifacts/dist`, and define these exact names:

```powershell
[CmdletBinding()]
param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'windows/artifacts/dist'
}
$project = Join-Path $repoRoot 'windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj'
$fullName = 'AE-Language-Switcher-win-x64.exe'
$liteName = 'AE-Language-Switcher-win-x64-lite.exe'
```

Before publish, create `$OutputDirectory`, remove only the two known staging subdirectories `self-contained` and `lite` when present, and remove only the four known canonical output files. Resolve and verify all deletion targets remain under `windows/artifacts` or the explicitly supplied output directory.

- [ ] **Step 3: Verify the script currently cannot satisfy the contract**

Run:

```powershell
pwsh -NoProfile -File scripts/package_windows.ps1 -OutputDirectory windows/artifacts/plan-red
```

Expected: FAIL because the two publish commands and artifact creation are not implemented yet.

- [ ] **Step 4: Implement the two publish commands**

Use argument arrays so PowerShell does not reinterpret MSBuild switches:

```powershell
& dotnet publish $project -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true `
    -p:PublishTrimmed=false -o $fullStage
if ($LASTEXITCODE -ne 0) { throw 'Self-contained publish failed.' }

& dotnet publish $project -c Release -r win-x64 --self-contained false `
    -p:SelfContained=false -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=false -p:PublishTrimmed=false -o $liteStage
if ($LASTEXITCODE -ne 0) { throw 'Lite publish failed.' }
```

Copy each staging `AE-Language-Switcher.exe` to its canonical distribution filename. Generate checksums using:

```powershell
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$exePath.sha256", "$hash  $([IO.Path]::GetFileName($exePath))`n", [Text.Encoding]::ASCII)
```

End by returning objects containing `Name`, `Bytes`, and `Sha256` for both EXEs.

- [ ] **Step 5: Run the packaging script and enforce measurable size guards**

After publishing, throw if the recommended compressed EXE is not below `130000000` bytes or the Lite EXE is not below `10000000` bytes. Run:

```powershell
pwsh -NoProfile -File scripts/package_windows.ps1 -OutputDirectory windows/artifacts/dual-package-test
```

Expected: PASS; exactly two EXEs and two `.sha256` files are present, the recommended EXE is below 130 MB, and Lite is below 10 MB.

- [ ] **Step 6: Confirm build metadata for both variants**

Run:

```powershell
dotnet msbuild windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj -getProperty:SelfContained -p:RuntimeIdentifier=win-x64
dotnet msbuild windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj -getProperty:SelfContained -p:RuntimeIdentifier=win-x64 -p:SelfContained=false
```

Expected: the first reports `true`; the second reports `false`.

- [ ] **Step 7: Commit the packaging boundary**

```powershell
git add scripts/package_windows.ps1 windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj
git commit -m "build: produce full and lite Windows packages"
```

---

### Task 2: GitHub Actions Publishes Both Variants

**Files:**
- Modify: `.github/workflows/windows.yml`

**Interfaces:**
- Consumes: `scripts/package_windows.ps1 -OutputDirectory windows/artifacts/dist` from Task 1.
- Produces: one Actions artifact and one tagged Release containing the exact four files in Global Constraints.

- [ ] **Step 1: Demonstrate the current workflow only names one variant**

Run:

```powershell
$workflow = Get-Content -Raw -Encoding UTF8 .github/workflows/windows.yml
if ($workflow -notmatch 'AE-Language-Switcher-win-x64-lite\.exe') { throw 'Lite artifact is absent, as expected before implementation.' }
```

Expected: FAIL with `Lite artifact is absent`.

- [ ] **Step 2: Replace duplicated publish commands with the packaging script**

Keep the existing test step, then use:

```yaml
- name: Publish Windows packages
  shell: pwsh
  run: ./scripts/package_windows.ps1 -OutputDirectory windows/artifacts/dist
```

- [ ] **Step 3: Upload all four canonical files**

Use a single artifact named `AE-Language-Switcher-Windows` and this shared path list for Actions artifacts and `softprops/action-gh-release`:

```yaml
windows/artifacts/dist/AE-Language-Switcher-win-x64.exe
windows/artifacts/dist/AE-Language-Switcher-win-x64.exe.sha256
windows/artifacts/dist/AE-Language-Switcher-win-x64-lite.exe
windows/artifacts/dist/AE-Language-Switcher-win-x64-lite.exe.sha256
```

- [ ] **Step 4: Validate workflow references**

Run a PowerShell assertion that each of the four canonical basenames occurs at least twice in `.github/workflows/windows.yml`—once for artifact upload and once for Release upload—and that `scripts/package_windows.ps1` occurs once.

Expected: PASS.

- [ ] **Step 5: Commit CI changes**

```powershell
git add .github/workflows/windows.yml
git commit -m "ci: publish full and lite Windows releases"
```

---

### Task 3: Document the Download Choice

**Files:**
- Modify: `README.md`
- Modify: `MAINTENANCE.md`

**Interfaces:**
- Consumes: canonical filenames and runtime contract from Global Constraints.
- Produces: user-facing selection guidance and maintainer build instructions matching the packaging script.

- [ ] **Step 1: Verify Lite guidance is absent**

Run:

```powershell
$readme = Get-Content -Raw -Encoding UTF8 README.md
if ($readme -notmatch 'AE-Language-Switcher-win-x64-lite\.exe') { throw 'Lite guidance is absent, as expected before implementation.' }
```

Expected: FAIL with `Lite guidance is absent`.

- [ ] **Step 2: Add a compact Windows download comparison**

State exactly:

```markdown
- **推荐／免安装版**：`AE-Language-Switcher-win-x64.exe`，自带运行环境，下载后直接运行。
- **小体积版**：`AE-Language-Switcher-win-x64-lite.exe`，功能完全相同，需要预先安装 Microsoft .NET 8 Desktop Runtime x64。

不确定时请选择免安装版。两个版本都可以使用 Release 页面中对应的 `.sha256` 文件校验完整性。
```

Replace the single-build command with:

```powershell
pwsh -NoProfile -File scripts/package_windows.ps1
```

- [ ] **Step 3: Update maintainer release inventory**

List both EXEs and both checksum files in `MAINTENANCE.md`, identify the full variant as recommended, and state that the workflow invokes `scripts/package_windows.ps1`.

- [ ] **Step 4: Assert documentation filename consistency**

Read both files as UTF-8 and assert both canonical EXE names occur in each file. Assert the README contains `.NET 8 Desktop Runtime x64` and `scripts/package_windows.ps1`.

Expected: PASS.

- [ ] **Step 5: Commit documentation changes**

```powershell
git add README.md MAINTENANCE.md
git commit -m "docs: explain full and lite Windows downloads"
```

---

### Task 4: End-to-End Verification and Deliverables

**Files:**
- Generate: `windows/artifacts/final/AE-Language-Switcher-win-x64.exe`
- Generate: `windows/artifacts/final/AE-Language-Switcher-win-x64.exe.sha256`
- Generate: `windows/artifacts/final/AE-Language-Switcher-win-x64-lite.exe`
- Generate: `windows/artifacts/final/AE-Language-Switcher-win-x64-lite.exe.sha256`
- Copy: the same four files to the current task `outputs` directory

**Interfaces:**
- Consumes: completed Tasks 1–3.
- Produces: verified local user deliverables without modifying AE preferences or the Desktop.

- [ ] **Step 1: Run all Windows unit tests**

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln -c Release
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Build final dual packages**

```powershell
pwsh -NoProfile -File scripts/package_windows.ps1 -OutputDirectory windows/artifacts/final
```

Expected: the script passes its 130 MB and 10 MB guards and reports two hashes.

- [ ] **Step 3: Verify both checksum files independently**

For each EXE, calculate `Get-FileHash -Algorithm SHA256`, read the corresponding ASCII `.sha256`, split at two spaces, and assert both the hash and basename match exactly.

Expected: four assertions pass.

- [ ] **Step 4: Smoke-test both windows**

Start each EXE with `Start-Process -PassThru`, wait up to 10 seconds for a non-zero `MainWindowHandle`, assert `MainWindowTitle` equals `AE 中英文切换器`, then stop only that test process. Do not click either language button.

Expected: both variants display the main window and exit cleanly after the smoke test.

- [ ] **Step 5: Copy only canonical deliverables**

Copy the two EXEs and their checksum files from `windows/artifacts/final` to the current task `outputs` directory. Do not write to Desktop and do not remove unrelated output files.

- [ ] **Step 6: Review the final Git state**

```powershell
git status --short
git diff --check HEAD
git log --oneline -5
```

Expected: no uncommitted source or documentation changes, no whitespace errors, and the three implementation commits are present after the design and plan commits.
