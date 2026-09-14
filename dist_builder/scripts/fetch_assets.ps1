# fetch_assets.ps1
# Automates downloading, extracting, and configuring all runtime dependencies for Stirling-PDF offline installer.

param(
    [string]$CustomJarPath = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Split-Path -Parent $ScriptDir
$RepoRoot = Split-Path -Parent $BaseDir
$StagingDir = Join-Path $BaseDir "staging"
$DownloadsDir = Join-Path $BaseDir "downloads"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Stirling-PDF Windows Offline Asset Fetcher" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Base Dir:    $BaseDir"
Write-Host "Staging Dir: $StagingDir"
Write-Host ""

# Ensure base directories exist
New-Item -ItemType Directory -Force -Path $DownloadsDir | Out-Null
New-Item -ItemType Directory -Force -Path "$StagingDir\app\configs" | Out-Null
New-Item -ItemType Directory -Force -Path "$StagingDir\launcher" | Out-Null

# Resolve 7-Zip
$SevenZip = "7z"
if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
        $SevenZip = "C:\Program Files\7-Zip\7z.exe"
    } else {
        throw "7-Zip executable (7z.exe) not found on PATH or in C:\Program Files\7-Zip\"
    }
}
Write-Host "[OK] 7-Zip found: $SevenZip" -ForegroundColor Green

# Resolve jlink (prioritize JDK 25 matching modernJavaVersion)
$JLink = ""
$jlinkCandidates = @(
    "C:\Program Files\Java\jdk-25.0.3\bin\jlink.exe",
    "C:\Program Files\Java\latest\bin\jlink.exe",
    "$env:JAVA_HOME\bin\jlink.exe"
)
foreach ($cand in $jlinkCandidates) {
    if ($cand -and (Test-Path $cand)) {
        $JLink = $cand
        break
    }
}
if (-not $JLink -or -not (Test-Path $JLink)) {
    if (Get-Command jlink -ErrorAction SilentlyContinue) {
        $JLink = (Get-Command jlink).Source
    } else {
        throw "jlink executable not found. Please install JDK 25."
    }
}
Write-Host "[OK] jlink found: $JLink" -ForegroundColor Green

# Helper function for downloading with curl
function Download-FileWithCurl {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )
    if (Test-Path $OutFile) {
        $fileSize = (Get-Item $OutFile).Length
        if ($fileSize -gt 1000000) {
            $existingMB = [math]::Round(($fileSize / 1MB), 2)
            Write-Host ("[OK] " + $Description + " already downloaded (" + $existingMB + " MB). Skipping.") -ForegroundColor Yellow
            return
        }
    }
    Write-Host ("[-] Downloading " + $Description + "...") -ForegroundColor Cyan
    Write-Host ("    Source: " + $Url)
    Write-Host ("    Target: " + $OutFile)
    & curl.exe -L -C - --retry 5 --retry-delay 2 -A "Mozilla/5.0" -o "$OutFile" "$Url"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutFile)) {
        throw ("Failed to download " + $Description + " from " + $Url)
    }
    $fileSize = (Get-Item $OutFile).Length
    $downloadedMB = [math]::Round(($fileSize / 1MB), 2)
    Write-Host ("[OK] Downloaded " + $Description + " (" + $downloadedMB + " MB)") -ForegroundColor Green
}

# ----------------------------------------------------
# 1. Stirling-PDF Full-Stack JAR (with Web UI)
# ----------------------------------------------------
$JarTarget = Join-Path $StagingDir "app\Stirling-PDF.jar"

if ($CustomJarPath -and (Test-Path $CustomJarPath)) {
    Write-Host ("[OK] Using custom JAR: " + $CustomJarPath) -ForegroundColor Green
    Copy-Item -Path $CustomJarPath -Destination $JarTarget -Force
} else {
    # Check for locally compiled JAR from source
    $localLibsDir = Join-Path $RepoRoot "app\core\build\libs"
    $localJars = @()
    if (Test-Path $localLibsDir) {
        $localJars = Get-ChildItem -Path $localLibsDir -Filter "stirling-pdf-*.jar" | Where-Object { $_.Name -notmatch "plain" }
    }

    if ($localJars.Count -gt 0) {
        $latestLocalJar = $localJars | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Host ("[OK] Found locally compiled JAR: " + $latestLocalJar.FullName) -ForegroundColor Green
        Copy-Item -Path $latestLocalJar.FullName -Destination $JarTarget -Force
    } elseif (-not (Test-Path $JarTarget) -or (Get-Item $JarTarget).Length -lt 200000000) {
        $JarUrl = "https://github.com/Stirling-Tools/Stirling-PDF/releases/latest/download/Stirling-PDF.jar"
        $JarDownload = Join-Path $DownloadsDir "Stirling-PDF.jar"
        Download-FileWithCurl -Url $JarUrl -OutFile $JarDownload -Description "Stirling-PDF Full-Stack JAR (with Web UI)"
        Copy-Item -Path $JarDownload -Destination $JarTarget -Force
    } else {
        Write-Host "[OK] Stirling-PDF.jar (with Web UI) already present in staging." -ForegroundColor Yellow
    }
}

