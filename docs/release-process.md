# Release Process

## Versioning Format

DocNest releases use year-based semantic-ish tags:

- minor release: `YYYY.N`
- patch release: `YYYY.N.P`

Examples:

- `2026.7`
- `2026.6.1`

## Source of Truth

The GitHub release tag is the source of truth for the shipped app version.

Release builds derive:

- `MARKETING_VERSION` from the release tag
- `CURRENT_PROJECT_VERSION` from the workflow run/build number

This means local Xcode project defaults are not the canonical shipped version.

## Standard Release Flow

1. Commit the finished changes.
2. Push the target branch, typically `main`.
3. Create the GitHub release with the intended tag.
4. Let the release build pipeline produce the distributable app artifacts from that tag.

## Minor vs Patch Guidance

Create a new minor release when the change meaningfully expands functionality or marks a visible milestone.

Create a patch release when the change is a follow-up fix or refinement on the current minor line.

## GitHub Releases

The repository uses GitHub releases as the public release record. In normal operation:

- the newest release may be marked as latest
- generated release notes can be used
- artifacts are built from the release tag rather than from an arbitrary local project version

## Local Packaging Helper

Local packaging can be done via:

```sh
scripts/build-dmg.sh
```

Optional environment variables can inject version and build metadata for local packaging:

```sh
RELEASE_VERSION=2026.7 BUILD_NUMBER=42 scripts/build-dmg.sh
```

## Documentation Requirement

Any change to release rules, version semantics, or build metadata handling should update:

- this document
- [README.md](/Users/kaps/Projects/docnest/README.md)
- any scripts or workflow configuration that implement the change
