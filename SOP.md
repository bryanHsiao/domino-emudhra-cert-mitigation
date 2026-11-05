# SOP — Domino / Notes eMudhra 憑證清查與移除

可重現的最小化流程：**唯讀清查 → 備份 → 移除 → 回歸測試 → 回退**。全程只用 Domino 內建的 `keytool` 與文字編輯，不需要任何第三方程式。

> 🔴 **鐵則：絕對不要先在 production 跑。** 先在測試 / 備援機、且版本（Domino / JDK / OS）與 production 一致的環境做，確認回歸測試通過且可回退，再談正式環境。
>
> 指令以 **Windows PowerShell 5.1** 為例（串接用 `;`，不要用 `&&`）。Linux / 容器環境把 `Select-String` 換成 `grep -iE`、路徑換成實際安裝路徑即可。

---

## 〇、唯讀偵察（先做；完全不修改，零風險）

目的：在不動任何檔案的前提下，確認「這台到底有沒有這些憑證」「在哪個庫」「移掉的回歸面多大」。**範圍刻意只掃 Domino / Notes 目錄，不掃整機**，避免波及不相干軟體。

```powershell
# 1) 找出 Domino 範圍內的 cacert.pem 與 cacerts（唯讀列舉；路徑換成你的安裝路徑）
Get-ChildItem -Path "D:\HCL\Domino" -Recurse -Include cacert.pem,cacerts -ErrorAction SilentlyContinue | Select-Object FullName
```

```powershell
# 2) 看 cacert.pem 裡有沒有 emSign / eMudhra / AAA 的標籤（唯讀）
Select-String -Path "D:\HCL\Domino\Data\cacert.pem" -Pattern "emSign","eMudhra","AAA Certificate Services" -SimpleMatch
```

```powershell
# 3) 用 keytool 列出 Java cacerts 裡的目標別名（-list 唯讀，不會改檔）
& "D:\HCL\Domino\jvm\bin\keytool.exe" -list -v -keystore "D:\HCL\Domino\jvm\lib\security\cacerts" -storepass changeit | Select-String "emSign","emudhra","AAA Certificate Services"
```

> 或直接用本 repo 的 [`scripts/check-domino-certs.ps1`](scripts/check-domino-certs.ps1) 一次把上面三步跑完。

- **有找到** → 這台確有可移除標的，進入下面的備份與移除。
- **完全沒找到** → 這台沒這問題，不需做任何事。

### 各版路徑與 keytool 寫法

Domino server 與 Notes client **各有一份**內建 JVM `cacerts`，兩邊都要查。

| 版本 | 內建 JVM keytool / cacerts | 備註 |
|---|---|---|
| **9.0.1** | `jvm\bin\keytool.exe` + `jvm\lib\security\cacerts`（`-storepass changeit`） | 舊 JVM，`cacerts` 多半**無 emSign、有 AAA** |
| **12.0.2** | 同上，路徑對應 12.0.2 安裝位置 | |
| **14.5.x** | 新版可用 `keytool -list -v -cacerts`（免指定路徑 / 密碼） | |

> 唯讀清查完請用 `keytool -list -v` 的實際輸出 + SHA-256 指紋對照（見下），**確認抓到的就是目標憑證、不是只是別名剛好含關鍵字的無辜項目**。

### 目標憑證（公開 root 指紋，供識別用）

以下為**公開已知**的 root 憑證 SHA-256 指紋，用來核對你清查到的確實是目標：

| 憑證 | SHA-256 |
|---|---|
| emSign ECC Root CA - G3 | `86A1ECBA...`（以 `keytool -list -v` 實際輸出為準） |
| emSign Root CA - C1 | `125609AA...` |
| emSign Root CA - G1 *(第 4 張，是否移除有爭議)* | `40F6AF03...` |
| emSign ECC Root CA - C3 | `BC4D809B...` |
| AAA Certificate Services (Comodo/Sectigo) | `D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4` |

