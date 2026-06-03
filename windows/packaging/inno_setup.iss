[Setup]
AppId={{E6F7C8A9-9B8D-4C7E-B3A2-1F4D5E6C7B8A}
AppName=FocusMyTime
AppVersion=1.0.13
AppPublisher=Monody12
AppPublisherURL=https://github.com/Monody12/FocusTime
DefaultDirName={autopf}\FocusMyTime
DisableProgramGroupPage=yes
; We output the installer to the root of the project with a specific name
OutputDir=..\..\
OutputBaseFilename=FocusMyTime-Windows-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Requires no admin privileges to install (installs to user AppData\Local\Programs if autopf is used by non-admin)
PrivilegesRequired=lowest

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The source path will be passed from GitHub Action or defaults to release folder
Source: "..\..\build\windows\x64\runner\Release\focus_my_time.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\FocusMyTime"; Filename: "{app}\focus_my_time.exe"
Name: "{autodesktop}\FocusMyTime"; Filename: "{app}\focus_my_time.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\focus_my_time.exe"; Description: "{cm:LaunchProgram,FocusMyTime}"; Flags: nowait postinstall skipifsilent
