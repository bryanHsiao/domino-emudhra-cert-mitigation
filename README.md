# Domino / Notes eMudhra 憑證事件清理 (CVE-2026-91403)

**繁體中文** · [English](README.en.md)

> 📖 **線上視覺導讀**（GitHub Pages，兩頁）：① [事件原因](https://bryanhsiao.github.io/domino-emudhra-cert-mitigation/) → ② [該怎麼做：修補步驟](https://bryanhsiao.github.io/domino-emudhra-cert-mitigation/how-to.html)

針對 **eMudhra / emSign CA 中繼私鑰外洩**（CVE-2026-91403，CVSS 9.1）在 HCL Domino / Notes 環境中的**清查與移除**做法。

清查只要 Domino 內建的 `keytool`，移除也只是幾個 `keytool -delete` 加上文字編輯 `cacert.pem`、Domino Directory 編輯與 `cert8.db` 置換。本 repo 把這套可重現、可回退的流程整理成 SOP 與一支唯讀檢查腳本。

> ⚠️ 本文件整理自 HCL 公開 KB [KB0134844](https://support.hcl-software.com/csm?id=kb_article&sys_kb_id=493d196a3b14d31428f8f547f4e45a7c)（eMudhra 憑證事件）。但本文**仍非官方文件**——它是二次整理，另含官方 KB 未涵蓋的步驟（唯讀清查、備份、回歸測試），且 HCL 可能更新該 KB。正式環境一律以**官方 KB 最新版**為準，並務必先在測試機驗證。

---

## 背景與方向

- **事件**：eMudhra（emSign 品牌）CA 的多張中繼憑證私鑰可被還原，攻擊者可據以簽發受信任的偽造憑證。各家瀏覽器 / OpenJDK / vendor 均要求**移除 / 不信任（distrust）**這些 root 與相關中繼。
- **方向是「移除」，不是「新增信任」**：這些 root 目前在憑證庫裡**仍然密碼學有效**，漏洞在於它會**錯誤地「成功」**接受偽造憑證。所以要把它們從信任庫拿掉，而不是去加任何東西。
- **官方參考**：
  - HCL KB：**KB0134844**〈What steps are required to protect HCL Notes and Domino from the eMudhra Certificate Compromise issue?〉（內含相關 Security Bulletin）
  - CVE：**CVE-2026-91403**

## 官方依據與適用版本

HCL 官方 KB **KB0134844** 為權威依據，內含 4 份 Security Bulletin：**KB0134742 / KB0134847 / KB0134848 / KB0134849**。官方「Applies to」= **12.0.2 Fixpack 8 及更早、14.0 Fixpack 5 及更早、14.5.1 Fixpack 1 及更早**；在官方正式修正版釋出前，以下為手動緩解步驟。

> 9.0.1 **不在**官方 KB 的 Applies-to 清單內；且實測 9.0.1 內建 JVM 的 `cacerts` 多半**沒有** emSign。要處理 9.0.1 請先唯讀清查確認有無標的（見 [SOP.md](SOP.md) 步驟 0），不要照抄別人的假設。

## 牽涉的四個憑證庫

KB0134844 明列要從**四個**庫移除 emSign 與 Comodo CA Limited 憑證：

| 庫 | 位置 | 處理 |
|---|---|---|
| **Java `cacerts`** | 內建 JVM `jvm/lib/security/cacerts`（server 與 client 各一份） | 移除 emSign（官方 keytool 範例針對 **emSign ECC Root CA - G3**；請先 `-list` 確認實際別名） |
| **`cacert.pem`** | Data 目錄（libcurl 用於 LotusScript / OIDC 等） | 刪除 **3 張 emSign**：`emSign ECC Root CA - G3`、`emSign Root CA - C1`、`emSign ECC Root CA - C3`；**舊版另刪 Comodo AAA** |
| **`names.nsf`**（Domino Directory） | Security → Certificates view | **Comodo AAA 為原廠預載，需移除**；刪除後 replicate NAB、逐台重啟。另若曾手動加入其他受影響 CA（含 `certstore.nsf`）一併移除 |
| **`cert8.db`**（Notes client） | `…\Data\workspace\BrowserProfile\` | 備份後，以 KB0134844 提供的乾淨 `cert8.db` 置換（移除 Comodo AAA） |

> ⚠️ HCL 官方 cacert.pem 的 3 張**不含** `emSign Root CA - G1`；部分第三方建議連 G1 一起移（共 4 張）屬自行加嚴，請依你的對接回歸評估決定。
> 平台例外：**iSeries** 用獨立 `cacert.kdb`、不受 libcurl 影響（其 IBM JVM 請洽 IBM）；**Notes on Mac** 走系統 keychain（請裝最新 macOS 更新）。

## 做法概覽（都用內建 keytool）

清查與移除都只用 Domino 內建的 `keytool` 與文字編輯，不需要額外安裝工具。

- **清查**：`keytool -list -v ... | Select-String "emSign","emudhra","AAA"`，外加看 `cacert.pem`。這就是本 repo 的 [`scripts/check-domino-certs.ps1`](scripts/check-domino-certs.ps1)（純唯讀）。
- **移除**：`keytool -delete -alias <別名> ...` + 手動編輯 `cacert.pem` 文字區塊；`names.nsf` 走 Domino 管理端刪除、`cert8.db` 以官方乾淨檔置換。
- 建議先唯讀清查確認有無標的，逐台只動目標檔，避免動到不相干軟體的憑證庫。

詳細步驟見 **[SOP.md](SOP.md)**。

## ⚠️ 回歸風險（最容易出事的地方）

移除這些 root 會讓「憑證鏈**只**接到它們」的對方端點**連不上**。

- **先測鏈到 `AAA Certificate Services` 的端點**：這是通用老 root，用很廣，移除後波及面比 emSign 大得多。
- 再測鏈到 emSign 的端點（eMudhra 是印度 CA，印度政府 / 銀行 / 企業 API 風險上較需留意）。
- 一定要先在**版本與 production 一致的測試機**跑完整流程與回歸測試，確認可回退，再談正式環境。

## 檔案

- [`SOP.md`](SOP.md) — 可重現的清查 → 備份 → 移除 → 回歸 → 回退流程
- [`scripts/check-domino-certs.ps1`](scripts/check-domino-certs.ps1) — 純唯讀清查腳本（Windows PowerShell）

## 授權

MIT（見 [`LICENSE`](LICENSE)）。本資料「按現狀」提供，不含任何擔保；操作風險自負，請先在測試機驗證。