> 完整指紋請以你機器上 `keytool -list -v -alias <別名>` 的輸出為準再比對；這裡只列前綴供快速辨識。各家對 `emSign Root CA - G1` 與 `AAA Certificate Services` 是否要一併移除看法不一，請依你的對接回歸評估與官方 KB 決定。

---

## 一、前置準備

1. **確認版本一致**：測試機的 Domino / JDK / OS 與 production 對齊。
2. **全量手動備份**：
   - `cacert.pem`：整個目錄另存一份。
   - `cacerts`：連同所在目錄另存一份；記下該 keystore 密碼（預設 `changeit`，若改過要用你的）。
3. **現況存證**（給 before/after 對照）：
   ```powershell
   Get-FileHash "D:\HCL\Domino\Data\cacert.pem" -Algorithm SHA256
   & "D:\HCL\Domino\jvm\bin\keytool.exe" -list -keystore "D:\HCL\Domino\jvm\lib\security\cacerts" -storepass changeit | Select-String "emsign","emudhra","aaa"
   ```

---

## 二、移除

### A. `cacert.pem`（文字編輯）

`cacert.pem` 是純文字 PEM bundle，每張憑證是一段 `-----BEGIN CERTIFICATE-----` … `-----END CERTIFICATE-----`，上方通常有一行人類可讀的標籤（CN / 說明）。

1. 先備份（見上）。
2. 用文字編輯器開 `cacert.pem`，找到目標 emSign 憑證對應的 `BEGIN…END` 區塊。
3. **連同其上方的標籤註解整段刪除**；逐一 diff 備份檔與結果檔，確認**只刪了預期區塊、沒有多刪**。
4. 存檔後重新 hash 存證：
   ```powershell
   Get-FileHash "D:\HCL\Domino\Data\cacert.pem" -Algorithm SHA256
   ```

### B. Java `cacerts`（keytool）

1. 先備份（見上）。
2. 對每個要移除的別名執行：
   ```powershell
   & "D:\HCL\Domino\jvm\bin\keytool.exe" -delete -alias "<別名>" -keystore "D:\HCL\Domino\jvm\lib\security\cacerts" -storepass changeit
   ```
   > 別名用第〇節 `keytool -list` 查到的實際字串。注意：以 `findstr /i "aaa"` 之類比對時，別把「只是剛好含 `aaa`」的無辜 `trustedCertEntry` 誤刪。
3. 移除後再列一次確認只剩該留的：
   ```powershell
   & "D:\HCL\Domino\jvm\bin\keytool.exe" -list -keystore "D:\HCL\Domino\jvm\lib\security\cacerts" -storepass changeit | Select-String "emsign","emudhra","aaa"
   ```

> **Server 與 client 兩份 `cacerts` 都要處理。** 若你的對接端點需要，JDK 另有 blocklist 機制（`blocked.certs` / `blacklisted.certs`，首行 `Algorithm=SHA-256`）可一併封鎖中繼憑證——是否需要、封哪些，請依官方清單，不要憑空列指紋。

---

## 三、回歸測試（做完移除後，最重要）

1. **重現原本會報的操作 / 掃描** → 應不再報。
2. **既有正常流程不可壞**：
   - Domino HTTPS / Internet Site TLS 仍正常。
   - **優先測**：對外 API / adapter / 排程 / agent 中，憑證鏈用到 **`AAA Certificate Services`** 的端點（波及面最大）。
   - 再測鏈到 emSign 的端點。
   - 既有 SSO / 簽核等流程仍可連。
3. 用 openssl 對照憑證鏈前後差異：
   ```powershell
   openssl s_client -connect <host>:443 -showcerts
   ```

---

## 四、Rollback（任何一步出問題就回退）

- **`cacert.pem`**：把備份整份複製回去。
- **Java `cacerts`**：把備份整份複製回去（不要只還原單一別名，直接換回整個 keystore 最乾淨）。
- **blocklist 檔**：刪除新建的 `blocked.certs` / `blacklisted.certs`，或還原備份。
- 回退後重跑第三節回歸測試，確認回到原狀態。
