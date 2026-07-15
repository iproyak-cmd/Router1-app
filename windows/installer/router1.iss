#define AppName "Router1"
#define AppVersion "0.2.0.119"
#define AppPublisher "Router1"
#define AppExeName "Router1.exe"

[Setup]
AppId={{78DBB054-6235-41C0-9025-AF50BC273101}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Router1
DefaultGroupName=Router1
OutputDir=..\..\build-output\windows
OutputBaseFilename=Router1Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
CloseApplications=yes
RestartApplications=yes
CloseApplicationsFilter=*.exe

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\router1_app_mvp.exe"

[Icons]
Name: "{autoprograms}\Router1"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Router1"; Filename: "{app}\{#AppExeName}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Запустить Router1"; Flags: nowait postinstall skipifsilent runascurrentuser
