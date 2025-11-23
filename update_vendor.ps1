<#
.SYNOPSIS
    PEShell 依赖管理脚本：下载 Header-Only 库和 Lua 脚本
#>
$ErrorActionPreference = "Stop"

# === 配置 ===
$VendorDir = Join-Path $PSScriptRoot "vendor"

# 依赖源 URL
$ProcUtilsUrl = "https://raw.githubusercontent.com/daiaji/proc_utils/refs/heads/main/proc_utils_ffi.lua"
$LfsFfiUrl    = "https://raw.githubusercontent.com/daiaji/luafilesystem/main/lfs_ffi.lua"
$CtplUrl      = "https://raw.githubusercontent.com/vit-vit/CTPL/master/ctpl_stl.h"
$LuaUnitUrl   = "https://raw.githubusercontent.com/bluebird75/luaunit/master/luaunit.lua"
# spdlog v1.12.0 (使用较旧但稳定的版本，或者切回 v1.x 最新)
$SpdlogUrl    = "https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.zip"

# === 工具函数 ===
function Ensure-Dir($Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }
function Download($Url, $Dest) { 
    Write-Host "Downloading $Url ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $Dest 
}

Ensure-Dir $VendorDir

# 1. CTPL (C++ Header)
Write-Host "`n[1/5] Updating CTPL..." -ForegroundColor Green
Ensure-Dir "$VendorDir/ctpl"
Download $CtplUrl "$VendorDir/ctpl/ctpl_stl.h"

# 2. spdlog (C++ Header Library)
Write-Host "`n[2/5] Updating spdlog..." -ForegroundColor Green
Ensure-Dir "$VendorDir/spdlog"
if (-not (Test-Path "$VendorDir/spdlog/include")) {
    $Zip = "$VendorDir/spdlog.zip"
    Download $SpdlogUrl $Zip
    Expand-Archive $Zip -DestinationPath $VendorDir -Force
    $Extracted = Get-ChildItem $VendorDir -Directory -Filter "spdlog-*" | Select-Object -First 1
    Move-Item "$($Extracted.FullName)/include" "$VendorDir/spdlog/"
    Remove-Item $Extracted.FullName -Recurse -Force
    Remove-Item $Zip -Force
} else {
    Write-Host "spdlog headers already exist." -ForegroundColor Gray
}

# 3. proc_utils (Lua FFI Source)
Write-Host "`n[3/5] Updating proc_utils_ffi..." -ForegroundColor Green
Ensure-Dir "$VendorDir/proc_utils"
Download $ProcUtilsUrl "$VendorDir/proc_utils/proc_utils_ffi.lua"

# 4. lfs_ffi (Lua FFI Source)
Write-Host "`n[4/5] Updating lfs_ffi..." -ForegroundColor Green
Ensure-Dir "$VendorDir/lfs"
Download $LfsFfiUrl "$VendorDir/lfs/lfs_ffi.lua"

# 5. LuaUnit (Test Framework)
Write-Host "`n[5/5] Updating LuaUnit..." -ForegroundColor Green
Ensure-Dir "$VendorDir/luaunit"
Download $LuaUnitUrl "$VendorDir/luaunit/luaunit.lua"

Write-Host "`n✅ All Dependencies Updated Successfully." -ForegroundColor Green