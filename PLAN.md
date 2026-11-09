# Treble — Project Plan

> **Treble:** the top of the musical range, sitting at the top of your screen.
> Chosen 2026-11-08 after a name check. See [§12 Naming](#12-naming).

A free, open-source macOS menu bar app that adds features that feel built in:
now playing, sleep timer, keep awake, separate scroll direction for mouse and trackpad, stats, battery care and more.
You pick only the features you want, and features you don't pick cost nothing.

- **Target:** macOS 14 Sonoma and later, Apple Silicon first (Intel builds come free with a universal binary)
- **Main development Mac:** M2 MacBook Air on **macOS 15.7 Sequoia** (first assumed to be 14; corrected 2026-11-08). Still pre–Liquid Glass.
- **Design language:** Sonoma's own: Control Center materials, SF Symbols, system accent color. No notch UI, no Liquid Glass.
- **License:** MIT (recommended, see §13)

---

## Table of contents

1. [Principles](#1-principles)
2. [The modularity model](#2-the-modularity-model)
3. [Architecture](#3-architecture)
4. [Performance budget](#4-performance-budget)
5. [Feature specs — Phase 1](#5-feature-specs--phase-1)
6. [App-wide behavior and nuances](#6-app-wide-behavior-and-nuances)
7. [Phases and milestones](#7-phases-and-milestones)
8. [Later features (backlog)](#8-later-features-backlog)
9. [Non-goals](#9-non-goals)
10. [Developer setup and gotchas](#10-developer-setup-and-gotchas)
11. [Glossary](#11-glossary)
12. [Naming](#12-naming)
13. [Open decisions](#13-open-decisions)

---

## 1. Principles

These settle arguments later. If a feature breaks one of these, it changes or it doesn't ship.

1. **Pay only for what you use.** A disabled feature isn't loaded, doesn't run, doesn't ask for permissions and doesn't wake the CPU.
2. **Event-driven, never polling.** React to system notifications. Timers exist only for things that are actually about time (a countdown), and they're coalesced.
3. **Features don't know about each other.** They connect only through shared parts that Core owns (see §2). Deleting a feature's folder must not break the build.
4. **Feels like macOS, not like an app.** System materials, system fonts, system behaviors. Settings looks like System Settings. Nothing flashy.
5. **Fail small.** If a feature can't work (missing permission, macOS changed a private API), that one feature says so in its tile. The rest of the app carries on.
6. **Private by default.** No telemetry, no accounts, no network except an update check you can turn off.
7. **Simple over clever.** Readable code a contributor can follow beats a smart abstraction. Few dependencies.

---

## 2. The modularity model

### 2.1 What you asked for

- **Like an installer's component list:** you tick the features you want.
- **Like Chrome tabs:** one feature misbehaving can't take down the others.
- **Works together like magic:** features cooperate when they're both on, without depending on each other.

### 2.2 Choosing features (the installer part)

On first launch, Treble shows a **"Choose your features"** screen, like an installer's component step:

```
☑ Now Playing      Song in the menu bar, album art on click
☑ Sleep Timer      Fade out, pause, and sleep your Mac
☑ Keep Awake       Stop your Mac sleeping for a while
☐ Scroll           Separate direction for mouse and trackpad
                   Needs: Accessibility permission
☐ Stats            CPU, memory, temperature
                                        [Continue]
```

- Each row lists the permissions it needs, so nothing surprises you later.
- You can change the list any time in **Settings → Features**. Turning a feature on or off is instant, with no restart.
- An unticked feature is truly gone at runtime. Its code is in the app (a few hundred KB on disk) but is never loaded into memory.

> We don't do *download-time* package selection. Separately signed downloadable bundles would add a lot of complexity (code signing, updates, version mismatches) to save a few MB of disk. Runtime selection gives the same experience at a fraction of the cost.

### 2.3 Isolation (the Chrome part)

Chrome gives every tab its own process. That's why a crashed tab doesn't kill the browser, and also why Chrome uses so much RAM: each process carries its own overhead. Doing that for every Treble feature would break principle 1.

So Treble uses **three layers of isolation**, from cheapest to strongest:

| Layer | What it protects against | Cost | Used for |
|---|---|---|---|
| **1. Code isolation** (compile time) | Features getting tangled together | Free | Every feature |
| **2. Fault containment** (runtime) | A feature failing (missing API, no permission, bad data) | Free | Every feature |
| **3. Process isolation** (separate helper process) | A crash or hang | ~3–8 MB RAM per helper, only while enabled | Only where justified (below) |

**Layer 1 — code isolation.** Each feature is its own Swift package target. The compiler **forbids** one feature from importing another; the build fails if you try. This is enforced by the dependency rules in §3.2, not by discipline.

**Layer 2 — fault containment.** Every feature has a status: `running`, `needsPermission`, `unavailable(reason)` or `failed(reason)`. Risky calls (private APIs, permission-gated APIs) are wrapped so failure becomes a status instead of a crash. For example, if macOS removes the private API Now Playing uses, its tile says "Not available on this macOS version", and Keep Awake still works.

**Layer 3 — process isolation, only where it earns its cost:**

| Helper | Why it gets its own process | When |
|---|---|---|
| **Charge limit daemon** | Needs root to write battery controller settings. Must be separate, and tiny, for security. | Phase 3 |
| **Media bridge (macOS 15.4+ only)** | Apple locked the Now Playing API in 15.4. The known workaround runs in a separate process anyway. | **Phase 1**: required, since the main development Mac runs 15.7 |
| **Scroll engine** *(maybe)* | Scrolling must never stutter. If the main app's UI hangs, an in-process scroll handler could lag. | Start in-process on a dedicated thread. Move to a helper only if testing shows stutter. |

Helpers are launched only while their feature is enabled. If one crashes, the system restarts it and the main app keeps running.

Honest limitation: a crash in plain Swift code inside the main process still takes the whole app down (Swift can't catch crashes like some languages can). Layer 2 makes this rare by design: no force-unwraps, all risky calls wrapped. Treble can also be set up so macOS relaunches it within seconds after a crash (see §6.4).

### 2.4 Working together (the magic part)

Features never talk to each other directly. They cooperate through three things Core provides:

**a) Shared services.** These are the system plumbing that several features need, each started only when someone uses it:

| Service | Wraps | Used by |
|---|---|---|
| `MediaService` | The now-playing info and controls | Now Playing, Sleep Timer ("end of track") |
| `PowerService` | Sleep, display sleep, keep-awake assertions | Keep Awake, Sleep Timer |
| `AudioService` | System volume, output devices | Sleep Timer (fade), Audio (later) |

So Sleep Timer's "end of track" works **even if the Now Playing feature is off**, because it uses `MediaService` directly. Features share plumbing, not code.

A service counts its subscribers. With zero subscribers it's fully stopped: no observers, no memory held.

**b) Events.** Services publish typed events that anyone can listen to, without knowing who sends them:
- `PowerEvents.sleepRequested(by:)`, `PowerEvents.didWake`
- `MediaEvents.trackChanged`, `MediaEvents.playbackStateChanged`

**c) Slots.** A feature can put a small piece of UI into a named spot in another feature's UI, without either side knowing about the other. Core defines the slots:

| Slot | Shown in | Example contribution |
|---|---|---|
| `nowPlaying.popover.accessory` | The album art popover | Sleep Timer adds a "Sleep after this track" button |
| `menuBar.contextMenu` | Treble's right-click menu | Keep Awake adds "Keep awake for 1 hour" |
| `panel.footer` | Bottom of the main panel | (future) |

The "magic" examples, all built from those three parts:
- **Sleep Timer on + Now Playing on →** the album popover gets a "Sleep after this track" button.
- **Sleep Timer fires while Keep Awake is active →** `PowerService` ends the keep-awake session first, and Keep Awake's tile shows "Ended by sleep timer".
- **Only Sleep Timer installed →** it still offers "end of track". The button just doesn't appear in a popover that doesn't exist.

---

## 3. Architecture

### 3.1 Tech choices

| Choice | Decision | Why |
|---|---|---|
| Language | Swift 5.10+ (Swift 6 language mode where practical) | Native, fast, safe |
| UI | **SwiftUI** for views, **AppKit** for windows and the menu bar | SwiftUI's `MenuBarExtra` is too limited (no right-click, no width control, no slot for a live ticker). `NSStatusItem` + `NSPanel` gives full control, with SwiftUI views inside. |
| Project | Xcode app target (thin) + one local Swift package with many targets | Compiler-enforced isolation (§2.3) |
| Min OS | macOS 14.0 | Your OS; features needing newer APIs check at runtime (for example per-app volume needs 14.2) |
| Sandbox | **Not sandboxed** | Required for event taps, private APIs, power management. This means no Mac App Store. |
| Distribution | GitHub Releases + Homebrew cask, Sparkle for updates | Standard for open-source Mac utilities |

**Dependencies.** Keep this list tiny and MIT-only:
- [Sparkle](https://sparkle-project.org) — app updates
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkeys + the shortcut recorder UI (*optional; could be added in Phase 2*)

That's it. Launch at login uses Apple's built-in `SMAppService`.

### 3.2 Folder layout and dependency rules

```
Treble/
├── Treble.xcodeproj
├── App/                          ← thin: AppDelegate, wiring, feature list
├── Packages/TrebleKit/
│   ├── Package.swift
│   └── Sources/
│       ├── TrebleCore/           ← Module protocol, registry, settings, permissions,
│       │                            events, slots, shared UI (tiles, popover chrome)
│       ├── Services/
│       │   ├── MediaService/     ← the ONLY place that touches the private Now Playing API
│       │   ├── PowerService/
│       │   └── AudioService/
│       └── Modules/
│           ├── NowPlaying/
│           ├── SleepTimer/
│           ├── KeepAwake/
│           └── Scroll/
│   └── Tests/
├── PLAN.md                       ← this file
├── docs/
│   ├── ADDING_A_MODULE.md        ← contributor guide
│   └── TESTING.md                ← manual test checklists
├── LICENSE
└── README.md
```

**Dependency rules (enforced in `Package.swift`):**

```
App ──► Modules ──► Services ──► TrebleCore
          ✗ Modules never import other Modules
          ✗ Services never import Modules
          ✗ TrebleCore imports nothing of ours
```

A feature only knows Core and the services it lists. Deleting `Modules/Scroll/` and removing one line from the app's feature list builds a working app with no scroll feature. That's the isolation test, and it gets checked in CI.

### 3.3 The Module contract

Every feature implements one small protocol. This is a sketch; it gets finalized in Phase 0:

```swift
@MainActor
protocol TrebleModule: AnyObject {
    // Identity (shown on the "Choose your features" screen)
    static var id: String { get }              // "sleepTimer"
    static var name: String { get }            // "Sleep Timer"
    static var summary: String { get }         // "Fade out, pause, and sleep your Mac"
    static var symbol: String { get }          // SF Symbol, "moon.zzz"
    static var permissions: Set<Permission> { get }

    init(context: ModuleContext)               // gets services, settings, events, slots

    func start()                               // feature turned on
    func stop()                                // feature turned off: MUST release everything

    var status: ModuleStatus { get }           // running / needsPermission / unavailable / failed

    // Optional UI pieces; nil means "this feature doesn't have one"
    var tile: TileDescriptor? { get }          // tile in the main panel
    var menuBarItem: MenuBarItemDescriptor? { get }  // its own menu bar item
    var settingsView: AnyView { get }          // its page in Settings
}
```

- **Placement**, per feature, chosen in Settings: *Off* · *Panel tile* · *Own menu bar item* · *Both*.
- `ModuleContext` hands each feature a **namespaced settings store**, so Sleep Timer's keys are `sleepTimer.*` and can't clash with another feature's.
- `stop()` is tested: after stopping, a feature must have zero timers, observers or assertions left (§7, Phase 0 tests).

### 3.4 UI shell

- **Status items:** `NSStatusItem`, one for the main panel plus one per feature placed in the menu bar. If you put everything in the panel, Treble uses exactly one menu bar slot.
- **Panel:** a non-activating `NSPanel` with `NSVisualEffectView` (`.popover` / `.menu` material) to match Control Center. It closes on outside click and Esc, and it's keyboard navigable.
- **Settings window:** a standard window with a System Settings–style sidebar (General, Features, then one page per enabled feature, then About).

---

## 4. Performance budget

These numbers are **targets we measure**, not guesses. Every release is checked against them (see `TESTING.md`).

| Metric | Target | How we measure |
|---|---|---|
| CPU at idle (nothing playing, panel closed) | ~0.0% average | Activity Monitor, `top -pid` |
| Idle wakeups | < 1 per second | Activity Monitor → Energy, "Idle Wake Ups" |
| Energy impact | "Low" / under 1 | Activity Monitor → Energy |
| Memory, Phase 1 features all on | < 40 MB | Activity Monitor, Instruments Allocations |
| Memory, only Now Playing on | < 30 MB | same |
| Launch to menu bar icon | < 0.5 s | stopwatch / Instruments |
| App size | < 10 MB | Finder |

**Rules that keep us inside the budget:**
- **No polling.** Track changes, wake/sleep, device connects and app launches all come from system notifications.
- **Animate only when visible.** The progress bar and countdowns only tick while their popover or panel is open. Menu bar countdowns update **once per minute**, and once per second only in the final minute.
- **Coalesced timers.** Every timer gets a tolerance (leeway) so macOS can batch wakeups.
- **Images sized to need.** Album art is downscaled to the largest size shown (~600 px). Only the current artwork is kept; nothing is cached on disk.
- **No marquee by default.** A constantly scrolling ticker burns CPU. Titles are truncated, and the ticker scrolls **on hover only** (off under Reduce Motion).
- **Diff before updating.** The system sends now-playing updates several times per track. We debounce (~150 ms) and only redraw if something actually changed.
- **Lazy everything.** Features not enabled are never created. Services with zero subscribers are fully stopped.

---

## 5. Feature specs — Phase 1

Each spec lists **behavior**, then **nuances** (the small things that make it feel built in), then **how it works**.

### 5.1 Keep Awake (the first feature built: simplest, proves the architecture)

**Behavior**
- Durations: 15 min · 30 min · 1 h · 2 h · 5 h · *Until a time…* · *Indefinitely*
- Conditions: *While [app] is running* (for example, keep awake until a render or download app quits)
- Option: **Keep display on** (off by default, so the screen can sleep while the Mac keeps working; saves battery)
- Icon: an outlined cup when off, filled when active. The tile shows the time left.

**Nuances**
- **Uses the wall clock, not a countdown.** "Until 3:00 PM" is still correct after the lid was closed or the clock changed.
- **Battery safety:** an option to *stop when battery falls below 20%* (default on), and *only while plugged in* (default off). It sends a notification when it stops for this reason.
- **Lid closed:** macOS sleeps on lid close no matter what normal apps ask. The exception is clamshell mode (power + external display), which already works natively. Keeping a Mac awake with the lid closed on battery needs a root helper, so it's deferred to Phase 3, alongside the charge-limit helper. The UI says so honestly instead of silently failing.
- **Never stuck awake.** macOS ties "keep awake" requests to the process, so if Treble quits or crashes, the request disappears automatically and the Mac sleeps normally.
- **Visible to the system.** The request is named, for example "Treble: Keep Awake until 3:00 PM", so `pmset -g assertions` in Terminal shows exactly why the Mac is awake.
- The sleep timer ends a keep-awake session cleanly (see §2.4).
- *Indefinitely* shows a subtle reminder in the tile after 8 hours, so it doesn't get forgotten for days.

**How it works:** IOKit power assertions through `PowerService` (`PreventUserIdleSystemSleep`, or `PreventUserIdleDisplaySleep` when "keep display on" is set). App-quit watching uses `NSWorkspace` notifications, which are event-driven.

---

### 5.2 Now Playing (the Jukebox feature)

**Behavior**
- **Menu bar ticker:** shows `♪ Title — Artist`. Format options: *Title — Artist* · *Title only* · *Artist — Title* · *Icon only*.
- **Click → popover:** large album art, title, artist, album, a draggable progress bar, previous / play-pause / next, and the source app's icon (click to open that app).
- **Panel tile:** compact art + title + controls.
- **Ticker gestures:** left-click opens the popover · right-click opens a menu · **middle-click toggles play/pause** · **scroll over the ticker changes volume** (option).

**Nuances**
- **Width cap.** The ticker has a max width (default ~160 pt) because menu bar space on a notched Air is precious. When macOS runs out of room it hides status items behind the notch, so a long title must never push other icons away.
- **Paused and stopped states:** paused shows a dimmed ticker. After N minutes paused (default 5) it collapses to icon only. With nothing playing it shows icon only, or hides completely (option).
- **Source filter:** an allow/block list of apps, so a muted YouTube tab in Chrome doesn't take over the ticker. Default: show everything.
- **Artwork arrives late.** Apps often send the title first and artwork a moment later. We show a placeholder and cross-fade, so it never flashes empty-then-full.
- **Progress without polling.** macOS reports elapsed time *at a timestamp* plus playback rate. We compute `elapsed = reported + (now − timestamp) × rate` only while the popover is open. Zero cost when closed.
- **Seeking** writes back to the player. Apps that don't support seeking get a read-only progress bar.
- **Podcasts / audiobooks:** if there's no artist, show the album or app name. If there's no duration (live streams), hide the progress bar and show "Live".
- **Long titles:** truncate in the middle for the ticker when needed ("Symphony No. 9 … IV. Presto"). The full text is in the popover and the tooltip.
- **Accessibility:** VoiceOver labels on every control. Reduce Motion means no hover scroll; Reduce Transparency means a solid background.
- **Slot:** the popover has an accessory spot where other features (Sleep Timer) can add buttons.
- **Optional:** a subtle tint from the album art's average color in the popover background. It's computed once per track, so it's cheap.

> **As built (Phase 1):** `MediaService` uses Spotify's and Apple Music's own broadcasts plus AppleScript, not MediaRemote. See §7, Phase 1 item 2. The text below is the original design, kept for the later MediaRemote adapter.

**How it works:** everything goes through `MediaService`, the **only** code that touches Apple's private `MediaRemote` framework. It's loaded at runtime, and if any function is missing the feature becomes `unavailable` instead of crashing. Internally it's a `NowPlayingProvider` protocol, so the second provider for macOS 15.4+ (the separate-process bridge) is built in Phase 1 alongside it, without touching the feature. On 15.4+ the direct provider is blocked by Apple, so the bridge is what most users (including the main development Mac) will actually run.

---

### 5.3 Sleep Timer

**Behavior**
- **When:** 15 min · 30 min · 45 min · 1 h · custom · *at a time…* · **end of this track** · **when this album ends**
- **Then** (checkboxes, all on by default):
  1. ☑ Fade out audio over the last *60 s* (30 s / 60 s / 2 min / off)
  2. ☑ Pause playback
  3. ☑ Then: **Sleep the Mac** · Turn off display · Do nothing
- **Snooze:** +10 min from the tile, the menu bar or the warning notification
- **Countdown** in the tile, and optionally in the menu bar (`☾ 28m`)

**The ending sequence**, in order:
1. **T−60 s:** a "Going to sleep in 1 minute" notification with **Cancel** and **+10 min** buttons.
2. **Fade:** lower system volume smoothly over the fade window.
3. **Pause** the now-playing app.
4. **Restore the volume** to where it was. *Critical:* otherwise you wake up tomorrow to a silent Mac and think something's broken.
5. **End any Keep Awake session**, with a note in its tile.
6. **Sleep** (or turn off the display).

**Nuances**
- **Are you still there?** If you've used the keyboard or mouse in the last 60 seconds when the timer ends, it **pauses but doesn't sleep** and shows "Timer ended. Sleep now?" (option, default on). It never puts the Mac to sleep while you're actively typing.
- **Waking up after the deadline:** if the Mac slept on its own and wakes after the timer's end time, the timer is **discarded silently**. It never sleeps the Mac right as you open the lid.
- **End of track:** a timer is scheduled for *remaining time − fade*. Pausing the music pauses the countdown, seeking recalculates it, and skipping re-targets the new track (option: "the track playing when I set it" vs "whatever is playing"). Backup: if the track changes before we pause, pause immediately (at most a fraction of a second of the next song).
- **When album ends:** the API doesn't say "last track", so we watch for the **album changing**. When the next track's album differs (including Spotify's autoplay after an album), we pause immediately. Labelled honestly as "When the album changes".
- **Nothing playing?** Skip the fade and pause steps and go straight to sleep or display-off.
- **Outputs without software volume** (some HDMI/DisplayPort audio): skip the fade, then pause.
- **Only one timer** at a time. Setting a new one replaces the old one, with a brief confirmation in the tile.
- **Wall clock,** same as Keep Awake.
- **Doesn't fight the user:** if you press pause yourself during the fade, the fade stops and the volume is restored immediately.
- Works **without the Now Playing feature** enabled, via `MediaService` (see §2.4).

**How it works:** `PowerService` for sleep (`pmset sleepnow`, which works without admin rights; to be confirmed in the Phase 1 prototype, with the IOKit sleep call as the fallback). `AudioService` for volume ramp and restore. `MediaService` for pause and track info. Idle time comes from the system's "seconds since last input" counter, which needs no permission.

---

### 5.4 Scroll (separate direction for mouse and trackpad)

**Behavior**
- Two settings: **Trackpad: Natural / Standard** and **Mouse: Natural / Standard**, set independently. Optionally separate horizontal from vertical.
- Leave macOS's own "Natural scrolling" **on** (best for the trackpad). Treble just flips the mouse. No toggling system settings back and forth, ever.
- Tile shows the current state; click to swap.

**Nuances**
- **Telling devices apart:** a regular wheel mouse sends "line" scrolls; a trackpad sends "continuous" scrolls with gesture phases. That gives a reliable split for v1.
- **Magic Mouse caveat:** it sends continuous scrolls like a trackpad, so in v1 it's treated as a trackpad, noted in Settings. A finer detector (watching for trackpad touch events, as other open-source tools do) is a Phase 2 refinement.
- **Inverted consistently:** a scroll event carries its distance in several fields (line, pixel, fixed-point). All of them are flipped together, or apps disagree about which way you scrolled.
- **Never break scrolling:** macOS disables a slow event handler. Ours is a few lines, runs on its own thread (so a busy UI never lags your scrolling), and re-enables itself automatically if macOS switches it off.
- **Permission:** needs **Accessibility**. Treble explains why *before* the system prompt, then detects when you grant it (no restart needed).
- **Turning it off removes the handler completely.** Zero cost when disabled.

**How it works:** a `CGEventTap` for scroll-wheel events, flipping the delta fields for non-continuous events.

---

## 6. App-wide behavior and nuances

### 6.1 Menu bar and panel
- One Treble icon by default. Features placed in the menu bar get their own items, ordered by you.
- Panel: tiles from enabled features, rearranged via *Edit tiles* (drag to reorder; 1- or 2-column width per tile).
- Esc / outside click closes. Arrow keys + Space navigate tiles.
- Optional global hotkey to open the panel.

### 6.2 Settings
- System Settings–style sidebar: **General** (launch at login, updates, hotkey) · **Features** (the installer-style list) · one page per enabled feature · **About**.
- No Dock icon, which has a side effect: opening Settings would normally appear *behind* other windows. We briefly bring the app forward (and show it in Cmd-Tab) while Settings is open, then go back to menu bar only.

### 6.3 Permissions
- Asked **only** when a feature that needs it is turned on, with a one-sentence explanation first.
- Treble detects the grant without a restart.
- If you revoke a permission later, that feature's status flips to `needsPermission` with a "Fix" button. Nothing crashes.

### 6.4 Lifecycle
- Launch at login via `SMAppService` (shows correctly under System Settings → Login Items).
- Handles sleep/wake, display changes, fast user switching and menu bar auto-hide.
- **Crash relaunch:** a plain login item (`SMAppService.mainApp`) is *not* relaunched after a crash. Option: register Treble as a tiny launch agent with `KeepAlive` (`SMAppService.agent`), so macOS restarts it within seconds. Decide in Phase 0 (see §13).

### 6.5 Look and feel
- System materials, SF Symbols, system accent color, light/dark automatic.
- Respects **Reduce Motion**, **Reduce Transparency** and **Increase Contrast**.
- All text in a String Catalog from day one (cheap now, enables translations later).

### 6.6 Privacy and updates
- No telemetry. No network except the Sparkle update check (opt-in on first launch, signed updates) and, while Now Playing shows a Spotify song, fetching that song's cover from Spotify (no cookies, no disk cache).
- Settings stored locally in UserDefaults. Export/import settings in Phase 2.

---

## 7. Phases and milestones

Each phase ends with something you can actually use. Within a phase, every step is small enough to finish and test on its own.

### Phase 0 — Foundation *(no visible features yet; the most important phase)* — ✅ built 2026-11-08

**Outcome:** builds and runs; 12 unit tests pass; isolation check passes and catches violations; the shell builds with zero modules. Measured idle: **0.0% CPU, 23 MB, ~1 wakeup per 5 s** (Sample only). Decisions made while building:
- **XcodeGen** (`project.yml`) generates the Xcode project, so no hand-edited `.pbxproj` and no merge conflicts. The `.xcodeproj` isn't committed.
- **Signing:** `Config/Signing.xcconfig` (shared, ad-hoc by default) + `Config/Local.xcconfig` (personal team ID, ignored by Git).
- **Shell is its own target** (`TrebleShell`), depending only on Core. The app target just lists feature types.
- **Core cleans up for features:** subscriptions, slot contributions and menu bar labels handed out through the context are removed on stop, so even a sloppy feature is released (tested).
- **Minimal app menu** so Cmd-C/V/W/Q work in Treble's windows (menu bar apps don't get one by default).
- **`UIDesignRequiresCompatibility`** set, so builds against the macOS 26 SDK keep the pre–Liquid Glass look on macOS 26.
- **Single instance:** a second copy of Treble activates the first and quits.
- **Still open:** crash auto-relaunch (§13 #6), moved to Phase 1. Visual check of the panel and Settings by hand (`docs/TESTING.md`).

Original steps:
1. Dev setup: Xcode, free Apple ID signing, Git + GitHub repo, MIT license, README (§10)
2. Create the app target + `TrebleKit` package with the folder layout from §3.2
3. App shell: menu bar icon, empty panel, Settings window with sidebar
4. `TrebleCore`: Module protocol, module registry, namespaced settings, permission helper, events, slots
5. "Choose your features" first-launch screen + Settings → Features page
6. Launch at login
7. Tests: a dummy module that proves `start()`/`stop()` leave nothing behind
8. **Isolation check:** remove the dummy module from the app and confirm it still builds

✅ *Done when:* the app launches to a menu bar icon, you can enable or disable a dummy feature, and idle CPU is ~0%.

### Phase 1 — Daily drivers *(→ release v0.1)*
1. ✅ **Keep Awake** + `PowerService` (built 2026-11-08). Simplest feature; proved the module system end to end.
   - Logic lives in a testable `KeepAwakeController` with a fake clock, battery and apps (21 tests), plus a real `pmset` check.
   - Core gained `own(_:)` (features hand Core their timers and observers to cancel on teardown), `TrebleTimer`, `trebleObserve`, and `TrebleNotifications` (asks for notification permission only when first needed).
   - System observers (wake, clock change, power, app quit) run only while a session is active. The menu bar countdown ticks once a minute, only if shown.
   - Features added in an update start **off** for existing users. A "New features" prompt is a later nicety.
2. ✅ **Now Playing** + `MediaService` (built 2026-11-08). **Changed approach:** instead of the private MediaRemote API (blocked on 15.4+) and a separate-process bridge, it listens to the broadcasts Spotify and Apple Music send on every track change, play and pause.
   - Showing the song needs **no permission** and no polling, and works on every macOS version. Verified live with Spotify 1.3.6 on macOS 15.7.
   - Controls, exact position and sharper artwork use AppleScript, which asks once per app ("Allow Treble to control Spotify?"), only when a control is first used. Scripts never launch an app and time out after 2 s.
   - Spotify artwork without that permission comes from Spotify's public oEmbed endpoint (300 px). With it, AppleScript gives the 640 px cover. Downsampled to 600 px, held in memory only.
   - Music doesn't broadcast position, so it's extrapolated from play/pause times (and re-read when the popover opens, if allowed).
   - Two apps with tracks loaded: the one that most recently started playing wins.
   - Core gained `MenuBarLabel.maxWidth / isDimmed / isHidden / toolTip` and `handleMenuBarClick(.middle)`.
   - **Not covered:** browsers (YouTube, etc.) and other players. That needs the MediaRemote adapter, now a later item (§8).
3. **Sleep Timer** + `AudioService`: the ending sequence, then the nuances, then the Now Playing slot button
4. **Scroll**: event tap, then permissions flow, then tile
5. Performance pass against §4. Manual test checklists in `TESTING.md`.
6. Release v0.1: GitHub Release + install instructions

✅ *Done when:* you've used it for a week instead of Jukebox and Scroll Reverser and nothing annoyed you.

### Phase 2 — Power features
- Stats (CPU, RAM, disk, network, temperature, thermal state) + battery health readout
- Audio: output switcher, auto-switch rules, per-device volume memory
- Window snapping (drag to edges + shortcuts). Lower priority: macOS 15+ has built-in tiling, so this mainly helps macOS 14 users and adds shortcuts Apple's lacks.
- Quick toggles tile (hidden files, dark mode, Do Not Disturb, Bluetooth)
- Global hotkeys, settings export/import, Homebrew cask, Sparkle updates

### Phase 3 — Hard mode
- Charge limit + lid-closed keep-awake (one shared, minimal privileged helper)
- Per-app volume (macOS 14.2+)
- Menu bar icon hiding (notch-safe)
- Desktop now-playing widget
- MediaRemote adapter for browsers and other players (macOS 15.4+ needs the separate-process workaround)
- Clipboard history, copy text from screen, Cmd-Tab previews

---

## 8. Later features (backlog)

| Feature | Difficulty (1–3) | Notes |
|---|---|---|
| Media key routing (stop play key launching Apple Music) | 2 | |
| Smooth scrolling + no acceleration for mice | 2 | Extends the Scroll feature |
| Mouse side buttons → back/forward everywhere | 2 | Extends the Scroll feature |
| Middle-click on trackpad | 2 | |
| Click Dock icon to minimize | 2 | |
| Hold Cmd-Q to quit | 1 | |
| External display brightness (DDC) | 2 | |
| Color picker | 1 | |
| Scratchpad note | 1 | |
| Keep Awake: "while CPU is busy" / "while downloading" | 2 | |

---

## 9. Non-goals

What Treble will **not** do, to stay simple:
- No notch / Dynamic Island UI
- No third-party plugin system (features are compiled in; contributors add them via pull requests)
- No accounts, cloud sync or telemetry
- No themes engine (it follows macOS)
- No Mac App Store version (sandboxing would break most features)

---

## 10. Developer setup and gotchas

Written for a beginner-to-intermediate Swift developer.

**Setup**
1. Install Xcode from the App Store; open it once to install components.
2. Xcode → Settings → Accounts → add your Apple ID. A free account is enough for development.
3. Use **"Apple Development"** signing with your personal team, **not** "Sign to Run Locally". (See the first gotcha.)
4. Git + GitHub repo from day one; commit after every working step.

**Gotchas we already know about**
- 🔑 **Permissions reset on every build** if the app is signed ad-hoc ("Sign to Run Locally"): macOS sees each build as a new app and forgets the Accessibility grant. Fix: sign with your Apple Development certificate. If permissions get confused anyway: `tccutil reset Accessibility <bundle-id>`.
- 🔒 **Private APIs** (MediaRemote) only live in `MediaService`. Never call them from a feature.
- 🧵 **Main thread:** UI updates on the main thread (the `@MainActor` mark helps the compiler check this). The scroll handler runs on its own thread.
- 📦 **Releasing to others** needs a paid Developer ID ($99/yr) for notarization, or users must right-click → Open the first time. Fine to postpone until v0.1 is ready.
- 💥 **Compiler crash:** Swift 6.2 crashes on key paths to static members of feature types (`types.map(\.id)`). Use a closure instead: `types.map { $0.id }`.
- 🧪 **Measuring:** Activity Monitor's Energy tab and Xcode Instruments (Time Profiler, Allocations) are how we check §4.

---

## 11. Glossary

| Term | Meaning |
|---|---|
| **AppKit** | Apple's older, lower-level UI framework; we use it for windows and the menu bar |
| **SwiftUI** | Apple's newer UI framework; we use it to draw the actual views |
| **NSStatusItem** | An item in the menu bar |
| **NSPanel** | A floating window type; our main panel |
| **Swift package / target** | A unit of code the compiler builds separately; how we isolate features |
| **Event tap** | A hook that sees (and can modify) input events like scrolling |
| **Power assertion** | A request to macOS: "please don't sleep right now" |
| **Private framework** | An Apple API that isn't officially public; can change without notice |
| **Sandbox** | Apple's app restrictions; we can't use it because our features need system access |
| **Notarization** | Apple scanning your app so macOS opens it without warnings |
| **Privileged helper** | A tiny separate program that runs with admin rights for one specific job |

---

## 12. Naming

**Decided: Treble** (2026-11-08).

- **Meaning:** treble is the top of the musical range, and the app lives at the top of your screen. It hints at the music features without restricting the app to music.
- **Name check (2026-11-08):** no Mac app called Treble on GitHub, Homebrew or the web. The Homebrew cask name `treble` is free. The only naming noise is Android's "Project Treble", which is a system architecture, not an app.
- **Before the first public release:** check the Mac App Store, a domain, and the GitHub repo name; reserve the Homebrew cask name when publishing.
- **Bundle ID:** `io.github.<your-github-username>.Treble` (set in Phase 0).

Names considered and dropped: Ledge, Sill, Tuck, Transom, Lintel, Brim, Marquee, Headroom, Crest, Barkeep, Cornice, Canopy, Perch, Topside (all already used by small Mac menu bar or notch apps); Mantel (a similar combined menu bar app); Encore (a Discord app); Overture (an established music notation app); Overtone (a known music coding toolkit). Shortlisted but not picked: Descant, Awning, Gable, Minuet.

---

## 13. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| 1 | Name | ✅ **Treble** (decided 2026-11-08) |
| 2 | License | **MIT**: simplest, most contributor-friendly. GPL-3 would let us copy code from GPL projects like Ice/AltTab, but forces the whole project to stay GPL. We'll learn from those projects, not copy from them. |
| 3 | Scroll engine in-process or helper | Start in-process on its own thread; move to a helper only if we measure stutter |
| 4 | Sleep timer default "then" action | Sleep the Mac |
| 5 | Updates check default | Ask on first launch |
| 6 | Auto-relaunch after crash | Yes, via a `KeepAlive` launch agent (verify it plays well with "launch at login" in Phase 0) |
