# Firefly

Native macOS menu bar app that shows a paired iPhone's battery percentage and
charging state over USB or Wi-Fi. Current version: 0.2.0 (build 12).
Repository: https://github.com/pankuccii/Firefly (`main`).

## Working agreement

- Talk to the maintainer in **Turkish**. Everything written into the project
  (code, comments, commit messages, docs, script output) is **English**.
- The app UI stays bilingual (Turkish and English). Never delete Turkish UI
  translations.
- Ask before `git commit` and before `git push`.
- After every change run `swift test`; when app, widget, plist or project files
  changed, also build the `Firefly` scheme with `xcodebuild`.
- Never fabricate measurements. The app strictly separates a **live reading**
  from the **last known reading** (see "Data honesty"). Keep that separation in
  code, UI text, docs and the marketing site.

## Hard rules

- **Sparkle signing key**: the private EdDSA key lives only in the login
  Keychain (account `com.firefly.battery.updates`). Never export it, print it,
  or write it to a file. Never change the `SUPublicEDKey` value in
  `Resources/Info.plist` or `Widget/HostInfo.plist`.
- **Build number**: every release must increase `CFBundleVersion`, in
  `Resources/Info.plist`, `Widget/HostInfo.plist` and `Widget/Info.plist`
  together (same for `CFBundleShortVersionString`).
- **Appcast**: never hand-edit `docs/updates/appcast.xml`.
  `Scripts/prepare-update.sh` generates it.
- **Entitlements**: the menu bar app must be signed with
  `Resources/Firefly.entitlements` (`disable-library-validation`). Ad-hoc
  signatures have no Team ID, so without it the hardened runtime refuses to
  load `Sparkle.framework` and the app aborts at launch. Keep it for as long as
  builds are ad-hoc signed.
- **Bundled binaries**: do not touch the binaries under
  `Resources/DeviceTools/bin` and `Resources/DeviceTools/lib`, or anything in
  `ThirdParty/` and `Vendor/`, without asking first.