# Clean up old server-only jar if present
$oldServerJar = Join-Path $StagingDir "app\Stirling-PDF-server.jar"
if (Test-Path $oldServerJar) { Remove-Item -Force $oldServerJar -ErrorAction SilentlyContinue }

# ----------------------------------------------------
# 2. Minimal Custom JRE (via jlink)
# ----------------------------------------------------
$JreTarget = Join-Path $StagingDir "jre"
$needJreBuild = $true
$releaseFile = Join-Path $JreTarget "release"
if (Test-Path $releaseFile) {
    $relContent = Get-Content $releaseFile -Raw
    if ($relContent -match 'JAVA_VERSION="25\.') {
        $needJreBuild = $false
        Write-Host "[OK] Custom JRE 25 already present in staging." -ForegroundColor Yellow
    } else {
        Write-Host "[!] Existing JRE is not Java 25. Rebuilding runtime..." -ForegroundColor Yellow
    }
}

if ($needJreBuild) {
    Write-Host "[-] Creating minimal custom JRE 25 via jlink..." -ForegroundColor Cyan
    if (Test-Path $JreTarget) {
        Remove-Item -Recurse -Force $JreTarget
    }
    
    $modules = "java.base,java.compiler,java.desktop,java.instrument,java.logging,java.management,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.transaction.xa,java.xml,java.xml.crypto,jdk.crypto.ec,jdk.crypto.cryptoki,jdk.unsupported,jdk.dynalink,jdk.crypto.mscapi,jdk.zipfs"
    & $JLink --add-modules $modules --output $JreTarget --no-header-files --no-man-pages --strip-debug --compress=2
    
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$JreTarget\bin\javaw.exe")) {
        throw "jlink failed to create stripped JRE runtime"
    }

    # Reset read-only flags
    Get-ChildItem -Recurse -File $JreTarget | ForEach-Object { $_.IsReadOnly = $false }
    Write-Host "[OK] Custom minimal JRE 25 created at $JreTarget" -ForegroundColor Green
}

# ----------------------------------------------------
# 3. Portable LibreOffice
# ----------------------------------------------------
$LibreOfficeTarget = Join-Path $StagingDir "libreoffice"
if (-not (Test-Path "$LibreOfficeTarget\program\soffice.bin")) {
    $LoUrl = "https://download.documentfoundation.org/libreoffice/portable/26.2.4/LibreOfficePortable_26.2.4_MultilingualStandard.paf.exe"
    $LoDownload = Join-Path $DownloadsDir "LibreOfficePortable.paf.exe"
    Download-FileWithCurl -Url $LoUrl -OutFile $LoDownload -Description "LibreOffice Portable"
    
    Write-Host "[-] Extracting LibreOffice application files with 7-Zip..." -ForegroundColor Cyan
    $LoTempExtract = Join-Path $DownloadsDir "lo_extracted"
    if (Test-Path $LoTempExtract) { Remove-Item -Recurse -Force $LoTempExtract }
    
    # Extract only App/libreoffice/*
    & $SevenZip x "$LoDownload" "-o$LoTempExtract" "App\libreoffice\*" -y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed to extract LibreOffice from $LoDownload"
    }
    
    New-Item -ItemType Directory -Force -Path $LibreOfficeTarget | Out-Null
    Copy-Item -Path "$LoTempExtract\App\libreoffice\*" -Destination $LibreOfficeTarget -Recurse -Force
    Remove-Item -Recurse -Force $LoTempExtract -ErrorAction SilentlyContinue
    
    if (-not (Test-Path "$LibreOfficeTarget\program\soffice.bin")) {
        throw "soffice.bin not found after LibreOffice extraction in $LibreOfficeTarget\program\"
    }
    Write-Host "[OK] LibreOffice staged successfully at $LibreOfficeTarget" -ForegroundColor Green
} else {
    Write-Host "[OK] LibreOffice already present in staging." -ForegroundColor Yellow
}

# ----------------------------------------------------
# 4. Tesseract OCR + Traineddata
# ----------------------------------------------------
$TesseractTarget = Join-Path $StagingDir "tesseract"
if (-not (Test-Path "$TesseractTarget\tesseract.exe")) {
    $TessUrl = "https://github.com/UB-Mannheim/tesseract/releases/download/v5.4.0.20240606/tesseract-ocr-w64-setup-5.4.0.20240606.exe"
    $TessDownload = Join-Path $DownloadsDir "tesseract-setup.exe"
    Download-FileWithCurl -Url $TessUrl -OutFile $TessDownload -Description "Tesseract OCR Windows Installer"
    
    Write-Host "[-] Extracting Tesseract binaries with 7-Zip..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $TesseractTarget | Out-Null
    # Extract installer files into staging/tesseract/
    & $SevenZip x "$TessDownload" "-o$TesseractTarget" -y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$TesseractTarget\tesseract.exe")) {
        throw "7-Zip failed to extract Tesseract OCR"
    }
    # Clean up unneeded uninstaller or nsis files if any
    Remove-Item -Path "$TesseractTarget\`$*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$TesseractTarget\Uninstall.exe*" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Tesseract binaries staged successfully at $TesseractTarget" -ForegroundColor Green
} else {
    Write-Host "[OK] Tesseract binaries already present in staging." -ForegroundColor Yellow
}

