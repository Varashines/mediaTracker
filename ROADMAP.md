# MediaTracker — Roadmap

What's done, what's next. GitHub plumbing is largely complete; the focus now is
product features.

## Done

### CI & process
- [x] `ci.yml` — `swift build` + `swift test` on push/PR (`.build` cached).
      Build is the hard gate. Test step stays `continue-on-error`: the known
      SwiftData in-memory teardown race crashes full-suite runs (all assertions
      pass; Swift issue, not ours — not actionable right now).
- [x] **Branch protection on `main`** — requires `build-and-test`, linear history.
- [x] **CodeQL** (weekly + PRs) + **secret scanning** (public repo, default on).
- [x] PR template, `CONTRIBUTING.md`, labels (`enhancement`, `bug`, `perf`,
      `concurrency`, `tech-debt`), milestones (`8.1.1`, `8.2.0`, `9.0.0`).
- [x] Auto-merge — **not enabled**: repo setting `enablePullRequestAutoMerge`
      is off; we merge manually after CI passes. (Optional to flip on.)

### Release
- [x] `release.yml` (v-tags → both-arch DMGs + GitHub release, auto notes) and
      `build-only.yml` (manual DMG artifacts).
- [x] ~~Notarization~~ **Dropped** — free Personal Team rejected (HTTP 403);
      requires paid membership. DMGs stay ad-hoc signed.

### Tech debt (audit)
- [x] `#8` locks standardized on `OSAllocatedUnfairLock`; `#6` single
      `modelContainer`; `#1` 2000-item scan cap.
- [x] `#7` API keys — **reverted to `UserDefaults`** (the Keychain read failed in
      dev builds); `KeychainStore` is now a one-time migrate-back helper.

### Features shipped
- [x] **Year in Review** sidebar view: month heatmap, day/month overview,
      series-first stats, discovery-style taste cards (genres affinity, networks
      with logos, ranked actors, languages).
- [x] **MediaTracker MCP server** (`Tools/MediaTrackerMCP`) — read-only library
      search + insights over the SwiftData store.

## Next — v9 "Arc"

- [ ] **Weekly digest notification** — see `PLAN-WeeklyDigest.md`.
- [ ] **v9.0.0 release** — tag `v9.0.0`, codename **"Arc"** in About screen,
      auto release notes from the PRs since `v8.1.1`.
- [ ] (Optional) **Wrapped share card** — exportable Year-in-Review image.

## Explicitly NOT doing (for now)

- **iCloud / CloudKit sync** — too big, no.
- **Widgets** — no.
- **Streak stat** — no.
- **Swift test hard gate** — blocked by the SwiftData teardown crash; can't fix
  without upstream changes.

## Deferred / optional

- Discussions, Homebrew cask, GitHub Pages docs, Developer ID cert (paid).
- Dependabot — nothing to watch (zero external packages).
