# HeroTerm - build the Windows installer (HeroTerm-<version>-setup.exe).
#
# Run from the repository root on a Windows machine with Flutter,
# Visual Studio 2022 ("Desktop development with C++") and
# Inno Setup 6 installed:
#
#   winget install JRSoftware.InnoSetup
#   powershell -ExecutionPolicy Bypass -File scripts\package_windows_installer.ps1
#
# The script builds the release (with the ADR-019 git build
# stamp), compiles installer\HeroTerm.iss, and writes
# build\windows\HeroTerm-<version>-setup.exe plus its .sha256.
# The installer is per-user (no admin prompt) and unsigned, so
# SmartScreen warns on first run until a code-signing
# certificate is available. For a portable zip instead, use
# scripts\package_windows.ps1.

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$version = ($versionLine.Matches[0].Groups[1].Value -split '\+')[0]
$buildId = 'nogit'
try { $buildId = (git rev-parse --short HEAD 2>$null) } catch { }

Write-Host "==> flutter build windows --release (version $version, build $buildId)"
flutter build windows --release --dart-define=BUILD_ID=$buildId
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }

$releaseDir = 'build\windows\x64\runner\Release'
$exe = Join-Path $releaseDir 'HeroTerm.exe'
if (-not (Test-Path $exe)) { throw "Build output not found at $exe" }

$iscc = $null
$candidates = @(
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
)
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) { $iscc = $candidate; break }
}
if (-not $iscc) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
    throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup (or https://jrsoftware.org/isdl.php), then re-run this script.'
}

Write-Host "==> Inno Setup: $iscc"
& $iscc "/DAppVersion=$version" 'installer\HeroTerm.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }

$setup = "build\windows\HeroTerm-$version-setup.exe"
if (-not (Test-Path $setup)) { throw "Installer not found at $setup" }
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()
Set-Content -Path "$setup.sha256" -Value "$hash  HeroTerm-$version-setup.exe" -Encoding ASCII

Write-Host "==> Done: $setup"
Write-Host "    SHA256: $hash"
