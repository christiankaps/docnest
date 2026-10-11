# MVP implementation

- [x] Establish a self-contained iPhone app, share extension, selected icon, and reproducible project-owned commands.
- [x] Implement persisted pipelines, explicit default selection, filename templates, and configured destination access.
- [x] Implement bounded temporary-copy import, PDF/image conversion, searchable on-device OCR, cancellation, and cleanup.
- [x] Implement preview/attributes, pipeline editing, interactive sharing/saving, and unattended execution in the extension.
- [x] Verify source preservation, OCR appearance/text, export failure/collision handling, configuration persistence, and cleanup with automated checks.
- [x] Build both targets and exercise the app/share extension on a simulator; document real-device verification still required.
- [x] Review the final diff and consolidate behavior, limits, commands, and outstanding verification into project documentation.

## Verified outcome (2026-10-11)

The first MVP and four review corrections are implemented. `make verify` passes on the dedicated iOS 27 simulator: 27 unit tests, one end-to-end UI test, then optimized unsigned device Release analysis/build. The earlier `make test-release` run passed the then-existing 26 unit tests on the dedicated iOS 26 simulator. The selected v1 icon is integrated. The automated iPhone suite passes; the remaining physical-device acceptance checks are listed below. No signing credentials or team identifiers were invented.

Review corrections:
- App-owned Inbox deliveries move into protected managed sessions immediately; failed/canceled imports and abandoned sessions clean up those copies. Rejected/unclaimed Inbox copies are removed safely without consuming external originals.
- Configured saves stage and flush before exclusive atomic publication; interrupted writes cannot expose a partial final PDF. A forced-termination probe verified this behavior. Unexpected termination can leave a hidden `.partial` file at the destination.
- Long input names remain importable for shortening; output validation runs before OCR.
- The workbench previews the resolved filename and blocks invalid/missing input before Run, using the same preflight logic as execution.

The Makefile now includes Debug/device/Release builds, standalone Release analysis, all/unit/UI/optimized-Release tests, the full integration gate, and cleanup. Release uses whole-module Swift optimization and strict compiler/analyzer diagnostics. A negative Clang analyzer probe verified findings produce errors.

## Physical-iPhone verification (2026-10-11)

On an iPhone 14 Pro running iOS 27.0.1, all 27 unit tests pass, including OCR text/appearance, source preservation, temporary cleanup, and local destination success/failure/cancellation. Signed app installation succeeds with the configured team. Automatic development provisioning was explicitly authorized for this run.

The device exposed a real Inbox restriction: iOS allows consuming deliveries but forbids modifying the Inbox directory itself. Backup exclusion now applies to its app-owned Documents parent, covered by a new device regression test. Inbox fixtures use an injected temporary directory rather than attempting to write into the real system Inbox. A synthetic PDF delivered through the actual Inbox opened with the correct preview/attributes and was removed from Inbox immediately. Relaunching the app reclaimed that abandoned session; the shared Sessions directory contained only its maintenance lock afterward.

The end-to-end UI test also passes on the iPhone: pipeline creation, preview/filename processing, the real system share sheet, extension import with shared configuration, and extension discard without losing the host result. The test now scrolls the installed share-target carousel and the full More/Mehr list. Final app relaunch reclaims the synthetic working session.

`make verify` passes after the device fixes (27 unit tests, one UI test, optimized unsigned device Release analysis/build). The final More-list test adjustment is also checked separately on the simulator. Physical unit tests use local sandbox destinations; they do **not** prove Files-provider bookmarks work across app and extension.

## Remaining physical-device feasibility gate

- [x] Preserve the user's signing team `QQ2W7FVVXM` for both targets in `project.yml` and the generated project.
- [x] Verify signed installation and shared App Group access on the connected iPhone.
- [ ] Verify import/OCR/export from Files and other host apps on the real iPhone.
- [ ] Verify persisted folder access across app/extension, iCloud and third-party providers, revoked access, and successful/error/canceled saves.
- [x] Verify next-launch cleanup of a real abandoned app session.
- [ ] Exercise realistic extension memory limits and locking/termination during processing and provider writes. No distribution or background-completion claim before this gate.

Later feature milestones (document-derived renaming and Shortcuts) remain outside the first MVP.
