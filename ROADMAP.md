# MediaTracker — GitHub Enhancement Roadmap

Phase-gated plan for getting more out of GitHub on this repo. Each phase is
self-contained and shippable in one sitting.

---

## Phase 1 — CI gates (biggest win, do first)

Currently nothing verifies code before merge. Goal: main is protected and every
PR is "green or blocked".

- [ ] **Add `ci.yml`** — run `swift build` + `swift test` on `push` (main) and every
      `pull_request`. Cache `.build`.
- [ ] **Get CI green** — the full-suite run currently crashes on the known
      SwiftData in-memory teardown race (documented in `AGENTS.md`). Either fix
      it or run a curated test list that excludes the racy container teardown
      test, with a comment explaining why.
- [ ] **Branch protection on `main`** via:
      `gh api repos/{owner}/{repo}/branches/main/protection` — require
      `ci.yml` as a required check, linear history, dismiss stale reviews.
- [ ] **Auto-merge** for PRs that pass checks (`gh pr merge --auto`).

## Phase 2 — Release polish

- [x] ~~Notarization~~ **Dropped** — Apple's notary service rejects free Personal
      Teams (HTTP 403); requires a paid Developer Program membership. DMGs stay
      ad-hoc signed; users right-click → Open. Revisit only if you join the
      program (add `APPLE_APP_ID` / `APPLE_APP_PASSWORD` / `APPLE_TEAM_ID`
      secrets and re-add the `notarytool` step).
- [ ] **Milestones** — create a milestone per release version (`8.1.1`, …); tag
      PRs to it so the release has a scope. `release.yml` already uses
      `generate_release_notes: true`.
- [ ] **Version bump consistency** — `release.yml` derives the version from the
      tag (`${GITHUB_REF_NAME#v}`); make milestone names match tags.

## Phase 3 — Security & repo hygiene

- [ ] **CodeQL (Swift)** — enable code scanning in Settings → Code security →
      Code scanning → configure CodeQL (Swift build support on macOS runners).
- [ ] **Secret scanning** — enable for the repo (free); relevant to the audit
      finding about plaintext TMDB/OMDB/MooreMetrics API keys.
- [ ] **PR template + `CONTRIBUTING.md` + labels** (`enhancement`, `bug`,
      `perf`, `concurrency`, `tech-debt`). Feeds release notes in Phase 2.
- [ ] **Audit follow-ups (tech debt):**
      - `#7` Move user-supplied API keys from `UserDefaults` to Keychain.
      - `#8` Standardize lock primitives on `OSAllocatedUnfairLock`.
      - `#6` Collapse the duplicate `modelContainer` storage in `DataService`.

## Phase 4 — Community / scale (optional)

- [ ] **Discussions** — if you want a place for feature requests/feedback.
- [ ] **Homebrew cask** — alternative distribution once there's an audience.
- [ ] **Developer ID cert** — if you ever pay for the program, swap ad-hoc
      signing for a Developer ID certificate and get clean Gatekeeper launches.
- [ ] **GitHub Pages docs** — only if there's content worth documenting.

---

## Deferred / not planned

- Audit `#1` (unbounded in-memory fetch) — revisit only if library grows large;
  common search is already SQLite-filtered.
- Audit `#9` (thermal abort drops in-flight tasks) — correct as-is; add a
  clarifying comment if touched.
- Dependabot — nothing to watch (zero external packages).
