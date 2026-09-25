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
   them. Under **Bar order**, select **Expiring soonest first** — the bar
   stack should reorder live so the soonest-to-expire buff is at the
   bottom, next to the anchor;
   select **List order** to confirm it returns to your original order.
4. **Anchor drag persists.** Click **Unlock Anchor** in the config panel,
   drag the bar stack to a new screen position, click **Lock Anchor**,
   then `/reload`. Confirm the bar stack reappears at the position you
   moved it to.
5. **Missing-behavior toggle.** In the config panel, find a tracked buff
   that is not currently active on you. Uncheck its **Active only**
   checkbox and confirm its bar appears immediately, desaturated/greyed,
   even though the buff is off. Check it again and confirm the bar
   disappears.
6. **Icon size.** Drag the **Icon size** slider in the config panel.
   Confirm the bar icons grow and shrink live, bars never overlap, and
   the size is kept after `/reload`.

If any step doesn't match, note which step and what happened instead —
that pinpoints which task's code (see the step-to-task mapping in the
implementation plan) needs a fix.
