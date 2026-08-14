# Plan — "Year in Review" as a sidebar view ✅ IMPLEMENTED

"Year in Review" is now its own **sidebar destination** (ANALYTICS section, icon
`calendar.badge.sparkles`), using the **Release Calendar's two-pane layout**.

## Navigation
- `SidebarItem.yearReview` added (`Enums.swift`); ContentView routes it without
  touching `NavigationCategory`; CategoryRouterView shows `YearReviewView`.
- Insights card + its loading removed from `InsightsView`.

## `YearReviewView`
```
HStack {
  calendar pane (300pt fixed)   |  Divider  |  detail pane (flex, scrolls)
}
```
- Loads `YearInReviewService.compute(year: currentYear)` on appear.
- **Defaults to current month + today** (today's date ringed).

### Left pane — calendar
- Month chevrons; **tapping the month name → month mode** (collage).
- Day grid: 7-col weekday heatmap, intensity = minutes, day numbers.
- Click a day → day mode. Changing month drops selection to month mode if the
  selected day leaves the month.

### Right pane — contextual
- **Day mode**: "Watched on <date>" + a **2×2 poster grid** (first 4, 2:3 ratio).
  If more → a **"+N more" button to the right**; clicking it swaps to a
  **horizontal scroll** of every title (small cards: poster + name + eps count).
- **Month mode**: the **poster collage** — fixed **4×6 grid** (24 cells),
  **23 posters + a "+more" indicator** in the last cell when exceeded, sorted
  **Loved → Liked → Disliked → rest**. No share.
- **Taste cards** (top genres / networks / actors, no cutoffs, over all 2026
  watching) pinned below a divider.

## Components
- Kept: `YearMonthCollageCard` (reworked to fixed 4×6, no share), `YearTasteCards`.
- Deleted: `YearHeatmapView.swift`, `YearInReviewCard.swift`.

## Acceptance
- Sidebar → Year in Review opens on today with current month + that day's titles.
- Day click → 2×2 + "+N" → horizontal scroll.
- Month name → 4×6 collage (23 + more indicator), taste-sorted, no share.
- Build + `YearInReviewTests` green. ✅
