; MixLit Installer Script with Audio Service and Launcher
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

#define MyAppName "MixLit"
#define MyAppVersion "1.0"
#define MyAppPublisher "Goddeh & AlpacasRule"
#define MyAppURL "https://goddeh.dev/"
#define MyAppExeName "MixLit.exe"
#define LauncherExeName "MixLit-Launcher.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{96FA53A3-343F-4B93-B6F6-EF10F3E0C152}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
;AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\{#LauncherExeName}
; "ArchitecturesAllowed=x64compatible" specifies that Setup cannot run
; on anything but x64 and Windows 11 on Arm.
ArchitecturesAllowed=x64compatible
; "ArchitecturesInstallIn64BitMode=x64compatible" requests that the
; install be done in "64-bit mode" on x64 or Windows 11 on Arm,
; meaning it should use the native 64-bit Program Files directory and
; the 64-bit view of the registry.
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
OutputBaseFilename=MixLit-Installer
SetupIconFile=E:\Coding\Apps\Flutter Projects\mixlit\Software-Installer\Assets\mixlit-installer.ico
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Launcher (this will be the main executable)
Source: "E:\Coding\Apps\Flutter Projects\mixlit\Software-Installer\MixLitLauncher\bin\Release\net8.0-windows\win-x64\publish\MixLit-Launcher.exe"; DestDir: "{app}"; Flags: ignoreversion

; Flutter Application Files
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\flutter_libserialport_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\serialport.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\win32audio_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\window_to_front_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; Audio Service Files
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software-service\MixlitAudioService\bin\Release\net8.0\win-x64\publish\MixlitAudioService.exe"; DestDir: "{app}\AudioService"; Flags: ignoreversion
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software-service\MixlitAudioService\bin\Release\net8.0\win-x64\publish\appsettings.json"; DestDir: "{app}\AudioService"; Flags: ignoreversion onlyifdoesntexist
Source: "E:\Coding\Apps\Flutter Projects\mixlit\software-service\MixlitAudioService\bin\Release\net8.0\win-x64\publish\*.dll"; DestDir: "{app}\AudioService"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#LauncherExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#LauncherExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#LauncherExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Kill any running instances before uninstall
Filename: "taskkill"; Parameters: "/F /IM MixlitAudioService.exe"; Flags: runhidden; RunOnceId: "KillAudioService"
Filename: "taskkill"; Parameters: "/F /IM {#MyAppExeName}"; Flags: runhidden; RunOnceId: "KillMixLit"
Filename: "taskkill"; Parameters: "/F /IM {#LauncherExeName}"; Flags: runhidden; RunOnceId: "KillLauncher"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Kill any running instances before installation
  Exec('taskkill', '/F /IM MixlitAudioService.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/F /IM {#LauncherExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
  Result := True;
end;