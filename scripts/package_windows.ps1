# HeroTerm - build and package a shareable Windows release.
#
# Run from the repository root on a Windows machine with Flutter
# and Visual Studio 2022 ("Desktop development with C++")
# installed:
#
#   powershell -ExecutionPolicy Bypass -File scripts\package_windows.ps1
#
# Produces build\windows\HeroTerm-<version>-windows-x64.zip plus
# its .sha256. The zip holds the full Release folder (HeroTerm.exe
# and its DLLs must stay together) and a bilingual install note.
# The build is unsigned: Windows SmartScreen will warn on first
# run ("More info" -> "Run anyway") until a code-signing
# certificate is available.

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

$stageName = "HeroTerm-$version-windows-x64"
$stageDir = Join-Path 'build\windows' $stageName
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
Copy-Item $releaseDir $stageDir -Recurse

$note = @"
HeroTerm $version - Windows

INSTALL
1. Extract this zip to a folder of your choice
   (for example C:\Apps\HeroTerm).
2. Run HeroTerm.exe. Keep the .exe together with the DLL files
   next to it - the app does not work if the exe is moved alone.
3. First run: Windows SmartScreen may show "Windows protected
   your PC" because this build is not code-signed yet. Choose
   "More info" -> "Run anyway".

Your sessions and settings are stored per Windows user in
%APPDATA%\HeroTerm; passwords go to Windows Credential Manager.

---

CAI DAT
1. Giai nen file zip nay vao mot thu muc tuy chon
   (vi du C:\Apps\HeroTerm).
2. Chay HeroTerm.exe. Giu nguyen file .exe cung cac file DLL
   ben canh - ung dung se khong chay neu tach rieng file exe.
3. Lan chay dau: Windows SmartScreen co the hien canh bao vi
   ban build chua duoc ky so. Chon "More info" -> "Run anyway".

Du lieu phien lam viec va cai dat luu theo tai khoan Windows
tai %APPDATA%\HeroTerm; mat khau luu trong Windows
Credential Manager.
"@
Set-Content -Path (Join-Path $stageDir 'Huong dan cai dat.txt') -Value $note -Encoding UTF8

$zip = Join-Path 'build\windows' "$stageName.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stageDir -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Set-Content -Path "$zip.sha256" -Value "$hash  $stageName.zip" -Encoding ASCII

Write-Host "==> Done: $zip"
Write-Host "    SHA256: $hash"
