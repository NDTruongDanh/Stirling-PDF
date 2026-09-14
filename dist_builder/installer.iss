; installer.iss
; Inno Setup script for Stirling-PDF All-in-One Offline Windows Installer

#ifndef AppVersion
#define AppVersion "2.14.3"
#endif

[Setup]
AppName=Stirling PDF
AppVersion={#AppVersion}
AppPublisher=Stirling-Tools
AppPublisherURL=https://github.com/Stirling-Tools/Stirling-PDF
AppSupportURL=https://github.com/Stirling-Tools/Stirling-PDF/issues
DefaultDirName={autopf}\StirlingPDF
DefaultGroupName=Stirling PDF
AllowNoIcons=yes
OutputDir=output
OutputBaseFilename=StirlingPDF-Full-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=staging\app\icon.ico
UninstallDisplayIcon={app}\app\icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=commandline dialog
CloseApplications=yes
CloseApplicationsFilter=StirlingPDF.exe,javaw.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Dirs]
Name: "{app}"; Permissions: users-full
Name: "{app}\app"; Permissions: users-full
Name: "{app}\app\logs"; Permissions: users-full
Name: "{app}\app\configs"; Permissions: users-full

[Files]
Source: "staging\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Stirling PDF"; Filename: "{app}\StirlingPDF.exe"; WorkingDir: "{app}"; IconFilename: "{app}\app\icon.ico"
Name: "{group}\{cm:UninstallProgram,Stirling PDF}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Stirling PDF"; Filename: "{app}\StirlingPDF.exe"; WorkingDir: "{app}"; IconFilename: "{app}\app\icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\StirlingPDF.exe"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,Stirling PDF}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM StirlingPDF.exe /IM javaw.exe /T"; Flags: runhidden; RunOnceId: "StopStirlingPDF"
