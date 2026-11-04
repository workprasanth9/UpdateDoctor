# Standalone Jamf Pro Extension Attribute (pure bash)

[`Jamf/updatedoctor-ea-standalone.sh`](../Jamf/updatedoctor-ea-standalone.sh) is a single bash script that runs most of the UpdateDoctor checks without the `updatedoctor` binary. Use it when you do not want to deploy a package just to collect inventory. It only reads; it never installs, downloads, schedules or changes anything.

The goal is the question MDM update commands never answer: **why** did the update not install. When softwareupdated has recorded a DDM error, the EA shows its reason and timestamp, along with the other conditions that commonly stop an install (disk, power, network, stale catalog, deferral, Bootstrap Token).

## Jamf Pro setup

1. Settings > Computer management > Extension attributes > New.
2. Display name: `UpdateDoctor` (any name works).
3. Data type: **String**. Input type: **Script**.
4. Paste the contents of `updatedoctor-ea-standalone.sh` and save.
5. Inventory updates now collect the value. Build Smart Groups with criteria such as:
   - `UpdateDoctor` `like` `BLOCKED` for Macs that will likely miss a deadline.
   - `UpdateDoctor` `like` `ddm_errors` for Macs where softwareupdated recorded a DDM failure.
   - `UpdateDoctor` `like` `bootstrap_token` or `like` `disk_space` for one specific reason.

Jamf runs Extension Attributes as root, so every check runs. Run by hand without sudo, the script still works and lists `bootstrap_token (needs root)` under `skipped`.

Runtime on a MacBook Air (Apple silicon, macOS 26.7) is about 3 seconds, mostly the GDMF download and six HTTPS probes. It does not run `softwareupdate -l` (slow); it reads the update list softwareupdated already cached.

## Output

One line, always wrapped in a single `<result>...</result>`:

```
VERDICT | fail: id (reason); ... | warn: id (reason); ... | info: ... | skipped: id (why); ... | ud-sh 1.2.0
```

- `VERDICT` is `BLOCKED` (any fail), `AT_RISK` (any warn) or `HEALTHY`, the same as `updatedoctor doctor --ea`.
- Sections without entries are left out. The line is capped at 1000 characters.

Real output from the test Mac, run as a normal admin user (not root):

```
<result>BLOCKED | fail: ddm_errors (Software update failed. x1 at 2026-11-01T18:30:32-06:00) | warn: os_version (26.7 behind 26.7.2, macOS 27.2 also supported); power (on battery at 21%, install may wait for power) | info: macOS 26.7 (25G229), offered: Safari 27.2, macOS Tahoe 26.7.2, FileVault on, beta catalog, not MDM enrolled | ud-sh 1.2.0</result>
```

That Mac is not MDM enrolled, so the Bootstrap Token check does not apply and is not listed.

## Checks

| ID | What it reads | Needs root | Tested on a real Mac |
|---|---|---|---|
| `os_version` | `sw_vers`, `ioreg` device ID, Apple's GDMF feed via curl (with the System keychain roots, because curl's own bundle does not trust gdmf.apple.com) | No | Yes |
| offered updates (info) | `RecommendedUpdates` cached in `/Library/Preferences/com.apple.SoftwareUpdate.plist` | No | Yes |
| `disk_space` | `diskutil info -plist /`, APFS container free space (fail under 15 GB, warn under 25 GB) | No | Yes |
| `power` | `pmset -g batt` (warn on battery under 50 percent) | No | Yes |
| `network` | HTTPS reachability of the six Apple update hosts | No | Yes (all reachable) |
| `mdm_enrollment` | `profiles status -type enrollment` | No | Yes, but only the not enrolled case. Enrolled cases are fixture tested only. |
| `bootstrap_token` | `profiles status -type bootstraptoken` | **Yes** | Fixture tested only (test Mac is not enrolled) |
| FileVault (info) | `fdesetup status` | No | Yes |
| `ddm_errors` | `DDMPersistedErrorKey` in the Software Update plist, with reason, count and timestamp | No | Yes (the test Mac has a real recorded DDM error) |
| `su_history` | `LastSuccessfulDate`, `LastResultCode`, `CatalogURL` (beta catalog is info, custom catalog warns) | No | Yes for a recent scan and a beta catalog. Stale scan and custom catalog are fixture tested only. |
| auto settings (info) | Automatic check, download, install flags, managed profile first | No | Yes (none off) |
| deferral (info) | `/Library/Managed Preferences/com.apple.applicationaccess.plist` | No | Fixture tested only (no profile on the test Mac) |
| `install_log` | `/var/log/install.log`, last 7 days, lines from softwareupdated or installd that say an install, prepare, apply or download failed | No (the file is world readable) | Yes, no matching lines. The failure case is fixture tested only. |

## Not ported, still in the CLI

- `softwareupdate -l` live scan: can take a minute or more, too slow for inventory. The EA reports the cached list instead.
- Unified log errors (`log show --last 24h`): slow (often over a minute) and noisy. Use `updatedoctor doctor --logs` on one Mac.
- JSON and text reports and per check fix advice: the EA keeps the value short for Jamf. Use the CLI for the full explanation.

MDM enrollment (enrolled cases), Bootstrap Token, managed deferral and DDM declaration behavior on a managed Mac are covered by fixture tests only. I have not run this EA on a Jamf managed Mac.

## Tests

`Scripts/test-ea-standalone.sh` runs 29 fixture cases from `Tests/ea-standalone/base` with `/bin/bash` (3.2) and needs no root, MDM or network. CI runs it plus `shellcheck` on every push.

Test hooks (environment variables, none set by Jamf): `UD_FIXTURES=dir`, `UD_NOW=epoch`, `UD_AS_ROOT=0|1`, `UD_OFFLINE=1`.
