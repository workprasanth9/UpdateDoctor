# UpdateDoctor

**Why didn't this Mac update?** `updatedoctor` answers that in one command.

It runs a read only checklist on a Mac, compares the installed macOS with Apple's own release feed for that exact hardware, and prints a verdict with a reason and a recommended fix for every problem. It is built for the macOS 26 world, where updates are enforced by MDM through Declarative Device Management (DDM) and a missed deadline usually comes down to one quiet blocker: no Bootstrap Token, not enough disk, a laptop on battery, a filtered update host, a deferral profile, or a DDM error.

```
$ sudo updatedoctor doctor
UpdateDoctor 1.0.0  2026-10-28T14:23:50Z
Verdict: AT_RISK

[WARN] macOS version vs Apple GDMF feed
       macOS 26.7 (25G229) on Mac16,12 is behind macOS 26.7.2 (25G332), posted 2026-10-26.
       Fix: Install the update from System Settings > General > Software Update, or let your MDM's DDM software update declaration enforce it.
[PASS] Free space in the APFS container
       27.9 GB free.
[WARN] Power source and battery
       On battery at 40%. Laptops may postpone installing until plugged in or charged.
       Fix: Connect to power before the enforced install time.
...
```

(Shortened real output from a MacBook Air running macOS 26.7.)

## Install

Homebrew, one line. No `brew trust` step is needed, because this is a formula, not a cask:

```bash
brew install workprasanth9/tap/updatedoctor
```

