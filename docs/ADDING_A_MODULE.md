# Adding a feature

Every Treble feature is a **module**: its own Swift package target that only knows `TrebleCore`. It never imports another module.

## 1. Copy the sample

```bash
cp -R Packages/TrebleKit/Sources/Modules/SampleModule Packages/TrebleKit/Sources/Modules/MyFeature
mv Packages/TrebleKit/Sources/Modules/MyFeature/SampleModule.swift \
   Packages/TrebleKit/Sources/Modules/MyFeature/MyFeature.swift
```

Rename the class and change `id`, `name`, `summary` and `symbol`. **The `id` is permanent**: saved settings are stored under it.

## 2. Register the target

In `Packages/TrebleKit/Package.swift`, add a product and a target:

```swift
.library(name: "MyFeature", targets: ["MyFeature"]),
// ...
.target(name: "MyFeature", dependencies: ["TrebleCore"], path: "Sources/Modules/MyFeature"),
```

## 3. Add it to the app

In `project.yml`, add the dependency:

```yaml
- package: TrebleKit
  product: MyFeature
```

In `App/FeatureList.swift`, import it and add one line to the list. Then run `xcodegen`.

## The contract

```swift
public final class MyFeature: TrebleModule {
    public static let id = "myFeature"
    public static let name = "My Feature"
    public static let summary = "One short line"
    public static let symbol = "sparkles"          // SF Symbol

    // Optional:
    // static let permissions: Set<Permission> = [.accessibility]
    // static let defaultPlacement: Placement = .panel   // .panel, .menuBar, .both
    // static let tileSize: TileSize = .small            // .small or .wide

    public init(context: ModuleContext) { ... }
    public func start() { ... }   // turned on
    public func stop() { ... }    // turned off: release what start() created

    public var tile: AnyView? { ... }           // panel tile content
    public var menuBarPopover: AnyView? { ... } // defaults to the tile
    public var settingsView: AnyView? { ... }   // its page in Settings
}
```

### What the context gives you

| API | Use it for |
|---|---|
| `context.settings` | Your own saved settings, namespaced by your `id` |
| `context.setStatus(_:)` | Report `.unavailable("why")` or `.failed("why")` |
| `context.setMenuBarLabel(_:)` | Symbol and short text for your menu bar item |
| `context.subscribe(to:_:)` | Listen for events (like `PanelVisibilityChanged`) |
| `context.publish(_:)` | Broadcast an event |
| `context.contribute(to:_:)` | Add UI to a slot (like `.panelFooter`) |
| `context.own(_:)` | Hand over a timer, observer or service subscription for Treble to cancel when you're turned off |

Helpers in TrebleCore: `TrebleTimer.once(at:tolerance:_:)` and `.repeating(every:tolerance:_:)`, `NotificationCenter.trebleObserve(_:_:)`, `TrebleNotifications.post(title:body:)`.

### Using a Service

Shared system plumbing lives in `Sources/Services/` (for example `PowerService` for keep-awake requests and battery state). Add it to your target's `dependencies` in `Package.swift` and `import` it. Services never know about modules.

For logic worth testing, put it in a controller that takes an environment struct of closures (clock, system calls), like `KeepAwakeController`. Tests then pass fakes. See `Tests/KeepAwakeTests`.

Subscriptions, slot contributions and the menu bar label are **removed automatically** when your feature is turned off. In `stop()`, release only what you created yourself: timers, system observers, power assertions and so on.

## Rules

1. **Never import another module.** To share something, put it in `TrebleCore` or a Service. `scripts/check-isolation.sh` enforces this.
2. **No polling.** React to system notifications. Give timers a tolerance.
3. **Animate only when visible.** Listen for `PanelVisibilityChanged`.
4. **Fail small.** Never force-unwrap or crash. Report `.unavailable` or `.failed` instead.
5. **Capture `self` weakly** in closures you hand to the context: `{ [weak self] in ... }`.

## Before opening a pull request

```bash
cd Packages/TrebleKit && swift test
scripts/check-isolation.sh
```

Then turn your feature on and off a few times and check Activity Monitor: CPU should return to 0% when idle.
