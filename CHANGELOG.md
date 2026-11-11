# Changelog

Notes for 0.1.2 to 0.1.6 were moved here from the original setup guide. The entries for 0.1.7 and 0.2.0 are summarized from the commit history. No notes were recorded for 0.1.4.

## 0.2.0 (build 12)

- Signed in-app updates through Sparkle. Firefly checks the update feed at launch and at most once an hour, and shows an Update available button when a newer version exists. Installation always starts from that button.
- Refined battery visuals.
- Firefly is now English-only. The Turkish interface, the language setting and the Turkish guides were removed.
- Fixed a crash at launch in hardened runtime builds: the ad-hoc signed app now carries the library validation entitlement it needs to load the bundled Sparkle framework.

## 0.1.7 (build 8)

- Removed the backdrop behind the mascot.
- Added a drag-to-install disk image, built from the release ZIP and attached to the GitHub release.

## 0.1.6

- The tab strip scrolls horizontally, and swiping left or right inside the panel changes tabs.
- Optional battery reports over cellular: choose an iCloud file under Settings → Battery reports over cellular. See the [shortcut setup steps](Resources/DeviceTools/MobileSetup.html). The percentage only updates after the shortcut has run on the iPhone and the file has synced.

## 0.1.5

- Over Wi-Fi, Firefly waits up to 15 seconds for a delayed battery response.
- After the quick attempts are used up, Firefly checks about once a minute whether the paired device is back in the Mac's USB or network device list. No new session is opened while the device is not listed. Checks stop while the Mac sleeps.
- The last 40 connection events are recorded in `connection-events.txt` inside `Application Support/Firefly`, with only the time, the result and the connection type.

## 0.1.3

- Readings come through an open session with the paired iPhone. This can keep working while the screen is locked, as long as the iPhone offers its network service. If iOS stops Wi-Fi access completely, no live reading is possible. When the phone is announced on the network again, Firefly retries the connection. The first connection may require unlocking the phone.
- Between successful reads Firefly waits 1 second while the panel is open, 3 seconds while it is closed, and 10 seconds while it is closed and the Mac is in Low Power Mode. The device's response time is added to that interval.
- The logo is at most 22 points so that it fits the menu bar.
- The icon colour change takes 0.24 seconds. No animation is used when Reduce Motion is on.

## 0.1.2

- The Battery tab shrinks to fit its content.
- The menu bar icon turns system red when a current reading is below 20%, and system green when the level is 20% or above and charging. Otherwise it uses the standard menu bar colour.
