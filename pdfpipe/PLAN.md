# MVP implementation

- [x] Establish a self-contained iPhone app, share extension, selected icon, and reproducible project-owned commands.
- [x] Implement persisted pipelines, explicit default selection, filename templates, and configured destination access.
- [x] Implement bounded temporary-copy import, PDF/image conversion, searchable on-device OCR, cancellation, and cleanup.
- [x] Implement preview/attributes, pipeline editing, interactive sharing/saving, and unattended execution in the extension.
- [x] Verify source preservation, OCR appearance/text, export failure/collision handling, configuration persistence, and cleanup with automated checks.
- [x] Build both targets and exercise the app/share extension on a simulator; document real-device verification still required.
- [x] Review the final diff and consolidate behavior, limits, commands, and outstanding verification into project documentation.

## Verified outcome (2026-10-11)

The first MVP and four review corrections are implemented. `make verify` passes on the dedicated iOS 27 simulator: 26 unit tests, one end-to-end UI test, then optimized unsigned device Release analysis/build. `make test-release` passes all 26 unit tests on the dedicated iOS 26 simulator. The selected v1 icon is integrated. Real-device acceptance is pending; no signing credentials or team identifiers were invented, and unrelated mobile work remains untouched.

Review corrections:
- App-owned Inbox deliveries move into protected managed sessions immediately; failed/canceled imports and abandoned sessions clean up those copies. Rejected/unclaimed Inbox copies are removed safely without consuming external originals.
- Configured saves stage and flush before exclusive atomic publication; interrupted writes cannot expose a partial final PDF. A forced-termination probe verified this behavior. Unexpected termination can leave a hidden `.partial` file at the destination.
- Long input names remain importable for shortening; output validation runs before OCR.
- The workbench previews the resolved filename and blocks invalid/missing input before Run, using the same preflight logic as execution.

The Makefile now includes Debug/device/Release builds, standalone Release analysis, all/unit/UI/optimized-Release tests, the full integration gate, and cleanup. Release uses whole-module Swift optimization and strict compiler/analyzer diagnostics. A negative Clang analyzer probe verified findings produce errors.

## Remaining physical-device feasibility gate

- [x] Preserve the user's signing team `QQ2W7FVVXM` for both targets in `project.yml` and the generated project.
- [ ] Verify signed installation and shared App Group access on the connected iPhone.
- [ ] Verify import/OCR/export from Files and other host apps on the real iPhone.
- [ ] Verify persisted folder access across app/extension, iCloud and third-party providers, revoked access, and successful/error/canceled saves.
- [ ] Exercise realistic extension memory limits, device locking/termination, and next-launch cleanup. No distribution or background-completion claim before this gate.

Later feature milestones (document-derived renaming and Shortcuts) remain outside the first MVP.
