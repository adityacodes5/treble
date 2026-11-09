# Manual testing

Automated tests cover the module system (`swift test`). These checklists cover what only a person can check. Run the relevant ones before each release.

## Performance (every release)

Targets from PLAN.md §4. With Activity Monitor open (CPU and Energy tabs):

- [ ] Idle CPU ~0.0% with the panel closed and nothing playing
- [ ] Idle wakeups < 1 per second
- [ ] Memory < 30 MB with one feature on, < 40 MB with all Phase 1 features on
- [ ] CPU returns to 0% within a few seconds of closing the panel

From Terminal:

```bash
top -l 7 -s 5 -pid $(pgrep -x Treble) -stats pid,cpu,mem,idlew
```

| Date | Build | Features on | Idle CPU | Memory | Wakeups |
|---|---|---|---|---|---|
| 2026-11-08 | 0.0.1 (1), Debug | Sample only (or none) | 0.0% | 23 MB | ~1 per 5 s |

## Phase 0: app shell

**First launch**
- [ ] "Choose your features" window appears and comes to the front
- [ ] Features needing permissions show "Needs: …" in orange
- [ ] Continue turns on exactly the ticked features
- [ ] Closing the window without Continue doesn't show it again next launch

**Menu bar and panel**
- [ ] Treble's icon appears in the menu bar
- [ ] Left-click opens the panel under the icon; clicking again closes it
- [ ] Esc closes the panel; so does clicking another app
- [ ] The panel doesn't take focus from the app you're typing in
- [ ] Right-click (and Control-click) shows Settings / Choose Features / Quit
- [ ] With no features on, the panel shows "No features turned on"
- [ ] Turning a feature on or off while the panel is open resizes it, top edge staying put
- [ ] Cmd-dragging the icon to a new spot is remembered after relaunch

**Feature placement** (using Sample)
- [ ] Panel: tile only. Menu bar: own item only. Both: both
- [ ] Sample's menu bar item shows its count and updates on tap
- [ ] Clicking Sample's menu bar item opens a popover with its tile
- [ ] "Sample on" appears in the panel footer only while Sample is on

**Settings**
- [ ] Opens in front, shows in Cmd-Tab and the Dock while open, disappears from both after closing
- [ ] Cmd-W closes it; Cmd-C / Cmd-V work in text fields
- [ ] Enabled features appear in the sidebar under "Your Features"
- [ ] Open at login: turning it on shows Treble in System Settings → General → Login Items
- [ ] Double-clicking Treble.app in Finder while it's running opens Settings

**Permissions** (once a feature needs one)
- [ ] Feature shows "Needs … permission" with Grant Access and Open System Settings
- [ ] Granting in System Settings starts the feature without a restart
- [ ] Revoking it stops the feature and shows the message again

**Appearance**
- [ ] Looks right in light and dark mode
- [ ] Reduce Transparency (Accessibility → Display) gives a solid panel
