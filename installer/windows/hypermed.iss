; Hypermed Windows installer — Inno Setup 6.
; Built by .github/workflows/release.yml:
;   iscc /DAppVersion=1.4.0 /DSourceDir=<flutter Release dir> installer\windows\hypermed.iss
;
; Per-user install (PrivilegesRequired=lowest → %LOCALAPPDATA%\Programs\Hypermed)
; so the in-app updater can run this silently with no UAC prompt. The app
; calls it with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS
; (lib/services/update_service.dart) and the skipifnotsilent [Run] entry
; relaunches it afterwards.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#define AppName "Hypermed"
#define AppExe "bienhypermed.exe"

[Setup]
; Never change AppId — it's how updates find the existing install.
AppId={{4B4F9EE0-6785-4BA7-96BE-F00EC4ABB185}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=HyperMed Health Care Ltd
AppPublisherURL=https://hypermed.co.tz
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=Hypermed-Setup-{#AppVersion}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Flutter asset/DLL sets change between versions — start each update from a
; clean app folder so stale files from old versions can't linger.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Interactive install: "Launch Hypermed" checkbox on the last page.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Silent install = an in-app update: always relaunch.
Filename: "{app}\{#AppExe}"; Flags: nowait skipifnotsilent
