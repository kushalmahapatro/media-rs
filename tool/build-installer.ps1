$iss = @"
; InnoSetup installer for media-rs
; Creates setup.exe that installs on any Windows machine

#define MyAppName 'media'
#define MyAppVersion '0.1.2'
#define MyAppPublisher 'kushalmahapatro'
#define MyAppURL 'https://github.com/kushalmahapatro/media-rs'
#define MyAppExeName 'media.exe'

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf64}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=../../dist/windows
OutputBaseFilename=media-{#MyAppVersion}-windows-x86_64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64Bit=x64
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}
AppID={{4A2B1C3D-5E6F-4890-ABCD-EF1234567890}

[Files]
Source: 'build\windows\x64\runner\Release\{#MyAppExeName}'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\media.dll'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\flutter_windows.dll'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\share_plus_plugin.dll'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\url_launcher_windows_plugin.dll'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\ffmpeg.exe'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\ffprobe.exe'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\app.so'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\icudtl.dat'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\notices.z'; DestDir: '{app}'; Flags: ignoreversion
Source: 'build\windows\x64\runner\Release\data\*'; DestDir: '{app}\data\'; Flags: ignoreversion recursesubdirs createallsubdirs
Source: 'build\windows\x64\runner\Release\flutter_assets\*'; DestDir: '{app}\flutter_assets\'; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: '{group}\{#MyAppName}'; Filename: '{app}\{#MyAppExeName}'; Comment: 'Media processing toolkit'
Name: '{commondesktop}\{#MyAppName}'; Filename: '{app}\{#MyAppExeName}'; Tasks: desktopicon

[Tasks]
Name: 'desktopicon'; Description: 'Create a &desktop icon'; GroupDescription: 'Additional icons:'

[Run]
Filename: '{app}\{#MyAppExeName}'; Description: 'Launch {#MyAppName}'; Flags: nowait postinstall skipifsilent
"@

Set-Content -Path 'C:\Users\kusha\Documents\Projects\media-rs\media_flutter\example\build\windows-x86_64-installer.iss' -Value $iss -Encoding ASCII
Write-Output "ISS written: $((Get-Item 'C:\Users\kusha\Documents\Projects\media-rs\media_flutter\example\build\windows-x86_64-installer.iss').Length) bytes"
