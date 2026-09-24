# MyBuffTracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build MyBuffTracker, a small WoW 3.3.5a addon that tracks a
configurable list of self-buffs on the player and displays them as
icon+bar countdown timers, with an in-game config panel for managing the
list (add by name with spell-ID resolution, remove, reorder, per-buff
missing-behavior and color, global sort mode, and a movable display
anchor).

**Architecture:** Two runtime components sharing one `MyBuffTracker`
(`MBT`) global namespace table: a Tracker engine (`Tracker.lua` +
`Bar.lua`) driven by the `UNIT_AURA` event plus a throttled `OnUpdate`
ticker for smooth countdowns, and a Config panel (`Config.lua`) opened via
`/bt` for editing the tracked-buff list. `Core.lua` owns `SavedVariables`
(`MyBuffTrackerDB`) init/defaults and the small set of pure functions that
mutate the tracked-buff list; both the Tracker and Config UI call into
those functions rather than mutating the saved table directly.

**Tech Stack:** WoW 3.3.5a (WotLK) Lua 5.1 addon API. No external
libraries (no LibStub/Ace3). `.toc` + 4 `.lua` files.

**Spec:** `docs/superpowers/specs/2026-09-24-buff-tracker-design.md`

## Global Constraints

- `## Interface: 30300` (WoW client patch 3.3.5a).
- No external libraries — no LibStub, no Ace3, no embedded libs of any
  kind. Keep the addon small and readable; this is the whole point per
  the spec's Problem statement.
- Persistence is per-character `SavedVariables` under the global table
  name `MyBuffTrackerDB`, matching the data model in the spec exactly
  (`anchor`, `sortMode`, `trackedBuffs[]` with `spellId`, `displayName`,
  `icon`, `missingBehavior`, `barColor`, `order`).
- Tracking key is `spellId`, never buff name, per the spec's "Spell
  identification" section.
- v1 tracks **player buffs only** (`UNIT_AURA` on `"player"`,
  `UnitBuff("player", ...)`). Do not add debuff or friendly-unit-target
  code paths — that's explicitly deferred to v2. Keep data flowing through
  functions that take a `unit` or an injected fetch function as a
  parameter (not hardcoded WoW-global calls) so v2 can extend without a
  rewrite, per the spec's architecture note — but do not build any v2
  behavior now.
