$issContent = @"
[Setup]
AppName=media
AppVersion=0.1.2
AppPublisher=kushalmahapatro
AppPublisherURL=https://github.com/kushalmahapatro/media-rs
DefaultDirName={autopf64}\media
DefaultGroupName=media
OutputDir=../../dist/windows
OutputBaseFilename=media-0.1.2-windows-x86_64-setup
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=lowest

[Files]
Source: "windows\x64\runner\Release\media.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "windows\x64\runner\Release\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "windows\x64\runner\Release\ffprobe.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "windows\x64\runner\Release\data\*"; DestDir: "{app}\data\"; Flags: ignoreversion recursesubdirs
Source: "flutter_assets\*"; DestDir: "{app}\flutter_assets\"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\media"; Filename: "{app}\media.exe"
Name: "{commondesktop}\media"; Filename: "{app}\media.exe"
"@

# Create output directory
New-Item -ItemType Directory -Force -Path "C:\Users\kusha\Documents\Projects\media-rs\media_flutter\dist\windows"

# Write ISS file
$issPath = "C:\Users\kusha\Documents\Projects\media-rs\media_flutter\example\build\windows-x86_64-installer.iss"
$issContent | Out-File -FilePath $issPath -Encoding ASCII
Write-Host "ISS file written: $issPath"

# Compile with InnoSetup
$isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
& $isccPath $issPath
if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Installer built!"
    $setupExe = Get-ChildItem "C:\Users\kusha\Documents\Projects\media-rs\media_flutter\dist\windows\*.exe" | Select-Object -First 1
    if ($setupExe) {
        Write-Host "Setup.exe size: $([math]::Round($setupExe.Length/1MB, 2)) MB"
        Write-Host "Setup.exe path: $($setupExe.FullName)"
    }
} else {
    Write-Host "FAILED: InnoSetup compilation failed (exit code: $LASTEXITCODE)"
}
