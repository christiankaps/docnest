# MVP implementation

- [x] Establish a self-contained iPhone app, share extension, selected icon, and reproducible project-owned commands.
- [x] Implement persisted pipelines, explicit default selection, filename templates, and configured destination access.
- [x] Implement bounded temporary-copy import, PDF/image conversion, searchable on-device OCR, cancellation, and cleanup.
- [x] Implement preview/attributes, pipeline editing, interactive sharing/saving, and unattended execution in the extension.
- [x] Verify source preservation, OCR appearance/text, export failure/collision handling, configuration persistence, and cleanup with automated checks.
- [x] Build both targets and exercise the app/share extension on a simulator; document real-device verification still required.
- [x] Review the final diff and consolidate behavior, limits, commands, and outstanding verification into project documentation.

## Verified outcome (2026-10-11)

The first MVP is implemented. `make verify` passes on dedicated iOS 26.0 and 27.0 simulators (20 unit tests and one end-to-end UI test). The final reviewed code passes the iOS 27 gate and device-SDK compilation with `make build-device`. The selected v1 icon is integrated. Real-device acceptance is pending; no signing credentials or team identifiers were invented, and unrelated mobile work remains untouched.

## Remaining physical-device feasibility gate

- [ ] Configure the user's signing team and shared App Group for both targets. A connected iPhone is available, but the team information is still pending.
- [ ] Verify import/OCR/export from Files and other host apps on the real iPhone.
- [ ] Verify persisted folder access across app/extension, iCloud and third-party providers, revoked access, and successful/error/canceled saves.
- [ ] Exercise realistic extension memory limits, device locking/termination, and next-launch cleanup. No distribution or background-completion claim before this gate.

Later feature milestones (document-derived renaming and Shortcuts) remain outside the first MVP.
