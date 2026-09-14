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
UninstallDisplayIcon={app}\launcher\icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=commandline dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "staging\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Stirling PDF"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\launcher\run-stirling.vbs"""; WorkingDir: "{app}\launcher"; IconFilename: "{app}\launcher\icon.ico"
Name: "{group}\Stop Stirling PDF"; Filename: "{app}\launcher\stop.bat"; WorkingDir: "{app}\launcher"; IconFilename: "{app}\launcher\icon.ico"
Name: "{group}\{cm:UninstallProgram,Stirling PDF}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Stirling PDF"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\launcher\run-stirling.vbs"""; WorkingDir: "{app}\launcher"; IconFilename: "{app}\launcher\icon.ico"; Tasks: desktopicon

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\launcher\run-stirling.vbs"""; WorkingDir: "{app}\launcher"; Description: "{cm:LaunchProgram,Stirling PDF}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\launcher\stop.bat"; Flags: runhidden; RunOnceId: "StopStirlingPDF"
