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

if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location).Path $OutputDirectory
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

function Assert-DirectChildPath([string]$Path, [string]$Parent) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullParent = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::GetDirectoryName($fullPath) -ne $fullParent) {
        throw "Unsafe packaging path outside the output directory: $fullPath"
    }
}

$fullStage = Join-Path $OutputDirectory 'self-contained'
$liteStage = Join-Path $OutputDirectory 'lite'
$fullOutput = Join-Path $OutputDirectory $fullName
$liteOutput = Join-Path $OutputDirectory $liteName
$knownTargets = @(
    $fullStage,
    $liteStage,
    $fullOutput,
    "$fullOutput.sha256",
    $liteOutput,
    "$liteOutput.sha256"
)

foreach ($target in $knownTargets) {
    Assert-DirectChildPath $target $OutputDirectory
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

& dotnet publish $project -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true `
    -p:PublishTrimmed=false -o $fullStage
if ($LASTEXITCODE -ne 0) { throw 'Self-contained publish failed.' }

& dotnet publish $project -c Release -r win-x64 --self-contained false `
    -p:SelfContained=false -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=false -p:PublishTrimmed=false -o $liteStage
if ($LASTEXITCODE -ne 0) { throw 'Lite publish failed.' }

Copy-Item -LiteralPath (Join-Path $fullStage 'AE-Language-Switcher.exe') -Destination $fullOutput
Copy-Item -LiteralPath (Join-Path $liteStage 'AE-Language-Switcher.exe') -Destination $liteOutput

function Write-Checksum([string]$ExePath) {
    $hash = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $line = "$hash  $([IO.Path]::GetFileName($ExePath))`n"
    [IO.File]::WriteAllText("$ExePath.sha256", $line, [Text.Encoding]::ASCII)
    return $hash
}

$fullHash = Write-Checksum $fullOutput
$liteHash = Write-Checksum $liteOutput
$fullBytes = (Get-Item -LiteralPath $fullOutput).Length
$liteBytes = (Get-Item -LiteralPath $liteOutput).Length

if ($fullBytes -ge 130000000) {
    throw "Compressed self-contained package is unexpectedly large: $fullBytes bytes."
}
if ($liteBytes -ge 10000000) {
    throw "Framework-dependent Lite package is unexpectedly large: $liteBytes bytes."
}

Remove-Item -LiteralPath $fullStage -Recurse -Force
Remove-Item -LiteralPath $liteStage -Recurse -Force

@(
    [PSCustomObject]@{ Name = $fullName; Bytes = $fullBytes; Sha256 = $fullHash },
    [PSCustomObject]@{ Name = $liteName; Bytes = $liteBytes; Sha256 = $liteHash }
)
