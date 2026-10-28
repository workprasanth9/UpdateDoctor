# Changelog

## 1.1.0 (2026-10-28)

- New `UpdateDoctor.app` menu bar app. A green, yellow or red dot shows HEALTHY, AT_RISK or BLOCKED. The dropdown lists each check with its status and reason, the last checked time, Check now, Run full check (admin), Start at login, About and Quit.
- Checks run on launch and every 30 minutes without root. Root only checks show as Needs admin. Run full check (admin) runs the bundled CLI once through the standard macOS administrator prompt. No privileged helper.
- The app uses the same `UpdateDoctorKit` checks as the CLI. The CLI is unchanged.
- The pkg now installs the app in /Applications as well as the CLI. New `UpdateDoctor-<version>-app.zip` release asset and `updatedoctor-app` Homebrew cask.
- 6 new tests for the menu bar status mapping (25 in total).

## 1.0.0 (2026-10-28)

First release.

- `updatedoctor doctor` runs 13 read only checks and prints a verdict (HEALTHY, AT_RISK or BLOCKED) with a reason and a fix for each problem.
- Compares the installed macOS with Apple's GDMF feed for this exact device (target-type or board-id).
- Checks offered updates, free APFS container space, power, Apple update host reachability, MDM enrollment, Bootstrap Token escrow (root), FileVault, DDM persisted software update errors, scan history and CatalogURL, automatic update settings, managed deferrals, and optionally the unified log.
- `--json` for scripts, `--ea` for a one line Jamf Pro Extension Attribute, `--quick`, `--offline`, `--logs`.
- Skips root only and MDM only checks cleanly and says which ones were skipped.
- Universal (arm64 and x86_64) binary, installer pkg, Homebrew formula, Jamf EA script.
- 19 unit tests on recorded and synthetic fixtures.
