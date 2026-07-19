#define AppName "Fabula"
#define AppVersion "0.4.1.11"
#define AppPublisher "Fabula"
#define AppExeName "Fabula.exe"

[Setup]
AppId={{C5467DB1-9DC2-4BD1-A297-FBA64F81E4C9}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Fabula
DefaultGroupName=Fabula
OutputDir=..\..\build-output\windows
OutputBaseFilename=FabulaSetup
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
Name: "{autoprograms}\Fabula"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Fabula"; Filename: "{app}\{#AppExeName}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Запустить Fabula"; Flags: nowait postinstall skipifsilent runascurrentuser
