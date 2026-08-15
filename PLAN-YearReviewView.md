# Plan — Year in Review taste section: Discovery-Hub-style cards

Make Top Genres / Networks / Actors behave like `DiscoveryCard` (logo + text
styles) exactly: name/logo always visible, affinity/count revealed on hover,
same hover scale/shadow. Also fix poster hover clipping in the month "+N more"
scroll.

Reference behavior — `DiscoveryCard.swift`:
- **Logo style**: card tinted with theme color; logo on a white tile visible;
  on hover the logo fades and the **name** shows; a **count badge** appears
  top-trailing. Hover = `scaleEffect(1.02)` + `shadow(color: themeColor.opacity(0.12), radius: 8, y: 4)` + `springSnappy`.
- **Text style**: no icon; name always centered; **count badge on hover**.
- `compositingGroupIfNeeded()` to avoid ghosting during hover.

---

## 1. Top Genres — text-style, affinity on hover only
- **Remove the tag icon.** Card = rounded rect filled with the genre's theme
  color (`AppTheme.Colors.genreColor(for: name, default: accent)`), name centered.
- **Affinity % hidden by default**; on hover a badge appears (top-trailing or
  below the name) like Discovery's count badge.
- Hover: `scaleEffect(1.02)` + tinted shadow + `springSnappy`.
- Size: text-style card (~60pt tall, ~120pt wide), name `lineLimit(1)`.

## 2. Networks — logo-style, name + count on hover
- **Logo on a white tile** (already added) on a card; theme color fill from the
  logo's brand tint (fallback: `cardFill`).
- **On hover: logo fades out → network name shows**; **count badge** appears
  top-trailing — exactly `DiscoveryCard.logoContent`.
- Hover: same scale 1.02 + shadow.
- Size: logo-style (~90pt tall, ~110pt wide) so the logo tile breathes.

## 3. Actors — keep Hall-of-Fame rank card, add Discovery hover
- Keep the giant-outlined rank + avatar/name card as-is.
- Add hover: `scaleEffect(1.02)` + shadow + `springSnappy` (currently none).
- Wrap in `compositingGroupIfNeeded()` to prevent the overlapping rank number
  from ghosting during scale.

## 4. Fix poster hover cropping in "+N more" scrolls
- Problem: in month (and day) `ScrollView(.horizontal)` after "+N more",
  `PosterTile` scales 1.25 on hover and gets **clipped by the ScrollView** top/bottom.
- Fix:
  - Add vertical content padding so the scaled poster fits: HStack inside the
    scroll gets `.padding(.vertical, 8)`.
  - Bump the scroll's `.frame(height:)` to match: month `42 → 58`, day `84 → 100`.
  - (Scale stays 1.25; shadow no longer clipped either.)

## Deliverables
- `YearReviewView.swift`: rework `genreCard`, `networkCard`, `actorRankCard` with
  hover states (isHovered + scale/shadow + compositingGroupIfNeeded), genre
  affinity-on-hover, network name+count-on-hover; scroll-content padding for the
  two "+N more" scrolls.
- No service/model changes (affinity + counts already present).

## Acceptance
- Genres: bare genre name; % shows on hover (no tag icon).
- Networks: logo only; hover shows name + count badge.
- Actors: ranked card + hover scale/shadow.
- Month/day "+N more" scrolls: posters scale on hover without clipping.
- Build + `YearInReviewTests` green.
