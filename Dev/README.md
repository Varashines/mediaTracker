# MediaTracker Dev

`MediaTracker Dev` is an isolated app identity and SwiftData store for testing
schema changes against a copy of a real library. It must never use or modify the
production store.

## What is isolated

- Bundle identifier: `com.vara.mediatracker.dev`
- App name: `MediaTracker Dev`
- Dev SwiftData store: `~/Library/Application Support/MediaTracker Dev/default.store`
- Store migration failures: stop immediately and preserve the Dev store rather
  than invoking production recovery/reset behavior.

The XcodeGen target is defined as `MediaTrackerDev` in `project.yml`. The
SwiftPM executable is also packaged as the separate Dev app by
`./Dev/install-dev.sh`.

## Create a Dev snapshot

1. Quit **MediaTracker** completely.
2. Locate its `default.store` file.
3. Copy it with the helper:

   ```bash
   ./Dev/copy-production-store.sh \
     --source /absolute/path/to/default.store \
     --confirm-production-closed
   ```

   Add `--force` only when deliberately replacing the existing Dev snapshot.

The helper copies `default.store` and, when present, its `-wal` and `-shm`
sidecars together. Do not copy a store while production MediaTracker is open.

## Build and install Dev

```bash
./Dev/install-dev.sh
open -a "MediaTracker Dev"
```

Use `./Dev/install-dev.sh --release` for an optimized local Dev build.

## Migration test workflow

1. Keep a baseline snapshot under `Dev/Fixtures/` locally; it is ignored by Git.
2. Install and launch the current Dev build to prove the snapshot opens.
3. Implement the schema change.
4. Rebuild Dev and launch it against the same snapshot.
5. Verify item, episode, collection, and watch-history counts; then verify
   genre, provider, network, and smart-collection filters.
6. If opening or migration fails, inspect the preserved Dev store and console
   error. Do not test the change against production.

## Cleanup

To reset Dev data, quit MediaTracker Dev and remove:

```bash
rm -f "$HOME/Library/Application Support/MediaTracker Dev/default.store"*
```

## Code signing

Local installs (`install.sh`) and both CI DMGs must be signed by the same
certificate. A Keychain ACL records the certificate's leaf hash, so a
regenerated identity keeps its display name but becomes a different app to the
Keychain — every stored credential then asks for approval.

- Create the identity once: `./Dev/setup-signing.sh`
- Push it to CI and record the expected hash:

  ```bash
  ./Dev/export-signing-identity.sh
  ```

  This overwrites `CERT_P12_BASE64` / `CERT_PASSWORD` and sets the
  `SIGNING_CERT_SHA1` repository variable. `build-only.yml` and `release.yml`
  compare the imported certificate against that variable and fail on drift,
  instead of publishing a DMG that no longer matches existing installs.

Re-run the export after creating a new identity (new Mac, deleted keychain
entry, re-run of `setup-signing.sh`). If `SIGNING_CERT_SHA1` is unset the
workflows warn and continue — intended for forks that do not use the shared
certificate.
