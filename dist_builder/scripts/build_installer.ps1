# build_installer.ps1
# Complete build automation for Stirling-PDF All-in-One Offline Windows Installer

param(
    [string]$AppVersion = "",
    [string]$CustomJarPath = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Split-Path -Parent $ScriptDir
$IssFile = Join-Path $BaseDir "installer.iss"
$OutputDir = Join-Path $BaseDir "output"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Stirling-PDF Windows Installer Build Pipeline" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Fetch assets if needed
$FetchScript = Join-Path $ScriptDir "fetch_assets.ps1"
& $FetchScript -CustomJarPath $CustomJarPath

# 2. Locate Inno Setup Compiler (ISCC.exe)
$Iscc = "iscc"
if (-not (Get-Command iscc -ErrorAction SilentlyContinue)) {
    $candidates = @(
        "C:\Users\nguye\AppData\Local\Programs\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $Iscc = $cand
            break
        }
    }
    if ($Iscc -eq "iscc" -and -not (Test-Path $Iscc)) {
        throw "Inno Setup Compiler (ISCC.exe) could not be located."
    }
}
Write-Host ("[OK] Inno Setup compiler found: " + $Iscc) -ForegroundColor Green

# 3. Ensure output directory exists
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# 4. Compile Installer
Write-Host "[-] Compiling installer with Inno Setup (this may take a few minutes due to ultra compression)..." -ForegroundColor Cyan
$isccArgs = @()
if ($AppVersion -and $AppVersion.Trim() -ne "") {
    $cleanVersion = $AppVersion.TrimStart('v')
    $isccArgs += "/DAppVersion=$cleanVersion"
    Write-Host ("[OK] Setting AppVersion: " + $cleanVersion) -ForegroundColor Green
}
$isccArgs += "$IssFile"
& $Iscc @isccArgs
if ($LASTEXITCODE -ne 0) {
    throw ("Inno Setup compilation failed with exit code " + $LASTEXITCODE)
}

$FinalExe = Join-Path $OutputDir "StirlingPDF-Full-Setup.exe"
if (-not (Test-Path $FinalExe)) {
    throw ("Expected output executable not found: " + $FinalExe)
}

$FinalSizeMB = [math]::Round(((Get-Item $FinalExe).Length / 1MB), 2)
Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "  BUILD SUCCESSFUL!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ("Installer: " + $FinalExe) -ForegroundColor Yellow
Write-Host ("File Size: " + $FinalSizeMB + " MB") -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Green
