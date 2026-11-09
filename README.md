# Treble

A free, open-source macOS menu bar app that adds features that feel built in: now playing, a sleep timer, keep awake, separate scroll direction for mouse and trackpad, and more.

Pick only the features you want. Features you leave off don't run at all.

> **Status:** early development (Phase 1: Keep Awake and Now Playing work). See [PLAN.md](PLAN.md) for the full plan.

- macOS 14 Sonoma or later
- Native Swift (SwiftUI + AppKit), no Electron
- No tracking, no accounts

## Privacy

Treble has no analytics and no accounts. The only network request it makes today: when Now Playing shows a Spotify song, it fetches that song's album cover from Spotify, the same place the Spotify app gets it. Nothing is cached to disk.

## Building

You need Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen                 # creates Treble.xcodeproj from project.yml
open Treble.xcodeproj    # then press ⌘R
```

Run `xcodegen` again only after adding files to `App/` or changing `project.yml`. Code in `Packages/TrebleKit` is picked up automatically.

### Signing

Out of the box, builds are signed "to run locally". That works, but macOS treats every rebuild as a new app and forgets permissions like Accessibility. To avoid that, create `Config/Local.xcconfig` (it's ignored by Git):

```
DEVELOPMENT_TEAM = <your team ID>
CODE_SIGN_IDENTITY = Apple Development
```

A free Apple ID works: add it in Xcode → Settings → Accounts. To find your team ID:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

It's the `OU=` value.

## Project layout

```
App/                      Thin app target: startup and the list of features
Packages/TrebleKit/
  Sources/TrebleCore/     The module contract and shared parts (settings, events, slots)
  Sources/TrebleShell/    Menu bar, panel, Settings, onboarding
  Sources/Modules/        One folder per feature
  Tests/                  Unit tests
scripts/                  Checks, such as check-isolation.sh
docs/                     Contributor guides
```

Features never import each other. `scripts/check-isolation.sh` checks that rule.

## Tests

```bash
cd Packages/TrebleKit && swift test
scripts/check-isolation.sh
```

## Adding a feature

See [docs/ADDING_A_MODULE.md](docs/ADDING_A_MODULE.md).

## License

[MIT](LICENSE)
