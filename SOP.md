# SOP — Domino / Notes eMudhra 憑證清查與移除

可重現的流程：**唯讀清查 → 備份 → 移除 → 回歸測試 → 回退**。移除步驟以 HCL 官方 **KB0134844** 為準，前後再加上官方沒寫、但實務上很重要的唯讀清查、手動備份與回歸測試。

> 🔴 **鐵則：絕對不要先在 production 跑。** 先在測試 / 備援機、且版本（Domino / JDK / OS）與 production 一致的環境做，確認回歸測試通過且可回退，再談正式環境。
>
> 指令以 **Windows PowerShell 5.1** 為例（串接用 `;`，不要用 `&&`）。Linux / AIX / Mac 把 `Select-String` 換成 `grep -iE`、`\` 換成 `/`。
>
> 適用版本（官方 Applies to）：**12.0.2 FP8 及更早、14.0 FP5 及更早、14.5.1 FP1 及更早**。9.0.1 不在官方清單內，若要處理請先用步驟 0 唯讀確認有無標的。

---

## 步驟 0、唯讀偵察（先做；完全不修改，零風險）

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

### 目標憑證（公開 root 指紋，供識別用）

| 憑證 | 出現在 | SHA-256（前綴，供快速辨識） |
|---|---|---|
| emSign ECC Root CA - G3 | cacerts + cacert.pem | `86A1ECBA…` |
| emSign Root CA - C1 | cacert.pem | `125609AA…` |
| emSign ECC Root CA - C3 | cacert.pem | `BC4D809B…` |
| AAA Certificate Services (Comodo/Sectigo) | 舊版 cacert.pem、names.nsf、cert8.db | `D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4` |
| emSign Root CA - G1 *(非官方 3 張之一，是否移除有爭議)* | — | `40F6AF03…` |

> 完整指紋以你機器上 `keytool -list -v -alias <別名>` 的輸出為準再比對，避免誤刪只是別名剛好含關鍵字的無辜項目。

---

## 步驟 1、前置準備

1. **確認版本一致**：測試機的 Domino / JDK / OS 與 production 對齊。
2. **全量手動備份**（官方只對 cert8.db 要求備份，其餘務必自行備份）：
   - `cacert.pem`：整個檔另存一份。
   - `cacerts`：連同所在目錄另存一份；記下 keystore 密碼（預設 `changeit`）。
   - `names.nsf`：先做一份複本 / 全站備份。
   - `cert8.db`：複製一份（見 D 節）。
3. **現況存證**（給 before/after 對照）：
   ```powershell
   Get-FileHash "D:\HCL\Domino\Data\cacert.pem" -Algorithm SHA256
   & "D:\HCL\Domino\jvm\bin\keytool.exe" -list -keystore "D:\HCL\Domino\jvm\lib\security\cacerts" -storepass changeit | Select-String "emsign","emudhra","aaa"
   ```
4. **關閉 Notes / Domino** 再動檔（keytool 刪 keystore、置換 cert8.db 都要先關）。

---

## 步驟 2、移除（依 KB0134844）

### A. Java `cacerts`（keytool）

先 `cd` 到 **Notes/Domino 程式目錄** 下的 `jvm\lib\security`，再依版本執行。官方 keytool 範例針對 **emSign ECC Root CA - G3**；先用步驟 0 的 `-list` 確認你這台實際有哪些 emSign 別名。

**12.0.2 Fixpacks（Java 8）**

```powershell
# Windows
..\..\bin\keytool.exe -delete -alias "cn=emsign_ecc_root_ca_-_g3,o=emudhra_technologies_limited,ou=emsign_pki,c=in" -keystore cacerts -storepass changeit
```
```bash
# Linux / AIX / Mac
../../bin/keytool -delete -alias "cn=emsign_ecc_root_ca_-_g3,o=emudhra_technologies_limited,ou=emsign_pki,c=in" -keystore cacerts -storepass changeit
```
> 較舊的 12.0.2 別名格式可能要改成：`-alias "c = in, ou = emsign pki, o = emudhra technologies limited, cn = emsign ecc root ca - g3"`

**14.0 / 14.5.1 Fixpacks（Java 17 或 21）**

```powershell
# Windows（新版用 -cacerts 捷徑，免指路徑/密碼；別名含 [jdk] 後綴）
..\..\bin\keytool.exe -delete -alias "cn_emsign_ecc_root_ca__g3,o_emudhra_technologies_limited,ou_emsign_pki,c_in [jdk]" -cacerts
```
```bash
# Linux / AIX / Mac
../../bin/keytool -delete -alias "cn_emsign_ecc_root_ca__g3,o_emudhra_technologies_limited,ou_emsign_pki,c_in [jdk]" -cacerts
```

移除後再列一次確認：

```powershell
& "D:\HCL\Domino\jvm\bin\keytool.exe" -list -keystore "D:\HCL\Domino\jvm\lib\security\cacerts" -storepass changeit | Select-String "emsign","emudhra","aaa"
```

> 此步為 IBM Semeru runtime 建議做法。**iSeries** 客戶用的是 IBM JVM，請洽 IBM 協助 patch。

### B. `cacert.pem`（文字編輯）

`cacert.pem` 在 Data 目錄，供 libcurl（LotusScript / OIDC 等）做信任根驗證。用編輯器開啟，**刪除下列 3 張 emSign 憑證對應的整段 `-----BEGIN CERTIFICATE-----`…`-----END CERTIFICATE-----`（連同上方標籤）**，存檔：

- `emSign ECC Root CA - G3`
- `emSign Root CA - C1`
- `emSign ECC Root CA - C3`

**舊版 Notes/Domino 另需刪除 `Comodo AAA Services root`（AAA Certificate Services）。**

逐一 diff 備份檔與結果檔，確認只刪了預期區塊。存檔後 hash 存證：

```powershell
Get-FileHash "D:\HCL\Domino\Data\cacert.pem" -Algorithm SHA256
```

> **iSeries**：shipped 的是 `cacert.kdb`，不含受影響 root，不受此步影響。**Notes on Mac**：libcurl 走系統 keychain，請裝最新 macOS 更新。

### C. `names.nsf`（Domino Directory）

Comodo CA Limited 憑證**原廠預載**在 Domino Directory，需移除：

1. 在 Domino administration server 開 `names.nsf`。
2. 進 **Security → Certificates** view。
3. 選名稱為 `CN=AAA Certificate Services/O=Comodo CA Limited/L=Salford/ST=Greater Manchester/C=GB` 的憑證，從 view 刪除。
4. 把 NAB **replicate 到 domain 內所有 server**，再**逐台**（one at a time）重啟。

> 若 Internet certifier 有被 push 到 Notes client 的 names.nsf，也要在 client 的 **Advanced → Certificates** view 一併刪除。
> 若你曾手動把其他受影響 CA 加入 `names.nsf` / `certstore.nsf`，一併移除或換成其他可信 certifier。

### D. Notes client `cert8.db`

Notes client 的瀏覽器 profile 用 `cert8.db`。官方做法是**用 HCL 提供的乾淨版置換**（移除 Comodo AAA）：

1. 從 **KB0134844** 下載乾淨的 `cert8.db`。
2. 關閉 Notes client（置換前 client 至少需完整跑過一次）。
3. 到下列位置**先備份**現有 `cert8.db`，再用下載版覆蓋：
   - Windows 單人安裝：`C:\Program Files\HCL\Notes\Data\workspace\BrowserProfile\`（自訂路徑則 `<Notes>\<Data>\workspace\BrowserProfile\`）
   - Windows 多人安裝：`C:\Users\<user>\AppData\Local\HCL\Notes\Data\workspace\BrowserProfile\`
   - Mac：`~/Library/Application Support/HCL Notes Data/Expeditor/BrowserProfile`

> 美國聯邦政府（USFG）客戶請循 HCL Federal Support Center（FSC）管道處理。

完成 A–D 後重啟 Notes / Domino。

---

## 步驟 3、回歸測試（做完移除後，最重要；官方未涵蓋）

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

## 步驟 4、Rollback（任何一步出問題就回退）

- **`cacert.pem`**：把備份整份複製回去。
- **Java `cacerts`**：把備份整份複製回去（直接換回整個 keystore 最乾淨）。
- **`names.nsf`**：還原備份複本，重新 replicate。
- **`cert8.db`**：把備份複製回原位。
- 回退後重跑步驟 3 回歸測試，確認回到原狀態。
