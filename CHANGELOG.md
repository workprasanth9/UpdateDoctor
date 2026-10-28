# Changelog

## 1.0.0 (2026-10-28)

First release.

- `updatedoctor doctor` runs 13 read only checks and prints a verdict (HEALTHY, AT_RISK or BLOCKED) with a reason and a fix for each problem.
- Compares the installed macOS with Apple's GDMF feed for this exact device (target-type or board-id).
- Checks offered updates, free APFS container space, power, Apple update host reachability, MDM enrollment, Bootstrap Token escrow (root), FileVault, DDM persisted software update errors, scan history and CatalogURL, automatic update settings, managed deferrals, and optionally the unified log.
- `--json` for scripts, `--ea` for a one line Jamf Pro Extension Attribute, `--quick`, `--offline`, `--logs`.
- Skips root only and MDM only checks cleanly and says which ones were skipped.
- Universal (arm64 and x86_64) binary, installer pkg, Homebrew formula, Jamf EA script.
- 19 unit tests on recorded and synthetic fixtures.
