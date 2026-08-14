# MediaTracker — GitHub Enhancement Roadmap

Phase-gated plan for getting more out of GitHub on this repo. Each phase is
self-contained and shippable in one sitting.

---

## Phase 1 — CI gates (biggest win, do first)

Currently nothing verifies code before merge. Goal: main is protected and every
PR is "green or blocked".

- [x] **Add `ci.yml`** — `swift build` + `swift test` on every `push`/`pull_request`
      with `.build` caching. Build is the hard gate; the test step is
      `continue-on-error` because of the known SwiftData teardown race (all
      assertions pass; see `AGENTS.md`).
- [ ] **Branch protection on `main`** — not applied yet (repo setting). See
      `gh api` commands below.
- [ ] **Auto-merge** for PRs that pass checks (`gh pr merge --auto`).

### Branch protection (run once)

```bash
gh api -X PUT repos/Varashines/mediaTracker/branches/main/protection \
  -f required_status_checks='[{"context":"build-and-test"}]' \
  -f enforce_admins=false \
  -f required_pull_request_reviews=null \
  -f restrictions=null \
  -f required_linear_history=true
```

## Phase 2 — Release polish

- [x] ~~Notarization~~ **Dropped** — Apple's notary service rejects free Personal
      Teams (HTTP 403); requires a paid Developer Program membership. DMGs stay
      ad-hoc signed; users right-click → Open. Revisit only if you join the
      program.
- [x] **Milestones** — `8.1.1`, `8.2.0`, `9.0.0` created. Tag PRs to a milestone so
      the release has a scope; `release.yml` already uses
      `generate_release_notes: true`.
- [ ] **Version bump consistency** — `release.yml` derives the version from the
      tag (`${GITHUB_REF_NAME#v}`); make milestone names match tags.

## Phase 3 — Security & repo hygiene

- [x] **CodeQL workflow** — `.github/workflows/codeql.yml` added (weekly + PRs).
      Repo is public so Advanced Security is free; just **enable** code scanning
      in Settings → Code security → Code scanning.
- [x] **Secret scanning** — enabled by default (public repo); verify in
      Settings → Code security & analysis.
- [x] **PR template + `CONTRIBUTING.md`** — added `.github/pull_request_template.md`
      and `CONTRIBUTING.md`.
- [x] **Labels** — `enhancement`, `bug`, `perf`, `concurrency`, `tech-debt`
      created.
- [x] **Audit follow-ups (tech debt):**
      - `#7` API keys moved from `UserDefaults` to the **Keychain**
        (`KeychainStore`, migrated at launch).
      - `#8` Lock primitives standardized on `OSAllocatedUnfairLock`
        (`BadgeEngine`, `DateUtils`).
      - `#6` Collapsed the duplicate `modelContainer` storage in `DataService`
        (single `@MainActor` static).
      - `#1` Capped the in-memory filter scan at 2000 items (matches
        `ARCHITECTURE.md`).

## Phase 4 — Community / scale (optional)

- [ ] **Discussions** — if you want a place for feature requests/feedback.
- [ ] **Homebrew cask** — alternative distribution once there's an audience.
- [ ] **Developer ID cert** — if you ever pay for the program, swap ad-hoc
      signing for a Developer ID certificate and get clean Gatekeeper launches.
- [ ] **GitHub Pages docs** — only if there's content worth documenting.

---

## Deferred / not planned

- Audit `#9` (thermal abort drops in-flight tasks) — correct as-is; add a
  clarifying comment if touched.
- Dependabot — nothing to watch (zero external packages).
