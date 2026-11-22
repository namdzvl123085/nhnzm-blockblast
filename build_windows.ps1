$ErrorActionPreference = "Stop"
Write-Host "=== NHNZM CLIENT - AUTO BUILD IPA (WSL2 OFFLINE) ===" -ForegroundColor Cyan

if (-not (Test-Path "BlockBlast.ipa")) {
    Write-Host "THIEU FILE: Hay chep file BlockBlast.ipa (da giai ma) vao cung thu muc nay roi chay lai!" -ForegroundColor Red
    Pause
    exit 1
}

$winPath = (Get-Location).Path
$wslPath = (wsl wslpath -a "`"$winPath`"").Trim()

Write-Host "Dang chay bien dich trong WSL Ubuntu tai: $wslPath" -ForegroundColor Yellow
wsl bash -lc "cd '$wslPath' && sed -i 's/$//' build_offline.sh Makefile inject.py && chmod +x build_offline.sh && ./build_offline.sh"

if (Test-Path "NHNZM_BlockBlast.ipa") {
    Write-Host "THANH CONG! Da xuat file NHNZM_BlockBlast.ipa" -ForegroundColor Green
}
Pause
