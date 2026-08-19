# ==============================================================================
# Valapp Production Release Build Script (PowerShell)
# Builds Universal APK, Split-per-ABI APKs, and Google Play App Bundle (AAB)
# With full R8 Minification, Resource Shrinking, & Dart Obfuscation
# ==============================================================================

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  VALAPP - PRODUCTION RELEASE BUILD AUTOMATION" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Verification
Write-Host "
[1/6] Running static code analysis..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Host "Analysis failed! Fix lint errors before building." -ForegroundColor Red
    exit 1
}

# 2. Prepare Output Directories
Write-Host "
[2/6] Preparing output directories..." -ForegroundColor Yellow
$OutputDir = Join-Path $ProjectRoot "build_output"
$SymbolsDir = Join-Path $ProjectRoot "symbols"
if (Test-Path $OutputDir) { Remove-Item -Recurse -Force $OutputDir }
if (Test-Path $SymbolsDir) { Remove-Item -Recurse -Force $SymbolsDir }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $SymbolsDir | Out-Null

# 3. Build Universal APK
Write-Host "
[3/6] Compiling Universal Release APK (with R8 + Obfuscation)..." -ForegroundColor Yellow
flutter build apk --release --obfuscate --split-debug-info=$SymbolsDir
if ($LASTEXITCODE -ne 0) { exit 1 }

# 4. Build Split-per-ABI APKs
Write-Host "
[4/6] Compiling Split-per-ABI Release APKs..." -ForegroundColor Yellow
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=$SymbolsDir
if ($LASTEXITCODE -ne 0) { exit 1 }

# 5. Build Android App Bundle (AAB)
Write-Host "
[5/6] Compiling Google Play App Bundle (AAB)..." -ForegroundColor Yellow
flutter build appbundle --release --obfuscate --split-debug-info=$SymbolsDir
if ($LASTEXITCODE -ne 0) { exit 1 }

# 6. Collect Artifacts
Write-Host "
[6/6] Collecting and organizing release artifacts..." -ForegroundColor Yellow
$ApkSourceDir = Join-Path $ProjectRoot "build\app\outputs\flutter-apk"
$BundleSourceDir = Join-Path $ProjectRoot "build\app\outputs\bundle\release"

Get-ChildItem -Path $ApkSourceDir -Filter "*.apk" | ForEach-Object {
    $DestName = $_.Name -replace "app-", "Valapp-"
    Copy-Item -Path $_.FullName -Destination (Join-Path $OutputDir $DestName)
}

Get-ChildItem -Path $BundleSourceDir -Filter "*.aab" | ForEach-Object {
    $DestName = $_.Name -replace "app-", "Valapp-"
    Copy-Item -Path $_.FullName -Destination (Join-Path $OutputDir $DestName)
}

Write-Host "
======================================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE - RELEASE ARTIFACTS GENERATED" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Get-ChildItem -Path $OutputDir | ForEach-Object {
    $SizeMB = [math]::Round($_.Length / 1MB, 2)
    $Hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.Substring(0, 16)
    Write-Host ("  - {0,-32} ({1,5} MB)  SHA256: {2}..." -f $_.Name, $SizeMB, $Hash) -ForegroundColor White
}
Write-Host "
Artifacts saved to: $OutputDir" -ForegroundColor Cyan
Write-Host "Obfuscation symbols saved to: $SymbolsDir
" -ForegroundColor Cyan
