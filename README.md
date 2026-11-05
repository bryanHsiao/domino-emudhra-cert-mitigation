# Domino / Notes eMudhra 憑證事件清理 (CVE-2026-91403)

針對 **eMudhra / emSign CA 中繼私鑰外洩**（CVE-2026-91403，CVSS 9.1）在 HCL Domino / Notes 環境中的**清查與移除**做法。

重點：**不需要任何大型 GUI 程式**。清查只要 Domino 內建的 `keytool` 一行指令，移除也只是幾個 `keytool -delete` 加上文字編輯 `cacert.pem`。本 repo 把這套最小化、可重現、可回退的流程整理成 SOP 與一支唯讀檢查腳本。

> ⚠️ 本文件是整理自公開 advisory 的操作指引，非官方文件。正式環境請以 HCL 官方 KB 為準，並務必先在測試機驗證。

---

## 背景與方向

- **事件**：eMudhra（emSign 品牌）CA 的多張中繼憑證私鑰可被還原，攻擊者可據以簽發受信任的偽造憑證。各家瀏覽器 / OpenJDK / vendor 均要求**移除 / 不信任（distrust）**這些 root 與相關中繼。
- **方向是「移除」，不是「新增信任」**：這些 root 目前在憑證庫裡**仍然密碼學有效**，漏洞在於它會**錯誤地「成功」**接受偽造憑證。所以要把它們從信任庫拿掉，而不是去加任何東西。
- **官方參考**：
  - HCL KB：**KB0134844**〈What steps are required to protect HCL Notes and Domino from the eMudhra Certificate Compromise issue?〉（內含相關 Security Bulletin）
  - CVE：**CVE-2026-91403**

## 牽涉的三個憑證庫

| 庫 | 位置 | 處理 |
|---|---|---|
| **`cacert.pem`** | Domino server 與 **Notes client 各一份** | 移除受影響的 emSign CA 區塊（HCL 文件列 3 張；部分 vendor 建議連 `emSign Root CA - G1` 共 4 張） |
| **Java `cacerts`** | Domino / Notes 內建 JVM 的 `jvm/lib/security/cacerts` | 依版本可能含 emSign 或 `AAA Certificate Services`（Comodo/Sectigo 老 root）；是否移除 AAA 請依你的對接回歸評估 |
| **`names.nsf` / `certstore.nsf`** | Domino 目錄資料庫 | **只有在你曾手動把這些 CA 加成 Internet cross-certificate 時才需處理**；原廠樣板不出貨這些 root |

> 版本差異很大：舊版（如 9.0.1）內建 JVM 的 `cacerts` 多半**沒有** emSign、但**有** AAA；新版則不同。**不要照抄別人的假設，實測你自己這台**（見 SOP 第〇節）。

## 最小化做法（為什麼不需要大程式）

一支「掃全機、GUI、逐張確認、寫 log」的大型工具，99% 的體積是打包進去的執行環境，真正做事的邏輯只有幾行——而那幾行 `keytool` 本來就內建在每一台 Domino 裡。

- **清查**：`keytool -list -v ... | Select-String "emSign","emudhra","AAA"`，外加看 `cacert.pem`。這就是本 repo 的 [`scripts/check-domino-certs.ps1`](scripts/check-domino-certs.ps1)（純唯讀）。
- **移除**：`keytool -delete -alias <別名> ...` 幾行 + 手動編輯 `cacert.pem` 文字區塊。
- 大程式唯一多買到的是 GUI、自動掃全機、集中 log——代價是**波及面大**（會掃到 Python / git / Node 等不相干軟體的 `cacerts`）且不透明。對「已知的幾台伺服器」而言，手動反而更安全、更可控。

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
