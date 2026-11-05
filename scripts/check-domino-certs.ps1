<#
.SYNOPSIS
    唯讀清查：找出 Domino / Notes 目錄下的 cacert.pem 與 Java cacerts，
    並列出其中與 eMudhra / emSign / AAA 相關的憑證。

.DESCRIPTION
    針對 CVE-2026-91403（eMudhra/emSign CA 私鑰外洩）事件。
    本腳本「完全不修改任何檔案」——只做 Get-ChildItem、Select-String、
    與 keytool -list（-list 不會改 keystore）。範圍限定在你指定的 Domino/
    Notes 路徑，不掃整機，避免碰到不相干軟體的憑證庫。

    有找到 = 這台有可移除標的，依 SOP.md 備份後處理。
    沒找到 = 這台沒這問題。

.PARAMETER Path
    要掃描的 Domino 或 Notes 安裝 / Data 根目錄。可給多個。

.PARAMETER StorePass
    Java cacerts 的密碼，預設 changeit。若你改過 keystore 密碼請指定。

.EXAMPLE
    .\check-domino-certs.ps1 -Path "D:\HCL\Domino","D:\HCL\Notes"

.NOTES
    Windows PowerShell 5.1。唯讀，不需系統管理員（除非目錄本身需要權限才能讀）。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,

    [string]$StorePass = "changeit"
)

$ErrorActionPreference = "Continue"
$keywords = @("emSign", "emudhra", "AAA Certificate Services")

function Write-Section($title) {
    Write-Host ""
    Write-Host "==== $title ====" -ForegroundColor Cyan
}

foreach ($root in $Path) {
    if (-not (Test-Path $root)) {
        Write-Host "[略過] 路徑不存在：$root" -ForegroundColor Yellow
        continue
    }

    Write-Section "掃描根目錄：$root"

    # --- 1) 找出 cacert.pem 與 cacerts ---
    $pems    = Get-ChildItem -Path $root -Recurse -Filter "cacert.pem" -File -ErrorAction SilentlyContinue
    $stores  = Get-ChildItem -Path $root -Recurse -Filter "cacerts"    -File -ErrorAction SilentlyContinue

    Write-Host ("找到 cacert.pem {0} 個、cacerts {1} 個" -f $pems.Count, $stores.Count)

    # --- 2) cacert.pem：找關鍵字標籤 ---
    foreach ($pem in $pems) {
        Write-Section "cacert.pem：$($pem.FullName)"
        $hits = Select-String -Path $pem.FullName -Pattern $keywords -SimpleMatch -ErrorAction SilentlyContinue
        if ($hits) {
            $hits | ForEach-Object { Write-Host ("  行 {0}: {1}" -f $_.LineNumber, $_.Line.Trim()) -ForegroundColor Green }
        } else {
            Write-Host "  未命中關鍵字（可能無目標憑證，或 PEM 無人類可讀標籤需改用解碼比對）" -ForegroundColor DarkGray
        }
    }

    # --- 3) cacerts：用同目錄樹裡的 keytool.exe -list ---
    foreach ($store in $stores) {
        Write-Section "cacerts：$($store.FullName)"

        # 嘗試在這個 cacerts 所屬的 jvm 下找對應的 keytool.exe
        $jvmRoot = Split-Path (Split-Path (Split-Path $store.FullName))  # ...\jvm\lib\security\cacerts -> ...\jvm
        $keytool = Join-Path $jvmRoot "bin\keytool.exe"

        if (-not (Test-Path $keytool)) {
            $keytool = (Get-ChildItem -Path $root -Recurse -Filter "keytool.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        }

        if (-not $keytool -or -not (Test-Path $keytool)) {
            Write-Host "  找不到 keytool.exe，無法列舉此 cacerts（可手動用新版 keytool -list -keystore ... 查）" -ForegroundColor Yellow
            continue
        }

        Write-Host "  使用 keytool：$keytool" -ForegroundColor DarkGray
        $list = & $keytool -list -keystore $store.FullName -storepass $StorePass 2>&1
        $hits = $list | Select-String -Pattern $keywords -SimpleMatch
        if ($hits) {
            $hits | ForEach-Object { Write-Host "  $($_.Line.Trim())" -ForegroundColor Green }
            Write-Host "  （要看指紋確認身分：keytool -list -v -alias <別名> -keystore ... -storepass ...）" -ForegroundColor DarkGray
        } else {
            Write-Host "  未命中關鍵字（此 cacerts 可能無目標憑證；或密碼非 '$StorePass'）" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "清查完成。本腳本未修改任何檔案。若有命中，依 SOP.md 備份後再移除。" -ForegroundColor Cyan
