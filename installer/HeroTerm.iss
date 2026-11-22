; HeroTerm Windows installer - Inno Setup 6 script (ADR-022).
;
; Normally compiled by scripts\package_windows_installer.ps1,
; which builds the release first and passes the version in:
;   ISCC /DAppVersion=1.0.0 installer\HeroTerm.iss
; Paths below are relative to this file (repo\installer).
; The install is per-user (no admin prompt): the app lands in
; %LOCALAPPDATA%\Programs\HeroTerm, shortcuts in the Start Menu
; (desktop shortcut optional), and a standard uninstaller is
; registered. User data (%APPDATA%\HeroTerm) is intentionally
; NOT removed on uninstall - it holds sessions and settings.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{B9C63B64-908D-4B62-A160-323E5590907F}
AppName=HeroTerm
AppVersion={#AppVersion}
AppVerName=HeroTerm {#AppVersion}
AppPublisher=HeroTerm
DefaultDirName={localappdata}\Programs\HeroTerm
DefaultGroupName=HeroTerm
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\windows
OutputBaseFilename=HeroTerm-{#AppVersion}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\HeroTerm.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#AppVersion}
VersionInfoProductName=HeroTerm
VersionInfoDescription=HeroTerm Setup

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\HeroTerm"; Filename: "{app}\HeroTerm.exe"
Name: "{autodesktop}\HeroTerm"; Filename: "{app}\HeroTerm.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\HeroTerm.exe"; Description: "{cm:LaunchProgram,HeroTerm}"; Flags: nowait postinstall skipifsilent