Installer package (installs `/usr/local/bin/updatedoctor`, good for Jamf):
download `UpdateDoctor-1.0.0.pkg` from the [latest release](https://github.com/workprasanth9/UpdateDoctor/releases/latest).

Plain binary: download `updatedoctor-1.0.0-macos-universal.tar.gz` from the release, extract it, and put `updatedoctor` on your PATH. If you download it in a browser, macOS may quarantine it; run `xattr -d com.apple.quarantine updatedoctor` once. The binary is ad hoc signed, not notarized.

Requires macOS 13 or later. Universal binary for Apple silicon and Intel.

## Usage

```bash
updatedoctor doctor            # full checklist, human readable
sudo updatedoctor doctor       # adds the Bootstrap Token check (needs root)
updatedoctor doctor --json     # full report as JSON
updatedoctor doctor --ea       # one line for a Jamf Pro Extension Attribute
updatedoctor doctor --quick    # skip `softwareupdate -l`, which can take a minute
updatedoctor doctor --offline  # skip the Apple feed and network checks
updatedoctor doctor --logs     # also count recent update errors in the unified log
updatedoctor version
updatedoctor help
```

Exit codes: `0` healthy or at risk, `2` blocked, `64` usage error.

### Verdicts

| Verdict | Meaning |
|---|---|
| `HEALTHY` | Nothing found that would stop an update. |
| `AT_RISK` | At least one warning. The update may be delayed or fail. |
| `BLOCKED` | At least one failing check that will very likely stop the update. |

Each check is `PASS`, `INFO` (worth knowing, not a problem), `WARN`, `FAIL`, or `SKIP` (could not run here, with the reason).

## What each check means

| ID | What it reads | Why it matters |
|---|---|---|
| `os_version` | `sw_vers`, `ioreg` target-type (Apple silicon) or board-id (Intel), and Apple's GDMF feed `https://gdmf.apple.com/v2/pmv` | Finds the newest release in the same major version that Apple lists for this exact device, and says if a newer major supports it too. Warns if the Mac is behind. |
| `pending_updates` | `softwareupdate -l` | What the Mac itself is being offered, including whether a restart is needed. A list that fails to load points at network or catalog problems. |
| `disk_space` | `diskutil info -plist /` (APFS container free space) | Updates need working space. Fails under 15 GB, warns under 25 GB. Apple does not publish one exact number, so these thresholds are conservative heuristics. |
| `power` | `pmset -g batt` | A laptop on low battery may postpone installing. Warns under 50% on battery. |
| `network` | HTTPS request to gdmf, mesu, swscan, swcdn, swdist and updates.cdn-apple.com | These hosts are listed by Apple for software updates ([support article 101555](https://support.apple.com/101555)). Any HTTP answer counts as reachable. TLS inspection or a firewall shows up here. |
| `mdm_enrollment` | `profiles status -type enrollment` | DDM enforcement only exists on an enrolled Mac. Warns if enrolled but not User Approved or ADE. When not enrolled, MDM checks are skipped. |
| `bootstrap_token` | `profiles status -type bootstraptoken` (root only) | On Apple silicon, MDM enforced updates use the Bootstrap Token to authorize the install. Not escrowed is a `FAIL`. |
| `filevault` | `fdesetup status` | Informational. Explains why an unattended restart might need authorization. |
| `ddm_errors` | `DDMPersistedErrorKey` in `/Library/Preferences/com.apple.SoftwareUpdate.plist` | Where softwareupdated keeps errors from DDM software update enforcement. Any entry is a `FAIL`, shown with its raw value. |
| `su_history` | `LastSuccessfulDate`, `LastResultCode`, `CatalogURL` in the same file | Warns if the Mac has not scanned Apple's catalog in 7 days or uses a non Apple catalog. Notes beta catalogs. |
| `auto_settings` | `AutomaticCheckEnabled`, `AutomaticDownload`, `AutomaticallyInstallMacOSUpdates`, managed values first | If these are off, nothing happens until the DDM deadline. |
| `deferral` | `/Library/Managed Preferences/com.apple.applicationaccess.plist` | A restrictions profile can hide new updates for up to 90 days. That alone explains many "why don't I see it" tickets. |
| `update_logs` | `log show --last 24h` for softwareupdated and mobileassetd errors (only with `--logs`) | Gives a count and the latest lines. Many error lines are routine, so this is `INFO`, never a failure. |

UpdateDoctor never installs, downloads, schedules, or changes anything. A unit test checks that no install or download command is ever run.

## Deploy with Jamf Pro

1. Upload `UpdateDoctor-1.0.0.pkg` to Jamf Pro and deploy it with a policy (or install with Homebrew).
2. Create an Extension Attribute: Data type **String**, Input type **Script**, and paste [`Jamf/updatedoctor-ea.sh`](Jamf/updatedoctor-ea.sh). Jamf runs EAs as root, so the Bootstrap Token check is included. It uses `--quick` so inventory stays fast.
3. Build Smart Groups on the value, for example `like BLOCKED` to find Macs that will miss the deadline, and `like bootstrap_token` to find the exact reason.
4. For a full report on one Mac, run a policy with `updatedoctor doctor --json` and read the policy log.

## How this differs from existing tools

Before building this I searched GitHub for tools that diagnose failed macOS updates. Honest summary:

- [Nudge](https://github.com/macadmins/nudge) (about 1,300 stars) and [S.U.P.E.R.M.A.N.](https://github.com/Macjutsu/super) (about 900 stars) are excellent and widely used. Nudge encourages users to update. SUPER drives the whole update and restart workflow and has its own checks inside that workflow. UpdateDoctor does not replace either one.
- [DDM OS Reminder](https://github.com/dan-snelson/DDM-OS-Reminder) (about 130 stars) shows end user messages for DDM enforced deadlines.
- [SOFA](https://github.com/macadmins/sofa) (about 460 stars) is a feed of Apple release data. UpdateDoctor reads Apple's GDMF feed directly instead.
- Many script collections cover single pieces, for example one Extension Attribute for Bootstrap Token status or free disk space.

I did not find an open source tool whose only job is to answer "why didn't this Mac update" as a single read only diagnosis that combines Apple's feed for the exact device, DDM error state, Bootstrap Token, disk, power, network, deferrals and scan history, with JSON and Jamf EA output. That is the gap UpdateDoctor fills: it explains, it does not enforce. It works next to Nudge, SUPER, or your MDM's DDM declarations. The search was not exhaustive, so if you know a tool that does this, please open an issue.

## Tested on a real Mac vs fixtures only

Be clear about what was proven where:

- **Real Mac (MacBook Air, Mac16,12, Apple silicon, macOS 26.7, not MDM enrolled, not root):** every check ran. It correctly found the Mac was behind 26.7.2, listed the offered updates, read disk, battery, FileVault, network, scan history (and the beta catalog), and the DDM error record (empty). It skipped the Bootstrap Token check with the reason. `--json`, `--ea`, `--quick`, `--offline` and `--logs` were all run there.
- **Fixtures only:** MDM enrolled Macs, Bootstrap Token escrowed and missing, a non empty DDM error record, managed deferral profiles, low disk, AC power, and Intel board-id matching. These outputs are synthetic files modeled on the documented formats (named `synthetic_*` in `Tests/UpdateDoctorKitTests/Fixtures`). They have **not** been verified on a real managed Mac yet. Reports from managed fleets are very welcome.
- **GitHub Actions (macos-15 runner):** build, tests, universal binary and a smoke run of `doctor`.

## Building from source

```bash
swift build -c release
swift test                 # needs Xcode (XCTest)
swift run fixture-tests    # same tests, works with only the Command Line Tools
./Scripts/build-release.sh [--universal]   # --universal needs Xcode
./Scripts/build-pkg.sh
```

Project layout:

- `Sources/UpdateDoctorKit/` the checks (`Doctor.swift`), pure parsers (`Parsers.swift`), output formats and the `SystemProbe` protocol. Every system read goes through `SystemProbe`, so tests replay recorded output.
- `Sources/updatedoctor/` the command line entry point.
- `Tests/UpdateDoctorKitTests/` XCTest tests and fixtures. `LocalTestRunner/` runs the same files without XCTest.
- `Jamf/` the Extension Attribute script. `Installer/` the pkg thank you page.

## License

MIT. See [LICENSE](LICENSE).