# English traineddata
$TessdataDir = Join-Path $TesseractTarget "tessdata"
New-Item -ItemType Directory -Force -Path $TessdataDir | Out-Null
$EngDataTarget = Join-Path $TessdataDir "eng.traineddata"
if (-not (Test-Path $EngDataTarget) -or (Get-Item $EngDataTarget).Length -lt 1000000) {
    $EngUrl = "https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata"
    Download-FileWithCurl -Url $EngUrl -OutFile $EngDataTarget -Description "Tesseract English traineddata"
    Write-Host "[OK] eng.traineddata staged successfully." -ForegroundColor Green
} else {
    Write-Host "[OK] eng.traineddata already present." -ForegroundColor Yellow
}

# ----------------------------------------------------
# 5. QPDF
# ----------------------------------------------------
$QpdfTarget = Join-Path $StagingDir "qpdf"
if (-not (Test-Path "$QpdfTarget\bin\qpdf.exe")) {
    $QpdfUrl = "https://github.com/qpdf/qpdf/releases/download/v11.9.1/qpdf-11.9.1-msvc64.zip"
    $QpdfDownload = Join-Path $DownloadsDir "qpdf-msvc64.zip"
    Download-FileWithCurl -Url $QpdfUrl -OutFile $QpdfDownload -Description "QPDF MSVC64 Zip"
    
    Write-Host "[-] Extracting QPDF with 7-Zip..." -ForegroundColor Cyan
    $QpdfTempExtract = Join-Path $DownloadsDir "qpdf_extracted"
    if (Test-Path $QpdfTempExtract) { Remove-Item -Recurse -Force $QpdfTempExtract }
    
    & $SevenZip x "$QpdfDownload" "-o$QpdfTempExtract" -y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed to extract QPDF"
    }
    
    # Locate extracted bin directory
    $extractedBin = Get-ChildItem -Path $QpdfTempExtract -Recurse -Filter "qpdf.exe" | Select-Object -First 1
    if (-not $extractedBin) {
        throw "Could not find qpdf.exe in extracted archive"
    }
    $extractedRootDir = Split-Path -Parent (Split-Path -Parent $extractedBin.FullName)
    
    New-Item -ItemType Directory -Force -Path $QpdfTarget | Out-Null
    Copy-Item -Path "$extractedRootDir\bin" -Destination $QpdfTarget -Recurse -Force
    Remove-Item -Recurse -Force $QpdfTempExtract -ErrorAction SilentlyContinue
    
    if (-not (Test-Path "$QpdfTarget\bin\qpdf.exe")) {
        throw "qpdf.exe not found at $QpdfTarget\bin\qpdf.exe"
    }
    Write-Host "[OK] QPDF staged successfully at $QpdfTarget\bin" -ForegroundColor Green
} else {
    Write-Host "[OK] QPDF already present in staging." -ForegroundColor Yellow
}

# ----------------------------------------------------
# 6. Brand Icon
# ----------------------------------------------------
$RepoRoot = Split-Path -Parent $BaseDir
$IconSource = Join-Path $RepoRoot "frontend\editor\src\core\assets\brand\modern-logo\favicon.ico"
if (-not (Test-Path $IconSource)) {
    $IconSource = Join-Path $RepoRoot "app\core\src\main\resources\static\favicon.ico"
}
if (Test-Path $IconSource) {
    Copy-Item -Path $IconSource -Destination "$StagingDir\app\icon.ico" -Force
    Copy-Item -Path $IconSource -Destination "$StagingDir\launcher\icon.ico" -Force
    Write-Host "[OK] Brand icons staged successfully." -ForegroundColor Green
}

# ----------------------------------------------------
# 7. Native Desktop Launcher (StirlingPDF.exe)
# ----------------------------------------------------
Write-Host "[-] Building native desktop launcher (StirlingPDF.exe)..." -ForegroundColor Cyan
$LauncherSrc = Join-Path $BaseDir "launcher\Program.cs"
$LauncherTarget = Join-Path $StagingDir "StirlingPDF.exe"
$Csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$IconPath = Join-Path $StagingDir "app\icon.ico"

if (-not (Test-Path $Csc)) {
    throw "C# compiler (csc.exe) not found at $Csc"
}

& $Csc /nologo /target:winexe /win32icon:"$IconPath" /out:"$LauncherTarget" /reference:System.Windows.Forms.dll,System.Drawing.dll,System.dll "$LauncherSrc"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $LauncherTarget)) {
    throw "Failed to compile StirlingPDF.exe launcher"
}
Write-Host "[OK] StirlingPDF.exe compiled successfully." -ForegroundColor Green

Write-Host ""
Write-Host "[OK] All dependencies fetched and verified successfully!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
