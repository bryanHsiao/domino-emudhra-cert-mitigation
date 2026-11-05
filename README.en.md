# Domino / Notes eMudhra Certificate Cleanup (CVE-2026-91403)

[繁體中文](README.md) · **English**

Guidance for **auditing and removing** the compromised eMudhra / emSign CA certificates (CVE-2026-91403, CVSS 9.1) from HCL Domino / Notes environments.

Key point: **no large GUI tool is required.** Auditing needs only a one-line `keytool` command that already ships inside every Domino install; removal is a handful of `keytool -delete` calls, a text edit of `cacert.pem`, a Domino Directory edit, and a `cert8.db` file swap. This repo wraps the official steps with read-only auditing, manual backups, and regression testing.

> ⚠️ This is an operational guide; removal steps follow HCL's official **KB0134844**. For production, follow the official KB and validate on a test machine first.

---

## Background and direction

- **Incident**: Several intermediate certificates of the eMudhra (emSign brand) CA had their private keys recoverable, letting an attacker issue trusted forged certificates. Browsers, OpenJDK, and vendors have all moved to **remove / distrust** these roots and related intermediates.
- **The fix is "remove", not "add trust"**: these roots are still **cryptographically valid** in the trust store today — the vulnerability is that they will **wrongly succeed** in accepting forged certificates. So you take them *out* of the trust store rather than adding anything.

## Official reference and applicable versions

HCL KB **KB0134844** is the authoritative source; it contains 4 Security Bulletins: **KB0134742 / KB0134847 / KB0134848 / KB0134849**. Official "Applies to" = **12.0.2 Fixpack 8 and earlier, 14.0 Fixpack 5 and earlier, 14.5.1 Fixpack 1 and earlier**. Until official fix releases are available, apply the manual steps below.

- CVE: **CVE-2026-91403**
- 9.0.1 is **not** in the official Applies-to list; empirically its bundled JVM `cacerts` usually has **no** emSign. If you need to handle 9.0.1, audit it read-only first (SOP section 0) rather than copying someone else's assumptions.

## The four certificate stores involved

KB0134844 removes emSign and Comodo CA Limited certificates from **four** stores:

| Store | Location | Action |
|---|---|---|
| **Java `cacerts`** | bundled JVM `jvm/lib/security/cacerts` (one on server, one in client) | Remove emSign (the official keytool example targets **emSign ECC Root CA - G3**; `-list` first to confirm actual aliases) |
| **`cacert.pem`** | Data directory (libcurl, used by LotusScript / OIDC etc.) | Delete **3 emSign certs**: `emSign ECC Root CA - G3`, `emSign Root CA - C1`, `emSign ECC Root CA - C3`; **older versions also delete Comodo AAA** |
| **`names.nsf`** (Domino Directory) | Security → Certificates view | **Comodo AAA is pre-populated — remove it**; then replicate the NAB and restart servers one at a time. Also remove any affected CAs you manually added (incl. `certstore.nsf`) |
| **`cert8.db`** (Notes client) | `…\Data\workspace\BrowserProfile\` | After backup, replace with the clean `cert8.db` provided in KB0134844 (removes Comodo AAA) |

> ⚠️ HCL's three `cacert.pem` certs do **not** include `emSign Root CA - G1`; some third parties also remove G1 (4 total) as extra hardening — decide based on your connectivity regression.
> Platform exceptions: **iSeries** uses a separate `cacert.kdb` and is not affected by libcurl (its IBM JVM — contact IBM); **Notes on Mac** relies on the system keychain (apply the latest macOS updates).

## Why you don't need a big program

A "scan-every-drive, GUI, confirm-each-cert, write-logs" tool is ~99% bundled runtime; the actual logic is a few lines — and those lines are `keytool`, which is already built into every Domino. The `names.nsf` and `cert8.db` steps are plain Domino-admin / file operations either way.

- **Audit**: `keytool -list -v ... | Select-String "emSign","emudhra","AAA"`, plus inspecting `cacert.pem`. That's what [`scripts/check-domino-certs.ps1`](scripts/check-domino-certs.ps1) does (read-only).
- **Remove**: a few `keytool -delete -alias <alias> ...` calls, a manual text edit of `cacert.pem`, a Directory edit, and a `cert8.db` swap.
- A big tool's only added value is the GUI, auto-discovery across the whole machine, and centralized logging — at the cost of a **large blast radius** (it also touches unrelated software's `cacerts`) and no transparency.

Full steps in **[SOP.md](SOP.md)** (written in Traditional Chinese; commands are standard PowerShell / keytool and copy-paste directly).

## ⚠️ Regression risk (where it most often breaks)

Removing these roots will break connections to any endpoint whose certificate chain terminates **only** at them.

- **Test endpoints chaining to `AAA Certificate Services` first**: it's a widely used old root, so its removal has a much larger blast radius than emSign.
- Then test endpoints chaining to emSign (eMudhra is an Indian CA — Indian government / bank / enterprise APIs warrant extra attention).
- Always run the full procedure and regression tests on a **test machine matching production versions**, confirm you can roll back, before touching production.

## Files

- [`SOP.md`](SOP.md) — reproducible audit → backup → remove → regression → rollback procedure
- [`scripts/check-domino-certs.ps1`](scripts/check-domino-certs.ps1) — read-only audit script (Windows PowerShell)

## License

MIT (see [`LICENSE`](LICENSE)). Provided "as is" with no warranty; use at your own risk and validate on a test machine first.
