# Release Process

## Versioning Format

DocNest releases use the version schema:

- release version: `YYYY.MAJOR.MINOR`

Examples:

- `2026.6.1`
- `2026.7.2`

## Source of Truth

The GitHub release tag is the source of truth for the shipped app version.

Release builds derive:

- `MARKETING_VERSION` from the release tag
- `CURRENT_PROJECT_VERSION` from the workflow run/build number

This means local Xcode project defaults are not the canonical shipped version.

## Standard Release Flow

1. Commit the finished changes.
2. Push the target branch `master`.
3. Create the GitHub release with the intended tag.
4. Let the release build pipeline produce the distributable app artifacts from that tag.

## Release Selection Guidance

- Before choosing the next version, check GitHub for the latest published release.
- Use the latest published release as the only base line for the next release tag.
- By default, create a new minor release by incrementing the `MINOR` component.
- Only increment the `MAJOR` component when the release plan explicitly calls for a larger version step.
- When the release year changes, start the new year's line at `YYYY.1.0` unless the release plan explicitly defines a different starting point.
- Older major lines and older year lines are not maintained separately.

This means DocNest always moves forward on one active release line rather than shipping fixes on multiple historical branches.

## GitHub Releases

The repository uses GitHub releases as the public release record. In normal operation:

- GitHub is the source to inspect for the current latest release before creating the next one
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
