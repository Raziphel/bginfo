### Blake's BGInfo Deployment Script — 100% satisfaction garunteed ###

# Variables
$bgInfoUrl     = "https://download.sysinternals.com/files/BGInfo.zip"
$zipPath       = "$env:TEMP\BGInfo.zip"
$extractPath   = "$env:TEMP\BGInfo"
$bginfoExe     = "Bginfo64.exe"
$bgiFile       = "StordLayout.bgi"
$wallpaperFile = "Stord_Basic_Black_3840x2160.png"

# Paths
$bgiSource        = "C:\Windows\Temp\$bgiFile"
$wallpaperSource  = "C:\Windows\Temp\$wallpaperFile"
$installPath      = "C:\ProgramData\BGInfo"
$bginfoDest       = Join-Path $installPath $bginfoExe
$bgiDest          = Join-Path $installPath $bgiFile
$wallpaperDest    = Join-Path $installPath $wallpaperFile

# Ensure the ProgramData install path exists
if (!(Test-Path $installPath)) {
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
}

# Download and extract BGInfo
Invoke-WebRequest -Uri $bgInfoUrl -OutFile $zipPath
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
Copy-Item -Path (Join-Path $extractPath $bginfoExe) -Destination $bginfoDest -Force

# Copy layout and wallpaper
Copy-Item -Path $bgiSource -Destination $bgiDest -Force
Copy-Item -Path $wallpaperSource -Destination $wallpaperDest -Force

# Get stord user profiles
$stordUsers = Get-ChildItem 'C:\Users' -Directory | Where-Object {
    $_.Name -match '(?i)stord'
}

# Loop through stord users and set wallpaper in their registry hive
foreach ($user in $stordUsers) {
    $ntUserDat = Join-Path $user.FullName "NTUSER.DAT"
    if (!(Test-Path $ntUserDat)) {
        Write-Warning "Skipping $($user.Name) — NTUSER.DAT not found"
        continue
    }

    try {
        $sid = (Get-LocalUser -Name $user.Name).SID.Value
    } catch {
        Write-Warning "Skipping $($user.Name) — couldn't get SID"
        continue
    }

    $regKey = "HKU\$sid"
    reg load "$regKey" "$ntUserDat" | Out-Null

    Set-ItemProperty -Path "$regKey\Control Panel\Desktop" -Name Wallpaper -Value $wallpaperDest
    Set-ItemProperty -Path "$regKey\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
    Set-ItemProperty -Path "$regKey\Control Panel\Desktop" -Name TileWallpaper -Value "0"

    reg unload "$regKey" | Out-Null

    Write-Host "Wallpaper set for user: $($user.Name)"
}

# Also apply wallpaper immediately for current user
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\' -Name Wallpaper -Value $wallpaperDest
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\' -Name WallpaperStyle -Value "10"
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\' -Name TileWallpaper -Value "0"
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters

# Create BGInfo shortcuts for stord users
foreach ($user in $stordUsers) {
    $startupPath = Join-Path $user.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    $shortcutPath = Join-Path $startupPath "BGInfo.lnk"

    if (!(Test-Path $startupPath)) {
        Write-Warning "Skipping '$($user.Name)' — no Startup folder found."
        continue
    }

    # Create shortcut
    $shell = New-Object -ComObject "WScript.Shell"
    $Shortcut = $shell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = $bginfoDest
    $Shortcut.Arguments = "`"$bgiDest`" /timer:0 /silent /nolicprompt"
    $Shortcut.WorkingDirectory = $installPath
    $Shortcut.Save()

    Write-Host "Created BGInfo shortcut for: $($user.Name)"
}

# Run BGInfo now for current user
Start-Process -FilePath $bginfoDest -ArgumentList "`"$bgiDest`" /timer:0 /silent /nolicprompt"

# Clean up temp files
Remove-Item $zipPath -Force
Remove-Item $extractPath -Recurse -Force

# Done!
Write-Host "`BGInfo deployed! Thanks for using BlakeWare™ 🐉"