- Aura matching/visibility is event-driven (`UNIT_AURA`); the ~0.1s
  `OnUpdate` ticker only re-renders countdown/bar-shrink, it never
  re-matches auras independently of an event (matching happens in
  `RefreshDisplay`, which both the event handler and the ticker call —
  there's one matching code path, invoked from two triggers).
- File layout is fixed by the spec:
  `MyBuffTracker/{MyBuffTracker.toc,Core.lua,Tracker.lua,Config.lua,Bar.lua}`.
  `.toc` load order is **Core.lua, Bar.lua, Tracker.lua, Config.lua** —
  this differs from the spec's prose listing order but is required
  because Tracker.lua calls functions defined in Bar.lua, and Config.lua
  calls functions defined in Core.lua and Tracker.lua. All cross-file
  calls happen inside event-time functions (never at file top-level
  execution time other than frame/handler *registration*), so this is the
  only ordering constraint that matters.

## Development Tooling Note (not shipped)

No WoW 3.3.5a client exists in this environment, so nothing that calls the
WoW API (`CreateFrame`, `UnitBuff`, events, etc.) can be executed or
automatically verified here — this matches the spec's own Testing/install
plan, which defers all of that to manual in-game verification (Task 12).

However, several pieces of this addon's logic are pure data
transformations with no WoW API dependency (matching auras against the
tracked list, computing sort/display order, resolving a typed buff name,
CRUD on the tracked-buff list). Those are written as standalone functions
that take plain Lua tables/values (and, where they'd otherwise call a WoW
API function like `UnitBuff`, take that function as a parameter instead)
so they can be genuinely unit-tested with a plain Lua interpreter during
development.

A system Lua (`lua 5.5.1`, installed via `brew install lua`) is used
**only** for this: throwaway `assert()`-based scripts run from your
scratchpad directory during the tasks below, deleted afterward. This adds
zero runtime dependency to the shipped addon — the `.toc` never
references it, and no `.lua` file in `MyBuffTracker/` requires anything
beyond the WoW 3.3.5a Lua 5.1 API surface. If `lua` isn't on `PATH` when
you reach Task 2, install it with `brew install lua` first.

---

## Task 1: Project scaffolding

**Files:**
- Create: `MyBuffTracker/MyBuffTracker.toc`
- Create: `MyBuffTracker/Core.lua`
- Create: `MyBuffTracker/Bar.lua`
- Create: `MyBuffTracker/Tracker.lua`
- Create: `MyBuffTracker/Config.lua`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: the global table `MyBuffTracker` (aliased `local MBT` inside
  each file), created once in `Core.lua` and reused (never re-created,
  only `... or {}` guarded) in the other three files. Every later task
  hangs functions off this same table.

- [ ] **Step 1: Create the addon folder and `.toc` manifest**

`MyBuffTracker/MyBuffTracker.toc`:

```
## Interface: 30300
## Title: MyBuffTracker
## Notes: Lightweight self-buff icon+bar tracker with a simple config panel.
## Author: Marek Tucek
## Version: 1.0
## SavedVariables: MyBuffTrackerDB

Core.lua
Bar.lua
Tracker.lua
Config.lua
```

- [ ] **Step 2: Create the four stub Lua files, each establishing the shared namespace**

`MyBuffTracker/Core.lua`:

```lua
MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker
```

`MyBuffTracker/Bar.lua`:

```lua
MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker
```

`MyBuffTracker/Tracker.lua`:

```lua
MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker
```

`MyBuffTracker/Config.lua`:

```lua
MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker
```

- [ ] **Step 3: Verify the folder structure**

Run: `find "MyBuffTracker" -type f`
Expected output (order may vary):
```
MyBuffTracker/MyBuffTracker.toc
MyBuffTracker/Core.lua
MyBuffTracker/Bar.lua
MyBuffTracker/Tracker.lua
MyBuffTracker/Config.lua
```

- [ ] **Step 4: Commit**

```bash
git add MyBuffTracker/MyBuffTracker.toc MyBuffTracker/Core.lua MyBuffTracker/Bar.lua MyBuffTracker/Tracker.lua MyBuffTracker/Config.lua
git commit -m "chore: scaffold MyBuffTracker addon structure"
```

---

## Task 2: Core.lua — SavedVariables defaults & tracked-buff CRUD (pure functions)

**Files:**
- Modify: `MyBuffTracker/Core.lua`
- Test: throwaway scratch script (not committed), see steps below.

**Interfaces:**
- Consumes: nothing WoW-specific — operates on a plain `db` table shaped
  like `MyBuffTrackerDB` from the spec's data model.
- Produces (all attached to `MBT`, called by later tasks):
  - `MBT.ApplyDefaults(db) -> db` — fills in missing top-level fields,
    used once at `ADDON_LOADED`.
  - `MBT.AddTrackedBuff(db, spellId, displayName, icon) -> buffEntry` —
    appends a new tracked buff with `missingBehavior = "hide"`,
    `barColor = nil`, `order` set to the new last position.
  - `MBT.RemoveTrackedBuff(db, spellId)` — removes by spellId,
    renumbers remaining `order` fields to stay contiguous `1..N`.
  - `MBT.MoveTrackedBuff(db, spellId, direction)` — `direction` is `-1`
    (up) or `1` (down); swaps with the neighbor and renumbers; no-op at
    the ends of the list.
  - `MBT.SetMissingBehavior(db, spellId, behavior)` — `behavior` is
    `"hide"` or `"dim"`.
  - `MBT.SetBarColor(db, spellId, r, g, b)` — pass `r = nil` to clear
    the override back to the default.
  - `MBT.SetSortMode(db, sortMode)` — `sortMode` is `"fixed"` or
    `"expiration"`.
  - `MBT.SetAnchorPosition(db, point, x, y)`.

- [ ] **Step 1: Write the failing scratch test**

Create `selfcheck-core.lua` in your scratchpad directory:

```lua
dofile("MyBuffTracker/Core.lua")
local MBT = MyBuffTracker

-- ApplyDefaults fills a nil/empty db
local db = MBT.ApplyDefaults(nil)
assert(db.sortMode == "fixed", "default sortMode should be fixed")
assert(db.anchor.point == "CENTER", "default anchor point should be CENTER")
assert(db.anchor.x == 0 and db.anchor.y == 0, "default anchor offset should be 0,0")
assert(type(db.trackedBuffs) == "table" and #db.trackedBuffs == 0, "trackedBuffs should start empty")

-- ApplyDefaults preserves existing values, only fills gaps
local existing = { sortMode = "expiration" }
local db2 = MBT.ApplyDefaults(existing)
assert(db2.sortMode == "expiration", "ApplyDefaults must not overwrite existing sortMode")

-- AddTrackedBuff appends with correct defaults and order
local a = MBT.AddTrackedBuff(db, 111, "Rampage", "Interface\\Icons\\Ability_Racial_Avatar")
assert(a.spellId == 111 and a.displayName == "Rampage")
assert(a.missingBehavior == "hide" and a.barColor == nil and a.order == 1)
local b = MBT.AddTrackedBuff(db, 222, "Battle Shout", "Interface\\Icons\\Ability_Warrior_BattleShout")
assert(b.order == 2)
assert(#db.trackedBuffs == 2)

-- MoveTrackedBuff swaps and renumbers, no-ops at boundaries
MBT.MoveTrackedBuff(db, 222, -1)
assert(db.trackedBuffs[1].spellId == 222 and db.trackedBuffs[1].order == 1)
assert(db.trackedBuffs[2].spellId == 111 and db.trackedBuffs[2].order == 2)
MBT.MoveTrackedBuff(db, 222, -1) -- already first, no-op
assert(db.trackedBuffs[1].spellId == 222)
MBT.MoveTrackedBuff(db, 111, 1) -- already last, no-op
assert(db.trackedBuffs[2].spellId == 111)

-- SetMissingBehavior / SetBarColor
MBT.SetMissingBehavior(db, 111, "dim")
assert(db.trackedBuffs[2].missingBehavior == "dim")
MBT.SetBarColor(db, 111, 1, 0, 0)
assert(db.trackedBuffs[2].barColor.r == 1 and db.trackedBuffs[2].barColor.g == 0)
MBT.SetBarColor(db, 111, nil)
assert(db.trackedBuffs[2].barColor == nil)

-- RemoveTrackedBuff removes and renumbers
local c = MBT.AddTrackedBuff(db, 333, "Berserker Rage", "Interface\\Icons\\Ability_Racial_Avatar")
assert(c.order == 3)
MBT.RemoveTrackedBuff(db, 222) -- was order 1
assert(#db.trackedBuffs == 2)
assert(db.trackedBuffs[1].spellId == 111 and db.trackedBuffs[1].order == 1)
assert(db.trackedBuffs[2].spellId == 333 and db.trackedBuffs[2].order == 2)

-- SetSortMode / SetAnchorPosition
MBT.SetSortMode(db, "expiration")
assert(db.sortMode == "expiration")
MBT.SetAnchorPosition(db, "TOPLEFT", 12, -34)
assert(db.anchor.point == "TOPLEFT" and db.anchor.x == 12 and db.anchor.y == -34)

print("Core.lua selfcheck: ALL PASS")
```

Run it from the repo root: `lua /path/to/scratchpad/selfcheck-core.lua`
Expected: FAIL — every `MBT.*` function is `nil` (only the namespace
table exists so far), e.g. `attempt to call a nil value (field
'ApplyDefaults')`.

- [ ] **Step 2: Implement the functions in `Core.lua`**

Append to `MyBuffTracker/Core.lua` (after the two namespace lines):

```lua
function MBT.ApplyDefaults(db)
  db = db or {}
  db.anchor = db.anchor or { point = "CENTER", x = 0, y = 0 }
  db.sortMode = db.sortMode or "fixed"
  db.trackedBuffs = db.trackedBuffs or {}
  return db
end

function MBT.AddTrackedBuff(db, spellId, displayName, icon)
  local order = #db.trackedBuffs + 1
  table.insert(db.trackedBuffs, {
    spellId = spellId,
    displayName = displayName,
    icon = icon,
    missingBehavior = "hide",
    barColor = nil,
    order = order,
  })
  return db.trackedBuffs[#db.trackedBuffs]
end

local function renumber(trackedBuffs)
  for i, buff in ipairs(trackedBuffs) do
    buff.order = i
  end
end

function MBT.RemoveTrackedBuff(db, spellId)
  for i, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      table.remove(db.trackedBuffs, i)
      break
    end
  end
  renumber(db.trackedBuffs)
end

function MBT.MoveTrackedBuff(db, spellId, direction)
  local buffs = db.trackedBuffs
  local index
  for i, buff in ipairs(buffs) do
    if buff.spellId == spellId then
      index = i
      break
    end
  end
  if not index then return end
  local targetIndex = index + direction
  if targetIndex < 1 or targetIndex > #buffs then return end
  buffs[index], buffs[targetIndex] = buffs[targetIndex], buffs[index]
  renumber(buffs)
end

function MBT.SetMissingBehavior(db, spellId, behavior)
  for _, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      buff.missingBehavior = behavior
      break
    end
  end
end

function MBT.SetBarColor(db, spellId, r, g, b)
  for _, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      buff.barColor = r and { r = r, g = g, b = b } or nil
      break
    end
  end
end

function MBT.SetSortMode(db, sortMode)
  db.sortMode = sortMode
end

function MBT.SetAnchorPosition(db, point, x, y)
  db.anchor.point = point
  db.anchor.x = x
  db.anchor.y = y
end
```

- [ ] **Step 3: Run the scratch test again and verify it passes**

Run: `lua /path/to/scratchpad/selfcheck-core.lua`
Expected: `Core.lua selfcheck: ALL PASS`

- [ ] **Step 4: Delete the scratch script (not part of the addon)**

- [ ] **Step 5: Commit**

```bash
git add MyBuffTracker/Core.lua
git commit -m "feat: add SavedVariables defaults and tracked-buff CRUD helpers"
```

---

## Task 3: Core.lua — ADDON_LOADED wiring & slash command

**Files:**
- Modify: `MyBuffTracker/Core.lua`

**Interfaces:**
- Consumes: `MBT.ApplyDefaults` (Task 2).
- Produces:
  - `MBT.db` — the live `MyBuffTrackerDB` table, set once defaults are
    applied; every other file reads/mutates tracked state through this.
  - Calls `MBT.InitTracker()` and `MBT.InitConfig()` if they exist (they
    don't yet — defined in Tasks 7 and 11 respectively). This is a
    runtime check (`if MBT.InitTracker then`), not a load-order
    dependency: by the time `ADDON_LOADED` fires, all four files have
    already executed top-to-bottom, so both functions exist by then
    regardless of which task originally defined them.
  - Registers `/bt` calling `MBT.ToggleConfig()` if it exists (defined
    in Task 11).

No automated test is possible for this step — it's pure WoW event/API
glue with no WoW client available here. Write it carefully against the
documented API and self-review against the checklist below; it gets its
real verification in Task 12's manual checklist (item 1, "Add a real
active buff by name via `/bt`" implicitly requires this step to work).

- [ ] **Step 1: Add the ADDON_LOADED handler and slash command registration**

Append to `MyBuffTracker/Core.lua`:

```lua
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
  if event == "ADDON_LOADED" and addonName == "MyBuffTracker" then
    MyBuffTrackerDB = MBT.ApplyDefaults(MyBuffTrackerDB)
    MBT.db = MyBuffTrackerDB

    if MBT.InitTracker then
      MBT.InitTracker()
    end
    if MBT.InitConfig then
      MBT.InitConfig()
    end

    self:UnregisterEvent("ADDON_LOADED")
  end
end)

SLASH_MYBUFFTRACKER1 = "/bt"
SlashCmdList["MYBUFFTRACKER"] = function()
  if MBT.ToggleConfig then
    MBT.ToggleConfig()
  end
end
```

- [ ] **Step 2: Self-review checklist**

- [ ] `ADDON_LOADED` is registered before any code assumes `MBT.db`
  exists (it is — this is the only place `MBT.db` is ever assigned).
- [ ] The `addonName == "MyBuffTracker"` check matches the `.toc`
  filename exactly (`MyBuffTracker.toc` → addon name `MyBuffTracker`).
- [ ] `SLASH_MYBUFFTRACKER1` and the `SlashCmdList` key
  (`"MYBUFFTRACKER"`) match — WoW requires the `SLASH_<KEY>1` global name
  and the `SlashCmdList[<KEY>]` string to use the identical key.
- [ ] `self:UnregisterEvent("ADDON_LOADED")` prevents the block from
  re-running if some other addon's load also happens to fire
  `ADDON_LOADED` before this one unregisters (defensive; in practice this
  only matters between this addon's own load and unregister).

- [ ] **Step 3: Commit**

```bash
git add MyBuffTracker/Core.lua
git commit -m "feat: wire SavedVariables init and /bt slash command"
```

---

## Task 4: Bar.lua — time formatting (pure function)

**Files:**
- Modify: `MyBuffTracker/Bar.lua`
- Test: throwaway scratch script, see steps below.

**Interfaces:**
- Consumes: nothing.
- Produces: `MBT.FormatTime(seconds) -> string` — used by Task 5's
  `MBT.UpdateBar` to render the remaining-time label.

- [ ] **Step 1: Write the failing scratch test**

Create `selfcheck-bar-format.lua` in your scratchpad directory:

```lua
dofile("MyBuffTracker/Bar.lua")
local MBT = MyBuffTracker

assert(MBT.FormatTime(0) == "0.0s", "zero seconds")
assert(MBT.FormatTime(4.96) == "5.0s", "sub-minute rounds to 1 decimal")
assert(MBT.FormatTime(59.9) == "59.9s", "just under a minute stays in seconds")
assert(MBT.FormatTime(60) == "1m", "exactly a minute switches to minutes")
assert(MBT.FormatTime(61) == "2m", "just over a minute rounds up (ceil)")
assert(MBT.FormatTime(119) == "2m", "just under two minutes rounds up to 2m")

print("Bar.lua FormatTime selfcheck: ALL PASS")
```

Run: `lua /path/to/scratchpad/selfcheck-bar-format.lua`
Expected: FAIL — `attempt to call a nil value (field 'FormatTime')`.

- [ ] **Step 2: Implement `MBT.FormatTime`**

Append to `MyBuffTracker/Bar.lua`:

```lua
function MBT.FormatTime(seconds)
  if seconds >= 60 then
    return string.format("%dm", math.ceil(seconds / 60))
  end
  return string.format("%.1fs", seconds)
end
```

- [ ] **Step 3: Run the scratch test again and verify it passes**

Run: `lua /path/to/scratchpad/selfcheck-bar-format.lua`
Expected: `Bar.lua FormatTime selfcheck: ALL PASS`

- [ ] **Step 4: Delete the scratch script**

- [ ] **Step 5: Commit**

```bash
git add MyBuffTracker/Bar.lua
git commit -m "feat: add bar countdown time formatting"
```

---

## Task 5: Bar.lua — bar/icon frame factory (WoW glue)

**Files:**
- Modify: `MyBuffTracker/Bar.lua`

**Interfaces:**
- Consumes: `MBT.FormatTime` (Task 4).
- Produces:
  - `MBT.CreateBar(parent, index) -> barFrame` — creates one icon+bar
    frame (not yet positioned; the caller in Task 7 sets its anchor
    point).
  - `MBT.UpdateBar(bar, data, now)` — updates an existing bar's texture,
    color, fill fraction, and label from a display-list entry shaped like
    the output of Task 6's `MBT.ComputeDisplayList` (fields: `spellId`,
    `displayName`, `icon`, `barColor`, `isActive`, `count`, `duration`,
    `expirationTime`). `now` is the caller's `GetTime()` value, passed in
    (not called internally) so this function has no direct WoW API call
    other than the widget methods on `bar` itself.

No automated test is possible for frame creation — `CreateFrame` doesn't
exist outside the WoW client. Self-review against the checklist below;
real verification is manual (Task 12).

- [ ] **Step 1: Implement the bar factory and updater**

Append to `MyBuffTracker/Bar.lua`:

```lua
local DEFAULT_BAR_COLOR = { r = 0.2, g = 0.6, b = 1.0 }
local BAR_WIDTH = 160
local BAR_HEIGHT = 20
local ICON_SIZE = BAR_HEIGHT

function MBT.CreateBar(parent, index)
  local bar = CreateFrame("Frame", "MyBuffTrackerBar" .. index, parent)
  bar:SetWidth(BAR_WIDTH)
  bar:SetHeight(BAR_HEIGHT)

  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetWidth(ICON_SIZE)
  bar.icon:SetHeight(ICON_SIZE)
  bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

  bar.bar = CreateFrame("StatusBar", nil, bar)
  bar.bar:SetWidth(BAR_WIDTH - ICON_SIZE - 2)
  bar.bar:SetHeight(BAR_HEIGHT)
  bar.bar:SetPoint("LEFT", bar.icon, "RIGHT", 2, 0)
  bar.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar.bar:SetMinMaxValues(0, 1)
  bar.bar:SetValue(1)

  bar.bar.bg = bar.bar:CreateTexture(nil, "BACKGROUND")
  bar.bar.bg:SetAllPoints(bar.bar)
  bar.bar.bg:SetTexture(0, 0, 0, 0.5)

  bar.label = bar.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.label:SetPoint("LEFT", bar.bar, "LEFT", 3, 0)
  bar.label:SetPoint("RIGHT", bar.bar, "RIGHT", -3, 0)
  bar.label:SetJustifyH("LEFT")

  return bar
end

function MBT.UpdateBar(bar, data, now)
  bar.spellId = data.spellId
  bar:Show()
  bar.icon:SetTexture(data.icon)

  local color = data.barColor or DEFAULT_BAR_COLOR
  bar.bar:SetStatusBarColor(color.r, color.g, color.b)

  if data.isActive then
    bar.icon:SetDesaturated(false)
    local remaining = math.max(data.expirationTime - now, 0)
    local fraction = 1
    if data.duration and data.duration > 0 then
      fraction = remaining / data.duration
    end
    bar.bar:SetValue(fraction)

    local text = data.displayName
    if data.count and data.count > 1 then
      text = text .. " x" .. data.count
    end
    text = text .. "  " .. MBT.FormatTime(remaining)
    bar.label:SetText(text)
  else
    bar.icon:SetDesaturated(true)
    bar.bar:SetValue(1)
    bar.label:SetText(data.displayName)
  end
end
```

- [ ] **Step 2: Self-review checklist**

- [ ] `MBT.UpdateBar` is only ever called (in Task 7) with entries that
  Task 6's `MBT.ComputeDisplayList` already decided should be visible —
  it never needs to `Hide()` a bar itself; recycling/hiding stale bars is
  the caller's job (Task 7), matching the spec's "hide vs dim" behavior
  living in the sort/filter step, not the render step.
  `bar:Show()` at the top of `UpdateBar` is correct because every call
  means "this bar is in this frame, render it" — bars beyond the current
  list length are hidden by the caller, not by this function.
- [ ] `SetStatusBarColor` and `SetDesaturated` are texture/statusbar
  methods available on 3.3.5a `StatusBar`/`Texture` widgets — no
  BackdropTemplate or retail-only mixin is used anywhere in this file
  (3.3.5a doesn't have the template-split backdrop system introduced in
  BfA 8.0; only `Frame:SetBackdrop` used later in Task 11 relies on the
  native pre-8.0 backdrop API, which is correct for this client).
- [ ] `bar.bar:SetMinMaxValues(0, 1)` is set once at creation and never
  changed, so `SetValue` always receives a 0–1 fraction — consistent
  between the active branch (`fraction`) and the inactive/dimmed branch
  (`1`, i.e. full grey bar).

- [ ] **Step 3: Commit**

```bash
git add MyBuffTracker/Bar.lua
git commit -m "feat: add bar/icon frame factory and updater"
```

---

## Task 6: Tracker.lua — aura matching & display order (pure functions)

**Files:**
- Modify: `MyBuffTracker/Tracker.lua`
- Test: throwaway scratch script, see steps below.

**Interfaces:**
- Consumes: nothing WoW-specific directly — takes a `unitBuffFn`
  parameter shaped like `UnitBuff(unit, index) -> name, rank, icon,
  count, dispelType, duration, expirationTime, caster, isStealable,
  shouldConsolidate, spellId` (the real `UnitBuff` global is passed in by
  Task 7, a plain Lua function stub is passed in by the test here).
- Produces:
  - `MBT.MatchActiveAuras(trackedBuffs, unitBuffFn) -> activeBySpellId`
    — a table keyed by `spellId`, values `{icon, count, duration,
    expirationTime}`, containing only tracked buffs that are currently
    active.
  - `MBT.ComputeDisplayList(trackedBuffs, activeBySpellId, sortMode) ->
    list` — an array, each entry `{spellId, displayName, icon, barColor,
    order, isActive, count, duration, expirationTime}`, already filtered
    (hidden-when-missing buffs excluded) and sorted per `sortMode`. This
    is exactly the shape Task 5's `MBT.UpdateBar` expects.

- [ ] **Step 1: Write the failing scratch test**

Create `selfcheck-tracker.lua` in your scratchpad directory:

```lua
dofile("MyBuffTracker/Tracker.lua")
local MBT = MyBuffTracker

-- ===== MatchActiveAuras =====

local trackedBuffs = {
  { spellId = 111, displayName = "Rampage", icon = "trackedicon1", missingBehavior = "hide", order = 1 },
  { spellId = 222, displayName = "Battle Shout", icon = "trackedicon2", missingBehavior = "dim", order = 2 },
  { spellId = 333, displayName = "Berserker Rage", icon = "trackedicon3", missingBehavior = "hide", order = 3 },
}

-- Mock UnitBuff: player has spellId 111 (active) and an untracked spellId 999.
-- spellId 222 and 333 are NOT currently active.
local mockAuras = {
  { name = "Rampage", rank = "", icon = "activeicon1", count = 1, dispelType = "", duration = 12, expirationTime = 100, caster = "player", isStealable = false, shouldConsolidate = false, spellId = 111 },
  { name = "Some Other Buff", rank = "", icon = "activeicon2", count = 3, dispelType = "", duration = 30, expirationTime = 200, caster = "player", isStealable = false, shouldConsolidate = false, spellId = 999 },
}
local function mockUnitBuff(unit, index)
  local a = mockAuras[index]
  if not a then return nil end
  return a.name, a.rank, a.icon, a.count, a.dispelType, a.duration, a.expirationTime, a.caster, a.isStealable, a.shouldConsolidate, a.spellId
end

local active = MBT.MatchActiveAuras(trackedBuffs, mockUnitBuff)
assert(active[111] ~= nil, "spellId 111 should be matched active")
assert(active[111].icon == "activeicon1", "matched entry should carry the live icon")
assert(active[111].count == 1)
assert(active[111].duration == 12 and active[111].expirationTime == 100)
assert(active[222] == nil, "spellId 222 is not active, should not appear")
assert(active[333] == nil, "spellId 333 is not active, should not appear")
assert(active[999] == nil, "untracked spellId 999 must not appear even though it's active")

-- ===== ComputeDisplayList: fixed sort, hide vs dim =====

local fixedList = MBT.ComputeDisplayList(trackedBuffs, active, "fixed")
-- 111 active+hide -> visible; 222 inactive+dim -> visible (dimmed); 333 inactive+hide -> excluded
assert(#fixedList == 2, "hide+inactive buff (333) must be excluded from the list")
assert(fixedList[1].spellId == 111 and fixedList[1].isActive == true)
assert(fixedList[2].spellId == 222 and fixedList[2].isActive == false)
assert(fixedList[1].order < fixedList[2].order, "fixed sort must follow the order field")
assert(fixedList[1].icon == "activeicon1", "active entry uses the live aura icon")
assert(fixedList[2].icon == "trackedicon2", "inactive/dimmed entry falls back to the tracked buff's stored icon")

-- ===== ComputeDisplayList: expiration sort =====

local trackedBuffs2 = {
  { spellId = 1, displayName = "A", icon = "i1", missingBehavior = "dim", order = 1 },
  { spellId = 2, displayName = "B", icon = "i2", missingBehavior = "dim", order = 2 },
  { spellId = 3, displayName = "C", icon = "i3", missingBehavior = "dim", order = 3 },
}
local active2 = {
  [1] = { icon = "i1", count = 1, duration = 10, expirationTime = 50 },  -- expires later
  [2] = { icon = "i2", count = 1, duration = 10, expirationTime = 20 },  -- expires soonest
  -- spellId 3 inactive (dimmed, stays visible)
}
local expList = MBT.ComputeDisplayList(trackedBuffs2, active2, "expiration")
assert(#expList == 3, "dim buffs stay visible under expiration sort too")
assert(expList[1].spellId == 2, "soonest-expiring active buff sorts first")
assert(expList[2].spellId == 1, "later-expiring active buff sorts second")
assert(expList[3].spellId == 3, "inactive dimmed buffs sort after all active buffs")

print("Tracker.lua selfcheck: ALL PASS")
```

Run: `lua /path/to/scratchpad/selfcheck-tracker.lua`
Expected: FAIL — `attempt to call a nil value (field 'MatchActiveAuras')`.

- [ ] **Step 2: Implement `MBT.MatchActiveAuras` and `MBT.ComputeDisplayList`**

Append to `MyBuffTracker/Tracker.lua`:

```lua
function MBT.MatchActiveAuras(trackedBuffs, unitBuffFn)
  local trackedSpellIds = {}
  for _, buff in ipairs(trackedBuffs) do
    trackedSpellIds[buff.spellId] = true
  end

  local activeBySpellId = {}
  local i = 1
  while true do
    local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = unitBuffFn("player", i)
    if not name then break end
    if trackedSpellIds[spellId] then
      activeBySpellId[spellId] = {
        icon = icon,
        count = count,
        duration = duration,
        expirationTime = expirationTime,
      }
    end
    i = i + 1
  end

  return activeBySpellId
end

function MBT.ComputeDisplayList(trackedBuffs, activeBySpellId, sortMode)
  local list = {}

  for _, buff in ipairs(trackedBuffs) do
    local active = activeBySpellId[buff.spellId]
    local visible = (active ~= nil) or (buff.missingBehavior == "dim")
    if visible then
      table.insert(list, {
        spellId = buff.spellId,
        displayName = buff.displayName,
        icon = (active and active.icon) or buff.icon,
        barColor = buff.barColor,
        order = buff.order,
        isActive = active ~= nil,
        count = (active and active.count) or 0,
        duration = (active and active.duration) or 0,
        expirationTime = (active and active.expirationTime) or 0,
      })
    end
  end

  if sortMode == "expiration" then
    table.sort(list, function(a, b)
      if a.isActive ~= b.isActive then
        return a.isActive
      end
      if a.isActive then
        return a.expirationTime < b.expirationTime
      end
      return a.order < b.order
    end)
  else
    table.sort(list, function(a, b)
      return a.order < b.order
    end)
  end

  return list
end
```

- [ ] **Step 3: Run the scratch test again and verify it passes**

Run: `lua /path/to/scratchpad/selfcheck-tracker.lua`
Expected: `Tracker.lua selfcheck: ALL PASS`

- [ ] **Step 4: Delete the scratch script**

- [ ] **Step 5: Commit**

```bash
git add MyBuffTracker/Tracker.lua
git commit -m "feat: add aura matching and display-order computation"
```

---

## Task 7: Tracker.lua — event-driven display engine (WoW glue)

**Files:**
- Modify: `MyBuffTracker/Tracker.lua`

**Interfaces:**
- Consumes: `MBT.CreateBar`, `MBT.UpdateBar` (Task 5),
  `MBT.MatchActiveAuras`, `MBT.ComputeDisplayList` (Task 6), `MBT.db`
  (Task 3), `MBT.SetAnchorPosition` (Task 2).
- Produces:
  - `MBT.InitTracker()` — called once from Core.lua's `ADDON_LOADED`
    handler (Task 3). Creates the anchor frame, the `UNIT_AURA` /
    `PLAYER_ENTERING_WORLD` event frame, and the `OnUpdate` ticker.
  - `MBT.RefreshDisplay()` — the single matching+layout entry point,
    called both by the event handler and by the ticker.
  - `MBT.SetAnchorLocked(locked)` — toggles whether the anchor frame
    responds to drag, called from Config.lua (Task 11).
  - `MBT.anchor` — the anchor frame, read by Config.lua if needed.

No automated test is possible here (frame creation, real events). Real
verification is manual (Task 12, items 1–4).

- [ ] **Step 1: Implement the tracker engine**

Append to `MyBuffTracker/Tracker.lua`:

```lua
local UPDATE_INTERVAL = 0.1

local anchor
local bars = {}
local elapsedSinceUpdate = 0

local function EnsureBar(index)
  if not bars[index] then
    bars[index] = MBT.CreateBar(anchor, index)
  end
  return bars[index]
end

local function LayoutBars(displayList)
  for i, data in ipairs(displayList) do
    local bar = EnsureBar(i)
    bar:ClearAllPoints()
    if i == 1 then
      bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    else
      bar:SetPoint("TOPLEFT", bars[i - 1], "BOTTOMLEFT", 0, -2)
    end
    MBT.UpdateBar(bar, data, GetTime())
  end

  for i = #displayList + 1, #bars do
    bars[i]:Hide()
  end
end

function MBT.RefreshDisplay()
  if not MBT.db then return end
  local activeBySpellId = MBT.MatchActiveAuras(MBT.db.trackedBuffs, UnitBuff)
  local displayList = MBT.ComputeDisplayList(MBT.db.trackedBuffs, activeBySpellId, MBT.db.sortMode)
  LayoutBars(displayList)
end

function MBT.SetAnchorLocked(locked)
  if not anchor then return end
  anchor:EnableMouse(not locked)
end

function MBT.InitTracker()
  anchor = CreateFrame("Frame", "MyBuffTrackerAnchor", UIParent)
  anchor:SetWidth(160)
  anchor:SetHeight(1)
  anchor:SetPoint(MBT.db.anchor.point, UIParent, MBT.db.anchor.point, MBT.db.anchor.x, MBT.db.anchor.y)
  anchor:SetMovable(true)
  anchor:EnableMouse(false)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    MBT.SetAnchorPosition(MBT.db, point, x, y)
  end)
  MBT.anchor = anchor

  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("UNIT_AURA")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    MBT.RefreshDisplay()
  end)

  local ticker = CreateFrame("Frame")
  ticker:SetScript("OnUpdate", function(self, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= UPDATE_INTERVAL then
      elapsedSinceUpdate = 0
      MBT.RefreshDisplay()
    end
  end)

  MBT.RefreshDisplay()
end
```

- [ ] **Step 2: Self-review checklist**

- [ ] `UNIT_AURA` in 3.3.5a fires with a single `unit` argument (no
  `updateInfo` payload — that was added much later); the handler's
  `event, unit` parameter order matches `OnEvent(self, event, ...)`.
- [ ] The `unit ~= "player"` guard prevents re-rendering on every other
  unit's aura change (party/target/etc.) — this addon only ever tracks
  `"player"` per the v1 scope constraint.
- [ ] `MBT.RefreshDisplay` is the *only* place that calls
  `MBT.MatchActiveAuras`/`MBT.ComputeDisplayList` — both the event
  handler and the `OnUpdate` ticker call it, satisfying the "one matching
  code path, two triggers" constraint from Global Constraints.
- [ ] The `OnUpdate` ticker is throttled to `UPDATE_INTERVAL` (0.1s) and
  does not re-run `MatchActiveAuras` faster than that, matching the
  spec's "throttled `OnUpdate` ticker (~0.1s)" requirement.
- [ ] `LayoutBars`'s trailing `for i = #displayList + 1, #bars do
  bars[i]:Hide() end` correctly recycles/hides bars left over from a
  longer previous list (e.g. a buff just expired and was hide-on-missing,
  shrinking the list by one).
- [ ] Anchor position is only persisted on `OnDragStop` (not continuously
  during drag), and reads back via `self:GetPoint()` — correct since the
  anchor is always given exactly one `SetPoint` call, so the no-argument
  `GetPoint()` form unambiguously returns that single point.

- [ ] **Step 3: Commit**

```bash
git add MyBuffTracker/Tracker.lua
git commit -m "feat: wire event-driven tracker engine with anchor drag"
```

---

## Task 8: Config.lua — buff name resolution (pure function)

**Files:**
- Modify: `MyBuffTracker/Config.lua`
- Test: throwaway scratch script, see steps below.

**Interfaces:**
- Consumes: nothing WoW-specific directly — takes the same `unitBuffFn`
  shape as Task 6.
- Produces: `MBT.ResolveBuffByName(name, unitBuffFn) -> match|nil`, where
  `match` is `{spellId, displayName, icon}`. Used by Task 9's add-flow UI.

- [ ] **Step 1: Write the failing scratch test**

Create `selfcheck-config-resolve.lua` in your scratchpad directory:

```lua
dofile("MyBuffTracker/Config.lua")
local MBT = MyBuffTracker

local mockAuras = {
  { name = "Rampage", icon = "icon1", spellId = 111 },
  { name = "Battle Shout", icon = "icon2", spellId = 222 },
}
local function mockUnitBuff(unit, index)
  local a = mockAuras[index]
  if not a then return nil end
  return a.name, "", a.icon, 1, "", 10, 100, "player", false, false, a.spellId
end

local match = MBT.ResolveBuffByName("Battle Shout", mockUnitBuff)
assert(match ~= nil, "exact name should match")
assert(match.spellId == 222 and match.icon == "icon2" and match.displayName == "Battle Shout")

local caseInsensitive = MBT.ResolveBuffByName("rampage", mockUnitBuff)
assert(caseInsensitive ~= nil and caseInsensitive.spellId == 111, "match should be case-insensitive")

local noMatch = MBT.ResolveBuffByName("Nonexistent Buff", mockUnitBuff)
assert(noMatch == nil, "no active buff with that name should return nil")

print("Config.lua ResolveBuffByName selfcheck: ALL PASS")
```

Run: `lua /path/to/scratchpad/selfcheck-config-resolve.lua`
Expected: FAIL — `attempt to call a nil value (field 'ResolveBuffByName')`.

- [ ] **Step 2: Implement `MBT.ResolveBuffByName`**

Append to `MyBuffTracker/Config.lua`:

```lua
function MBT.ResolveBuffByName(name, unitBuffFn)
  local lowerName = string.lower(name)
  local i = 1
  while true do
    local buffName, _, icon, _, _, _, _, _, _, _, spellId = unitBuffFn("player", i)
    if not buffName then break end
    if string.lower(buffName) == lowerName then
      return { spellId = spellId, displayName = buffName, icon = icon }
    end
    i = i + 1
  end
  return nil
end
```

- [ ] **Step 3: Run the scratch test again and verify it passes**

Run: `lua /path/to/scratchpad/selfcheck-config-resolve.lua`
Expected: `Config.lua ResolveBuffByName selfcheck: ALL PASS`

- [ ] **Step 4: Delete the scratch script**

- [ ] **Step 5: Commit**

```bash
git add MyBuffTracker/Config.lua
git commit -m "feat: add buff name resolution against active auras"
```

---

## Task 9: Config.lua — add-flow UI (name entry, confirm, advanced spell ID)

**Files:**
- Modify: `MyBuffTracker/Config.lua`

**Interfaces:**
- Consumes: `MBT.ResolveBuffByName` (Task 8), `MBT.AddTrackedBuff` (Task
  2), `MBT.db` (Task 3), `MBT.RefreshDisplay` (Task 7). Calls the global
  `GetSpellInfo` (WoW API) for the advanced/spell-ID path.
- Produces: module-local UI state and handler functions
  (`HandleAddByName`, `HandleConfirm`, `HandleAddById`, etc.) and the
  widgets `addEditBox`, `addButton`, `matchIcon`, `matchNameText`,
  `confirmButton`, `cancelButton`, `notFoundText`, `advancedToggle`,
  `spellIdEditBox`, `addByIdButton` — all consumed by Task 11's
  `MBT.InitConfig`, which parents them into the config frame.

This task defines the widgets' *behavior* (handler functions and local
widget variables); Task 11 creates the actual frame hierarchy
(`configFrame` and its children) that these are attached to. Writing
behavior before parenting keeps each task's diff focused, matching the
"produces exact names, consumed by name" contract in Interfaces.

No automated test is possible (real widgets, real `GetSpellInfo`).
Self-review against the checklist; manual verification in Task 12 (items
1 and 5).

- [ ] **Step 1: Implement the add-flow state and handlers**

Append to `MyBuffTracker/Config.lua`:

```lua
local addEditBox, addButton, matchIcon, matchNameText, confirmButton, cancelButton
local advancedToggle, spellIdEditBox, addByIdButton, notFoundText
local pendingMatch
local advancedMode = false

local function ShowPendingMatch(match)
  pendingMatch = match
  matchIcon:SetTexture(match.icon)
  matchNameText:SetText(match.displayName)
  matchIcon:Show()
  matchNameText:Show()
  confirmButton:Show()
  cancelButton:Show()
  notFoundText:Hide()
end

local function ClearPendingMatch()
  pendingMatch = nil
  matchIcon:Hide()
  matchNameText:Hide()
  confirmButton:Hide()
  cancelButton:Hide()
end

local function HandleAddByName()
  local name = addEditBox:GetText()
  if not name or name == "" then return end
  local match = MBT.ResolveBuffByName(name, UnitBuff)
  if match then
    ShowPendingMatch(match)
  else
    ClearPendingMatch()
    notFoundText:Show()
  end
end

local function HandleConfirm()
  if not pendingMatch then return end
  MBT.AddTrackedBuff(MBT.db, pendingMatch.spellId, pendingMatch.displayName, pendingMatch.icon)
  ClearPendingMatch()
  addEditBox:SetText("")
  if MBT.RefreshConfigRows then MBT.RefreshConfigRows() end
  MBT.RefreshDisplay()
end

local function HandleAddById()
  local idText = spellIdEditBox:GetText()
  local spellId = tonumber(idText)
  if not spellId then return end
  local name, _, icon = GetSpellInfo(spellId)
  local displayName = name or ("Spell " .. spellId)
  MBT.AddTrackedBuff(MBT.db, spellId, displayName, icon)
  spellIdEditBox:SetText("")
  if MBT.RefreshConfigRows then MBT.RefreshConfigRows() end
  MBT.RefreshDisplay()
end
```

Note: `MBT.RefreshConfigRows` doesn't exist yet — it's defined in Task
10. Guarded the same way `MBT.InitTracker`/`MBT.InitConfig` are guarded
in Task 3, for the same reason (all files finish loading before any of
these handlers can actually fire from user input).

- [ ] **Step 2: Self-review checklist**

- [ ] `HandleAddByName` never calls `MBT.AddTrackedBuff` directly — it
  only stages a `pendingMatch` and shows a confirm/cancel prompt, per the
  spec's add-flow step 3 ("On match: shows the resolved icon, asks for
  confirmation").
  `HandleConfirm` is the only place that actually calls
  `MBT.AddTrackedBuff` for the by-name path.
- [ ] `HandleAddById` resolves the display name/icon via `GetSpellInfo`
  when available, but falls back to `"Spell " .. spellId"` if
  `GetSpellInfo` returns nil (invalid ID) — matches the spec's "manual
  lookup...outside the addon" fallback path without crashing on a bad ID.
- [ ] `GetSpellInfo` in 3.3.5a returns `name, rank, icon, castTime,
  minRange, maxRange` (6 values, no `spellId`) — `local name, _, icon =
  GetSpellInfo(spellId)` correctly takes only the first and third.

- [ ] **Step 3: Commit**

```bash
git add MyBuffTracker/Config.lua
git commit -m "feat: add config panel buff-add flow with name resolution"
```

---

## Task 10: Config.lua — tracked-buff list rows (display, dim, color, reorder, remove)

**Files:**
- Modify: `MyBuffTracker/Config.lua`

**Interfaces:**
- Consumes: `MBT.db` (Task 3), `MBT.SetMissingBehavior`, `MBT.SetBarColor`,
  `MBT.MoveTrackedBuff`, `MBT.RemoveTrackedBuff` (Task 2),
  `MBT.RefreshDisplay` (Task 7). Uses the global `ColorPickerFrame` /
  `ShowUIPanel` (WoW API).
- Produces: `MBT.RefreshConfigRows()` (referenced by Task 9's handlers,
  defined here) and a module-local `rows` array + `CreateRow(parent,
  index)` factory, consumed by Task 11's `MBT.InitConfig` to build the
  row pool under the list container.

No automated test is possible (real widgets). Self-review against the
checklist; manual verification in Task 12 (items 3 and 5, plus general
add/remove/reorder exercise).

- [ ] **Step 1: Implement the row factory and refresh logic**

Append to `MyBuffTracker/Config.lua`:

```lua
local ROW_HEIGHT = 24
local MAX_VISIBLE_ROWS = 12
local rows = {}

function MBT.RefreshConfigRows()
  local buffs = MBT.db.trackedBuffs
  for i = 1, MAX_VISIBLE_ROWS do
    local row = rows[i]
    local buff = buffs[i]
    if buff then
      row.spellId = buff.spellId
      row.icon:SetTexture(buff.icon)
      row.nameText:SetText(buff.displayName)
      row.dimCheck:SetChecked(buff.missingBehavior == "dim")
      if buff.barColor then
        row.colorSwatchTexture:SetVertexColor(buff.barColor.r, buff.barColor.g, buff.barColor.b)
      else
        row.colorSwatchTexture:SetVertexColor(1, 1, 1)
      end
      row:Show()
    else
      row:Hide()
    end
  end
end

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetWidth(360)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + 2))

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetWidth(ROW_HEIGHT - 4)
  row.icon:SetHeight(ROW_HEIGHT - 4)
  row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

  row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.nameText:SetWidth(120)
  row.nameText:SetJustifyH("LEFT")

  row.dimCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.dimCheck:SetWidth(20)
  row.dimCheck:SetHeight(20)
  row.dimCheck:SetPoint("LEFT", row.nameText, "RIGHT", 4, 0)
  row.dimCheck:SetScript("OnClick", function(self)
    MBT.SetMissingBehavior(MBT.db, row.spellId, self:GetChecked() and "dim" or "hide")
    MBT.RefreshDisplay()
  end)

  row.colorSwatch = CreateFrame("Button", nil, row)
  row.colorSwatch:SetWidth(16)
  row.colorSwatch:SetHeight(16)
  row.colorSwatch:SetPoint("LEFT", row.dimCheck, "RIGHT", 6, 0)
  row.colorSwatch:SetNormalTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
  row.colorSwatchTexture = row.colorSwatch:GetNormalTexture()
  row.colorSwatch:SetScript("OnClick", function()
    local current
    for _, buff in ipairs(MBT.db.trackedBuffs) do
      if buff.spellId == row.spellId then current = buff.barColor end
    end
    local r, g, b = 0.2, 0.6, 1.0
    if current then r, g, b = current.r, current.g, current.b end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      MBT.SetBarColor(MBT.db, row.spellId, nr, ng, nb)
      MBT.RefreshConfigRows()
      MBT.RefreshDisplay()
    end
    ColorPickerFrame.cancelFunc = function() end
    ShowUIPanel(ColorPickerFrame)
  end)

  row.upButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.upButton:SetWidth(20)
  row.upButton:SetHeight(20)
  row.upButton:SetText("^")
  row.upButton:SetPoint("LEFT", row.colorSwatch, "RIGHT", 6, 0)
  row.upButton:SetScript("OnClick", function()
    MBT.MoveTrackedBuff(MBT.db, row.spellId, -1)
    MBT.RefreshConfigRows()
    MBT.RefreshDisplay()
  end)

  row.downButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.downButton:SetWidth(20)
  row.downButton:SetHeight(20)
  row.downButton:SetText("v")
  row.downButton:SetPoint("LEFT", row.upButton, "RIGHT", 2, 0)
  row.downButton:SetScript("OnClick", function()
    MBT.MoveTrackedBuff(MBT.db, row.spellId, 1)
    MBT.RefreshConfigRows()
    MBT.RefreshDisplay()
  end)

  row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.removeButton:SetWidth(60)
  row.removeButton:SetHeight(20)
  row.removeButton:SetText("Remove")
  row.removeButton:SetPoint("LEFT", row.downButton, "RIGHT", 6, 0)
  row.removeButton:SetScript("OnClick", function()
    MBT.RemoveTrackedBuff(MBT.db, row.spellId)
    MBT.RefreshConfigRows()
    MBT.RefreshDisplay()
  end)

  return row
end

function MBT.CreateConfigRows(parent)
  for i = 1, MAX_VISIBLE_ROWS do
    rows[i] = CreateRow(parent, i)
  end
end
```

- [ ] **Step 2: Self-review checklist**

- [ ] `row.colorSwatch` is a plain `Button`, not a `Texture` — vertex
  coloring must go through `row.colorSwatch:GetNormalTexture()` (captured
  once as `row.colorSwatchTexture` at creation), not
  `row.colorSwatch:SetVertexColor(...)` directly (a `Button` has no such
  method).
- [ ] `ColorPickerFrame.func`/`.cancelFunc`/`.hasOpacity` +
  `ShowUIPanel(ColorPickerFrame)` is the correct 3.3.5a-era color picker
  API (the redesigned `SetupColorPickerAndShow` API doesn't exist until
  much later retail/Classic clients).
- [ ] Row pool is fixed at `MAX_VISIBLE_ROWS = 12` with no scrolling —
  deliberate per the spec's "no UI polish beyond the above" v2 deferral;
  a row beyond index 12 simply won't display in the config panel (still
  tracked and rendered correctly by the Tracker engine, which has no such
  cap).
- [ ] `RefreshConfigRows` hides rows with no corresponding buff (`buffs[i]`
  is nil) rather than leaving stale data visible when the list shrinks.

- [ ] **Step 3: Commit**

```bash
git add MyBuffTracker/Config.lua
git commit -m "feat: add tracked-buff list rows with reorder, dim, and color controls"
```

---

## Task 11: Config.lua — global controls, panel assembly, and `/bt` toggle

**Files:**
- Modify: `MyBuffTracker/Config.lua`

**Interfaces:**
- Consumes: `MBT.SetSortMode` (Task 2), `MBT.SetAnchorLocked` (Task 7),
  the add-flow widgets/handlers (Task 9), `MBT.CreateConfigRows`,
  `MBT.RefreshConfigRows` (Task 10), `MBT.db` (Task 3).
- Produces:
  - `MBT.InitConfig()` — called from Core.lua's `ADDON_LOADED` handler
    (Task 3). Builds `configFrame` and parents every widget from Tasks 9
    and 10 into it.
  - `MBT.ToggleConfig()` — called from Core.lua's `/bt` handler (Task 3).

No automated test is possible. Self-review against the checklist; manual
verification in Task 12 (all items — this is the frame the user opens
with `/bt`).

- [ ] **Step 1: Implement panel assembly and global controls**

Append to `MyBuffTracker/Config.lua`:

```lua
local configFrame

function MBT.InitConfig()
  configFrame = CreateFrame("Frame", "MyBuffTrackerConfig", UIParent)
  configFrame:SetWidth(400)
  configFrame:SetHeight(520)
  configFrame:SetPoint("CENTER")
  configFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  configFrame:SetMovable(true)
  configFrame:EnableMouse(true)
  configFrame:RegisterForDrag("LeftButton")
  configFrame:SetScript("OnDragStart", configFrame.StartMoving)
  configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
  configFrame:Hide()

  local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", configFrame, "TOP", 0, -16)
  title:SetText("MyBuffTracker")

  local closeButton = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -4, -4)
  closeButton:SetScript("OnClick", function() configFrame:Hide() end)

  addEditBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
  addEditBox:SetWidth(180)
  addEditBox:SetHeight(20)
  addEditBox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -48)
  addEditBox:SetAutoFocus(false)
  addEditBox:SetScript("OnEnterPressed", HandleAddByName)

  addButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  addButton:SetWidth(60)
  addButton:SetHeight(22)
  addButton:SetText("Add")
  addButton:SetPoint("LEFT", addEditBox, "RIGHT", 8, 0)
  addButton:SetScript("OnClick", HandleAddByName)

  matchIcon = configFrame:CreateTexture(nil, "ARTWORK")
  matchIcon:SetWidth(20)
  matchIcon:SetHeight(20)
  matchIcon:SetPoint("TOPLEFT", addEditBox, "BOTTOMLEFT", 0, -8)
  matchIcon:Hide()

  matchNameText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  matchNameText:SetPoint("LEFT", matchIcon, "RIGHT", 4, 0)
  matchNameText:SetWidth(140)
  matchNameText:SetJustifyH("LEFT")
  matchNameText:Hide()

  confirmButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  confirmButton:SetWidth(70)
  confirmButton:SetHeight(20)
  confirmButton:SetText("Confirm")
  confirmButton:SetPoint("LEFT", matchNameText, "RIGHT", 8, 0)
  confirmButton:SetScript("OnClick", HandleConfirm)
  confirmButton:Hide()

  cancelButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  cancelButton:SetWidth(60)
  cancelButton:SetHeight(20)
  cancelButton:SetText("Cancel")
  cancelButton:SetPoint("LEFT", confirmButton, "RIGHT", 4, 0)
  cancelButton:SetScript("OnClick", ClearPendingMatch)
  cancelButton:Hide()

  notFoundText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  notFoundText:SetPoint("TOPLEFT", addEditBox, "BOTTOMLEFT", 0, -8)
  notFoundText:SetWidth(340)
  notFoundText:SetJustifyH("LEFT")
  notFoundText:SetText("No active buff matches that name. Use Advanced to enter a spell ID.")
  notFoundText:Hide()

  advancedToggle = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
  advancedToggle:SetWidth(20)
  advancedToggle:SetHeight(20)
  advancedToggle:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -108)

  local advancedLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  advancedLabel:SetPoint("LEFT", advancedToggle, "RIGHT", 2, 0)
  advancedLabel:SetText("Advanced: add by spell ID")

  spellIdEditBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
  spellIdEditBox:SetWidth(100)
  spellIdEditBox:SetHeight(20)
  spellIdEditBox:SetPoint("LEFT", advancedLabel, "RIGHT", 12, 0)
  spellIdEditBox:SetAutoFocus(false)
  spellIdEditBox:SetNumeric(true)
  spellIdEditBox:SetScript("OnEnterPressed", HandleAddById)
  spellIdEditBox:Hide()

  addByIdButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  addByIdButton:SetWidth(60)
  addByIdButton:SetHeight(20)
  addByIdButton:SetText("Add")
  addByIdButton:SetPoint("LEFT", spellIdEditBox, "RIGHT", 6, 0)
  addByIdButton:SetScript("OnClick", HandleAddById)
  addByIdButton:Hide()

  advancedToggle:SetScript("OnClick", function(self)
    advancedMode = self:GetChecked()
    if advancedMode then
      spellIdEditBox:Show()
      addByIdButton:Show()
    else
      spellIdEditBox:Hide()
      addByIdButton:Hide()
    end
  end)

  local listContainer = CreateFrame("Frame", nil, configFrame)
  listContainer:SetWidth(360)
  listContainer:SetHeight(MAX_VISIBLE_ROWS * (ROW_HEIGHT + 2))
  listContainer:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -140)
  MBT.CreateConfigRows(listContainer)

  local sortModeButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  sortModeButton:SetWidth(160)
  sortModeButton:SetHeight(22)
  sortModeButton:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -12)
  local function RefreshSortModeButton()
    sortModeButton:SetText("Sort: " .. MBT.db.sortMode)
  end
  sortModeButton:SetScript("OnClick", function()
    local newMode = (MBT.db.sortMode == "fixed") and "expiration" or "fixed"
    MBT.SetSortMode(MBT.db, newMode)
    RefreshSortModeButton()
    MBT.RefreshDisplay()
  end)

  local anchorLocked = true
  local lockButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  lockButton:SetWidth(160)
  lockButton:SetHeight(22)
  lockButton:SetPoint("LEFT", sortModeButton, "RIGHT", 8, 0)
  local function RefreshLockButton()
    lockButton:SetText(anchorLocked and "Unlock Anchor" or "Lock Anchor")
  end
  lockButton:SetScript("OnClick", function()
    anchorLocked = not anchorLocked
    MBT.SetAnchorLocked(anchorLocked)
    RefreshLockButton()
  end)

  RefreshSortModeButton()
  RefreshLockButton()
  MBT.RefreshConfigRows()
end

function MBT.ToggleConfig()
  if not configFrame then return end
  if configFrame:IsShown() then
    configFrame:Hide()
  else
    MBT.RefreshConfigRows()
    configFrame:Show()
  end
end
```

- [ ] **Step 2: Self-review checklist**

- [ ] `HandleAddByName`, `HandleConfirm`, `HandleAddById`,
  `ClearPendingMatch` are referenced here as plain upvalues, not
  `MBT.`-prefixed — confirm they're declared as `local function`
  (non-`MBT.`) in Task 9, in the same file, above this code, so they're
  in scope. (`Config.lua` is one file; Task 9's locals are visible to
  Task 11's code appended later in the same file.)
  `advancedMode` is also a Task-9 local, reused here as an upvalue by
  `advancedToggle`'s `OnClick` — same reasoning.
- [ ] `MBT.RefreshConfigRows()` is called both at the end of `InitConfig`
  (so the panel shows current state the first time it's built) and every
  time `ToggleConfig()` shows the panel (so edits made via the Tracker
  engine's own state, or from a previous session's SavedVariables, are
  reflected when reopened).
  `configFrame:Hide()` at creation matches the spec ("opened via slash
  command") — the panel must not be visible on login.
- [ ] `configFrame:SetBackdrop(...)` uses the native pre-8.0 backdrop API
  (no `BackdropTemplate` mixin needed) — correct for 3.3.5a, consistent
  with the Bar.lua self-review note in Task 5.
- [ ] `SLASH_MYBUFFTRACKER1`/`SlashCmdList["MYBUFFTRACKER"]` (Task 3) now
  has a real `MBT.ToggleConfig` to call — re-check Task 3's `/bt` handler
  still matches this function's exact name (`MBT.ToggleConfig`, no
  arguments).

- [ ] **Step 3: Commit**

```bash
git add MyBuffTracker/Config.lua
git commit -m "feat: assemble config panel with sort mode and anchor lock controls"
```

---

## Task 12: Install instructions and manual verification checklist

**Files:**
- Create: `MyBuffTracker/README.md`

**Interfaces:**
- Consumes: the finished addon (Tasks 1–11).
- Produces: nothing consumed by other tasks — this is the terminal task.

This task doesn't touch any `.lua` file. Its job is to hand the user (who
has the actual 3.3.5a client this environment lacks) a concrete,
sequential checklist to run once, matching the spec's Testing/install
plan section exactly. Running this checklist — not an automated test —
is what confirms Tasks 3, 5, 7, and 9–11's WoW-glue code actually works.

- [ ] **Step 1: Write install instructions and the verification checklist**

Create `MyBuffTracker/README.md`:

```markdown
# MyBuffTracker

A small WoW 3.3.5a addon that tracks a configurable list of your own
buffs and shows them as icon+bar countdown timers, with an in-game
config panel (`/bt`) for managing the list.

## Install

1. Copy (or symlink) the `MyBuffTracker` folder into your WoW 3.3.5a
   client's `Interface/AddOns/` directory, so the path
   `Interface/AddOns/MyBuffTracker/MyBuffTracker.toc` exists.
2. Launch (or `/reload`) and confirm `MyBuffTracker` appears (and is
   checked) in the AddOns list on the character-select screen.

## Manual verification checklist

Run these in order on a live character. Each step should match the
described result before moving to the next.

1. **Add a real active buff.** Cast or use an item that gives you a buff
   currently active on your character. Type `/bt` to open the config
   panel, type that buff's exact name into the name field, and click
   **Add** (or press Enter). Confirm the icon and name shown in the
   match-preview match the buff, then click **Confirm**. A bar should
   appear near the center of the screen.
2. **Countdown and expiry.** Confirm the bar's timer counts down
   smoothly and the displayed time roughly matches the buff's actual
   remaining duration (check against your buff tooltip). Let the buff
   expire; by default (`missingBehavior = "hide"`) the bar should
   disappear.
3. **Two buffs, both sort modes.** Add a second active buff the same way.
   In the config panel, confirm they're listed in the order you added
   them. Click the **Sort: fixed** button to switch to **Sort:
   expiration** — the bar stack should reorder live so the
   soonest-to-expire buff is on top; switch back to confirm it returns to
   your original fixed order.
4. **Anchor drag persists.** Click **Unlock Anchor** in the config panel,
   drag the bar stack to a new screen position, click **Lock Anchor**,
   then `/reload`. Confirm the bar stack reappears at the position you
   moved it to.
5. **Missing-behavior toggle.** In the config panel, find a tracked buff
   that is not currently active on you. Check its dim checkbox and
   confirm its bar appears immediately, desaturated/greyed, even though
   the buff is off. Uncheck it and confirm the bar disappears again.

If any step doesn't match, note which step and what happened instead —
that pinpoints which task's code (see the step-to-task mapping in the
implementation plan) needs a fix.
```

- [ ] **Step 2: Commit**

```bash
git add MyBuffTracker/README.md
git commit -m "docs: add install instructions and manual verification checklist"
```

---

## Self-Review Notes

**Spec coverage** — every section of
`docs/superpowers/specs/2026-09-24-buff-tracker-design.md` maps to a task:
Architecture/two components → Tasks 3+7 (Tracker) and 9–11 (Config); Data
model → Task 2; Spell identification & add flow → Tasks 8–9; Config panel
features (missing-behavior, bar color, remove/reorder, sort mode,
anchor lock) → Tasks 10–11; Display/runtime behavior (event-driven +
throttled ticker, expiration re-sort, hide/dim) → Tasks 6–7; File layout →
Task 1 (with the load-order clarification in Global Constraints); Testing
plan → Task 12, verbatim as the manual checklist.

**Placeholder scan** — no task contains "TBD"/"handle appropriately"/bare
prose describing code without showing it; every code block is complete
and copy-pasteable into the named file.

**Type/name consistency** — verified across tasks: `MBT.ComputeDisplayList`
(Task 6) output fields (`spellId, displayName, icon, barColor, order,
isActive, count, duration, expirationTime`) exactly match what
`MBT.UpdateBar` (Task 5) reads. `MBT.CreateBar`/`MBT.UpdateBar` (Task 5)
names match Task 7's calls. `MBT.ResolveBuffByName` (Task 8) match shape
(`spellId, displayName, icon`) matches what Task 9's `HandleConfirm`
passes into `MBT.AddTrackedBuff(db, spellId, displayName, icon)` (Task
2's exact signature). `MBT.RefreshConfigRows` is defined once (Task 10)
and referenced identically from Tasks 9 and 11. `MBT.SetAnchorLocked`
(Task 7) matches Task 11's `lockButton` call.
