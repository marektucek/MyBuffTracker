# MyBuffTracker — Design Spec (v1)

Date: 2026-09-24
Status: Approved for implementation planning

## Problem

WeakAuras is powerful but its configuration UI is overwhelming for a simple
use case: showing a handful of self-buffs as icons with countdown timers.
This project builds a small, purpose-built addon for WoW 3.3.5a (WotLK) that
does just that, with an intuitive in-game config panel instead of
WeakAuras-style nested condition trees.

## Scope

**v1 (this spec):** track a configurable list of buffs on the player
character and display them as icon+bar timers.

**Explicitly out of scope for v1 (future v2):** tracking specified debuffs
on a friendly unit (e.g. the tank). The data model and event handling should
not actively work against this later, but no debuff-tracking code is written
in v1.

## Architecture

Standard WoW 3.3.5a addon: a `.toc` manifest plus Lua files loaded from
`Interface/AddOns/MyBuffTracker/`. No external libraries (no LibStub/Ace3)
— the addon should stay small and readable, since avoiding WeakAuras-style
complexity is the point.

Two logical components:

1. **Tracker engine** — listens for `UNIT_AURA` on `"player"`, matches
   active buffs against the tracked list (by `spellId`), and drives bar
   frame updates (visibility, duration, stack count).
2. **Config panel** — a frame opened via slash command (`/bt`) for adding,
   removing, reordering, and configuring tracked buffs, and for
   unlocking/moving the display anchor.

Persistence via per-character `SavedVariables` (`MyBuffTrackerDB`): tracked
buff list, per-buff options, anchor frame position, and global sort mode
survive `/reload` and logout/login.

## Data model

```lua
MyBuffTrackerDB = {
  anchor = { point = "CENTER", x = 0, y = 0 },
  sortMode = "fixed",      -- "fixed" | "expiration"
  trackedBuffs = {
    {
      spellId = 12345,
      displayName = "Rampage",
      icon = "Interface\\Icons\\...",
      missingBehavior = "hide",  -- "hide" | "dim"
      barColor = nil,             -- optional override, else default/by-type
      order = 1,                   -- stack position when sortMode == "fixed"
    },
    -- ...
  },
}
```

## Spell identification & the add flow

Typing a bare buff name to match against is unreliable for trinket/potion
procs, where names can collide or be non-obvious. The 3.3.5a API returns a
`spellId` as part of `UnitBuff(unit, index, filter)`'s return values, so the
addon uses that as the real tracking key rather than matching on name at
runtime.

Add flow in the config panel:

1. User types a buff name.
2. Addon scans `UnitBuff("player", i)` for i = 1..N looking for a name
   match among currently active buffs.
3. On match: shows the resolved icon, asks for confirmation, and stores
   `{spellId, displayName, icon}`.
4. If no match (buff not currently active on the player right now): an
   "advanced" toggle lets the user enter a spell ID directly instead,
   falling back to a manual lookup (e.g. via Wowhead) outside the addon.

This makes name entry the friendly common path while keeping the actual
tracking unambiguous.

## Config panel features

Per tracked buff, editable in the panel:
- **Missing-state behavior:** `hide` (bar disappears when buff is off) or
  `dim` (bar stays visible, desaturated/grayed, when buff is off).
- **Bar color:** optional per-buff override; otherwise a sensible default.
- **Remove** and **reorder** (drag or up/down controls); order value is
  used as stack position when sort mode is `fixed`.

Global (not per-buff), also in the panel:
- **Sort mode:** `fixed` (order added / manually reordered) or
  `expiration` (bars re-sort live, soonest-expiring on top). Default:
  `fixed`, since it's more predictable.
- **Unlock/lock anchor** to drag-reposition the display frame.

## Display / runtime behavior

- Single movable anchor frame; buff bars stack vertically inside it,
  top-to-bottom, in the order determined by the current sort mode.
- Each bar: icon (left) + horizontal shrinking duration bar + text label
  (name and time remaining) — visually similar to DBM/BigWigs bars.
- Driven by `UNIT_AURA` (event-driven, not polling) for matching/visibility
  changes; a throttled `OnUpdate` ticker (~0.1s) only handles the smooth
  countdown/bar-shrink animation between aura events, not the aura-matching
  logic itself.
- When sort mode is `expiration`, each bar's vertical offset is recomputed
  on update based on current remaining duration.
- Missing buffs are hidden or dimmed per that buff's `missingBehavior`
  setting.

## File layout

```
MyBuffTracker/
  MyBuffTracker.toc   -- ## Interface: 30300, metadata, file list
  Core.lua            -- addon init, SavedVariables setup, slash command
  Tracker.lua         -- UNIT_AURA handling, spell matching, bar updates
  Config.lua          -- settings panel frame + widgets
  Bar.lua             -- bar/icon frame factory (create/update a single bar)
```

## Testing / install plan

No 3.3.5a client is set up in this environment, so there is no automated
test harness — WoW 3.3.5a Lua can't realistically be unit-tested outside
the client. The addon is built carefully against the documented 3.3.5a
WotLK API surface (`UnitBuff`, `UNIT_AURA`, frame/template APIs current as
of patch 3.3.5).

Manual verification (once the user copies/symlinks the folder into their
`Interface/AddOns/` and reloads):
1. Add a real active buff by name via `/bt`; confirm it resolves and a bar
   appears.
2. Confirm the bar's timer counts down accurately and the bar disappears
   (or dims, per setting) when the buff expires.
3. Add a second buff; confirm both sort modes (`fixed`, `expiration`)
   order the stack as expected.
4. Unlock and drag the anchor; `/reload` and confirm position persisted.
5. Confirm `missingBehavior` (`hide` vs `dim`) behaves as configured for a
   buff that isn't currently active.

## Open items deferred to v2

- Tracking specified debuffs on a friendly unit (e.g. tank).
- Any UI polish beyond the above (fonts, skins, LibSharedMedia, etc.).