- **Targets**: Apple Silicon (`arm64`) and macOS 27 only. The menu bar app is
  the main distribution. There is no Developer ID signature and no
  notarization; builds are ad-hoc signed.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/FireflyCore/` | Platform logic with no UI. `Battery.swift` (observation model, parsing, freshness, alerts, schedule, history, iCloud report parsing), `Transport.swift` (process runner, tool lookup, `BatteryService`, persistent device session), `Insights.swift` (charging sessions and time-to-full estimate), `WidgetSnapshot.swift`, `Language.swift` (initial UI language from the system language). |
| `Sources/FireflyApp/` | SwiftUI/AppKit menu bar app. `FireflyApp.swift` (status item, popover, Sparkle wrapper), `Model.swift` (`AppModel`: polling, retry state machine, notifications, persistence), `Views.swift` (popover pages). |
| `Tests/FireflyCoreTests/` | XCTest suite for `FireflyCore` (23 tests). |
| `DeviceSession/session.c` | C helper that keeps one authenticated lockdown session open. Built by `DeviceSession/build.sh` into `Resources/DeviceTools/bin/firefly-session`. |
| `Resources/DeviceTools/` | Bundled libimobiledevice 1.4.0 tools and dylibs, plus `MobileSetup.html` and `MobileSetup.tr.html` (iCloud shortcut guide opened from Settings in the UI language). |
| `Resources/en.lproj`, `Resources/tr.lproj` | `InfoPlist.strings` with the localized permission text. `Info.plist` itself carries the English text. |
| `ThirdParty/` | Licenses, source archives and `manifest.json` (versions, URLs, checksums) for the bundled libraries. Shipped inside the app. |
| `Vendor/Sparkle/` | Pinned Sparkle 2.10.1 framework and its `bin/` tools (`generate_keys`, `sign_update`). |
| `Widget/` | Optional WidgetKit extension and the host app's `HostInfo.plist` / entitlements. |
| `docs/` | GitHub Pages site (Three.js 3D iPhone in `firefly-3d.js`), `docs/experience/` (experimental page), `docs/updates/appcast.xml` (Sparkle feed). |
| `Scripts/` | `build-update.sh`, `prepare-update.sh`, `build-dmg.sh`, `installer/` (DMG artwork and Finder layout). |
| `.github/workflows/firefly-dmg.yml` | Builds a DMG from the release ZIP and attaches it to the published release. |
| `SETUP.md`, `CHANGELOG.md` | English setup guide and release notes. The Turkish guide is `docs/tr/SETUP.md`; keep both guides in step. |
| `Documentation/` | `AssetAudit.txt` is tracked. The verification log and device test JSON files are git-ignored local records. |

## Build and test

```sh
swift test                      # FireflyCore only (SwiftPM, library target)
xcodebuild -project Firefly.xcodeproj -scheme Firefly -configuration Debug build
```

- `Package.swift` defines only the `FireflyCore` library and its tests. The app
  is **not** a SwiftPM target.
- `Firefly.xcodeproj` compiles `Sources/FireflyCore/*.swift` directly into the
  app target, which is why app sources use `#if canImport(FireflyCore)`. A new
  Core file must be added to the Xcode targets by hand (`Firefly`,
  `FireflyWithWidgets`, and `FireflyWidget` if the widget needs it).
- `project.pbxproj` is stored as an **XML plist**, not the usual OpenStep
  format. Edit carefully and re-check with `plutil -lint`.
- `Resources/DeviceTools` and `ThirdParty` are folder references: files added
  there are bundled without project changes.
- Schemes: `Firefly` (menu bar app, `Resources/Info.plist`) and
  `FireflyWithWidgets` (host app with `Widget/HostInfo.plist` plus the
  `FireflyWidget` extension; needs a development team and the App Group
  `$(DEVELOPMENT_TEAM).com.firefly.battery.shared`).
- `DeviceSession/build.sh` needs `IDEVICE_INCLUDE` and `PLIST_INCLUDE` header
  directories that are not in the repository, and it overwrites a bundled
  binary. Ask before running it.

## Architecture notes

- **Read path**: `AppModel.refresh()` → `BatteryService.readSession()` (long-lived
  `firefly-session` helper, one byte `R` in, two bytes out: percent and
  charging state) → falls back to `BatteryService.read()` (discovery with
  `idevice_id`, query with `ideviceinfo`, USB first, then Wi-Fi).
- **Device identity**: once a device is selected, Firefly never substitutes a
  different paired phone. Tests enforce this.
- **Retry**: up to 6 quick attempts with backoff, then a passive once-a-minute
  check of the device list (`.waiting`). Bonjour discovery
  (`_apple-mobdev2._tcp`), network recovery and Mac wake restart attempts.
- **Polling cadence**: 1 s between successful reads while the popover is open,
  3 s when closed, 10 s when closed in Low Power Mode.
- **Persistence**: preferences and alert state in `UserDefaults` (JSON under
  `preferences`, `alertState`); history in
  `~/Library/Application Support/Firefly/history.json` (7 days, max 12,000
  samples); last 40 connection events in `connection-events.txt`.
- **Localization**: UI strings are inline pairs, `model.t("Türkçe", "English")`,
  selected by `Preferences.language` (`"tr"` or `"en"`). There is no string
  catalog yet. With no stored preferences the language comes from
  `AppLanguage.initial()`: Turkish if the Mac's first preferred language is
  Turkish, English otherwise. A stored choice is never overridden. The
  development region is `en`.
- **Updates**: Sparkle with automatic checks disabled. The app probes the feed
  silently and shows an "Update available" button; installation is always
  user-initiated.

## Data honesty

- `Observation.freshness` drives everything: `fresh` (≤ 90 s), `recent`
  (≤ 5 min), `stale`, `disconnected`, `unavailable`. Only `fresh`/`recent`
  count as live.
- When not live, the menu bar shows `—` and the panel labels the value as the
  last known reading with its timestamp.
- History gaps are never interpolated. Charging estimates appear only with
  enough contiguous samples from the same device.
- iCloud shortcut reports are shown as timestamped reports, never as live
  readings, and never imply a charging state.

## Release flow

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in all three plists.
2. `Scripts/build-update.sh <out-dir>` first checks that the Keychain signing
   key matches the committed `SUPublicEDKey` in both plists and stops without
   changing anything if it does not. It then builds Release, ad-hoc signs with
   `Resources/Firefly.entitlements`, zips to
   `Firefly-VERSION-macOS-arm64.zip`, then calls `prepare-update.sh`, which
   verifies the signature and key and appends the item to
   `docs/updates/appcast.xml`.
3. Attach the ZIP to the `vVERSION` GitHub release and publish it. The workflow
   builds and uploads the DMG.
4. Publish `docs/` (GitHub Pages) so the feed goes live.

## Known risks and gaps

- The published appcast advertises 0.2.0, but as of 2026-11-11 there is no
  `v0.2.0` tag or public release, so the enclosure URL returns 404.
- `Preferences`, `ScheduleRule`, `AlertEngine` and `History` use synthesized
  `Codable`. Adding a non-optional property makes old stored data fail to
  decode, and `AppModel.init` then silently falls back to defaults (all user
  settings reset). New fields must be optional or get a custom decoder.
- Ad-hoc signatures change with every build, so macOS may re-ask for Local
  Network and notification permission after an update, and Gatekeeper blocks
  the first launch of a downloaded copy.
- `AppModel` (polling, retry and notification state machine) lives in the app
  target and has no tests. Only `FireflyCore` is covered.
- No CI runs `swift test` or builds the app; the only workflow packages a DMG.
- The widget build is verified, but the signed App Group, widget gallery and
  refresh behaviour are untested.
- `firefly-session` cannot be rebuilt from the repository alone, so the source
  and the committed binary can drift without detection.
- `Package.swift` declares macOS 14 while the app targets macOS 27.
- The repository has no license file for Firefly's own code.
- Long-running energy use at the 1 s / 3 s polling cadence is unmeasured.
