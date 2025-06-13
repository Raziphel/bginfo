### BGINFO INSTALLER — BY BLAKE 🐉 ###

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────

$tempFolder      = "C:\Windows\Temp"
$publicBGFolder  = "C:\Users\Public\BGInfo"
$bginfoExe       = "Bginfo64.exe"
$bgiFile         = "StordLayout.bgi"
$wallpaperPng    = "Stord Logo PNG.png"
$wallpaperBmp    = "Stord Logo PNG.bmp"
$zipName         = "BGInfo.zip"
$bginfoUrl       = "https://download.sysinternals.com/files/BGInfo.zip"

$filesToMove = @($bginfoExe, $bgiFile, $wallpaperPng, $zipName)

# ─────────────────────────────────────────────
# Create install folder and move files
# ─────────────────────────────────────────────

New-Item -Path $publicBGFolder -ItemType Directory -Force | Out-Null

foreach ($fileName in $filesToMove) {
    $src = Join-Path $tempFolder $fileName
    if (Test-Path $src) {
        Move-Item -Path $src -Destination $publicBGFolder -Force
    }
}

# ─────────────────────────────────────────────
# Download BGInfo if not present
# ─────────────────────────────────────────────

if (!(Test-Path "$publicBGFolder\$zipName")) {
    Invoke-WebRequest -Uri $bginfoUrl -OutFile "$publicBGFolder\$zipName"
}

# ─────────────────────────────────────────────
# Extract and move Bginfo64.exe (skip if exists)
# ─────────────────────────────────────────────

$extractTemp = "$publicBGFolder\_extract"
Expand-Archive -Path "$publicBGFolder\$zipName" -DestinationPath $extractTemp -Force

$exeItem = Get-ChildItem -Path $extractTemp -Filter "Bginfo64.exe" -Recurse -File | Select-Object -First 1
$destPath = "$publicBGFolder\$bginfoExe"
if ($exeItem -and !(Test-Path $destPath)) {
    Move-Item -Path $exeItem.FullName -Destination $destPath
} elseif (!$exeItem) {
    Write-Host "❌ BGInfo executable not found in ZIP!" -ForegroundColor Red
    exit 1
}
Remove-Item $extractTemp -Recurse -Force

# ─────────────────────────────────────────────
# Convert PNG wallpaper to BMP for BGInfo
# ─────────────────────────────────────────────

Add-Type -AssemblyName System.Drawing
$pngPath = "$publicBGFolder\$wallpaperPng"
$bmpPath = "$publicBGFolder\$wallpaperBmp"

if (Test-Path $pngPath) {
    $img = [System.Drawing.Image]::FromFile($pngPath)
    $img.Save($bmpPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $img.Dispose()
    Write-Host "✅ Converted wallpaper to BMP format."
} else {
    Write-Host "⚠️ PNG wallpaper not found at $pngPath" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# Remove wallpaper enforcement policies
# ─────────────────────────────────────────────

$regPaths = @(
    "HKLM:\Software\Policies\Microsoft\Windows\Personalization",
    "HKCU:\Software\Policies\Microsoft\Windows\Personalization"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        Remove-ItemProperty -Path $regPath -Name "Wallpaper" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name "WallpaperStyle" -ErrorAction SilentlyContinue
        Write-Host "🔓 Removed wallpaper policy from $regPath"
    }
}

RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters

# ─────────────────────────────────────────────
# Ensure public folder is accessible to users
# ─────────────────────────────────────────────

cmd /c "icacls `"$publicBGFolder`" /grant *S-1-1-0:(OI)(CI)F /T"

# ─────────────────────────────────────────────
# Run BGInfo as the logged-in user (not SYSTEM)
# ─────────────────────────────────────────────

$exePath = "$publicBGFolder\$bginfoExe"
$bgiPath = "$publicBGFolder\$bgiFile"
$logFile = "$publicBGFolder\BGInfo_Debug.log"
$runLog = "$publicBGFolder\BGInfo_RunLog.txt"
$taskName = "RunBGInfoOnce"

function Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

Log "`n=== Starting BGInfo Launch Phase ==="
Log "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Log "BGInfo EXE Path: $exePath"
Log "BGInfo Layout Path: $bgiPath"

if (Test-Path $publicBGFolder) {
    Log "Public BGInfo folder contents:"
    Get-ChildItem -Path $publicBGFolder | ForEach-Object {
        Log " - $_"
    }
} else {
    Log "❌ BGInfo folder does not exist!"
}

if ((Test-Path $exePath) -and (Test-Path $bgiPath)) {
    Log "✅ BGInfo and layout file found. Scheduling for logged-in user..."

    # Accept EULA for the logged-in user via their SID
    try {
        $user = (Get-WmiObject -Class Win32_ComputerSystem).UserName
        $sid = (New-Object System.Security.Principal.NTAccount($user)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $bginfoKey = "Registry::HKEY_USERS\$sid\Software\Sysinternals\BGInfo"
        if (-not (Test-Path $bginfoKey)) {
            New-Item -Path $bginfoKey -Force | Out-Null
        }
        New-ItemProperty -Path $bginfoKey -Name "EulaAccepted" -Value 1 -PropertyType DWord -Force | Out-Null
        Log "✅ BGInfo EULA accepted in registry for user SID $sid"
    } catch {
        Log "⚠️ Failed to set EULA accepted flag: $_"
    }

    # Schedule the task
    $fullCmd = 'timeout /t 3 && start "" "' + $exePath + '" "' + $bgiPath + '" /nolicprompt /timer:0 >> "' + $runLog + '" 2>&1'
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $fullCmd" -WorkingDirectory $publicBGFolder
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
        Log "✅ Scheduled BGInfo to run for user $user at next login."
    } catch {
        Log "❌ Failed to register scheduled task: $_"
    }
} else {
    if (!(Test-Path $exePath)) { Log "❌ BGInfo executable missing at $exePath" }
    if (!(Test-Path $bgiPath)) { Log "❌ Layout file missing at $bgiPath" }
}

Log "=== BGInfo Script Finished ===`n"
