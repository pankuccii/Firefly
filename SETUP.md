# Using Firefly

Firefly is built for Apple Silicon and macOS 27. The tools that read the iPhone are bundled inside the app. You do not need Homebrew, and nothing has to be installed on the iPhone.

1. If Firefly is already running, quit it with the power button at the top right of the panel. Unzip `Firefly-macOS.zip`, or use the `Firefly.app` you were given.
2. Drag `Firefly.app` into the Applications folder and double-click it. Click the firefly icon in the menu bar.
3. For the first pairing, connect the iPhone over USB and unlock it. If asked, confirm trust in Finder and on the iPhone. Press Refresh in the panel. The device name, USB, the percentage and the time of the last successful reading should appear.
4. For wireless use, keep the cable connected and select the iPhone in Finder. Under General, turn on “Show this iPhone when on Wi-Fi” and press Apply. With the Mac and the iPhone on the same local network, unplug the cable. After a Refresh, check that the panel shows Wi-Fi and a new reading time. Both methods were tested with one Mac and iPhone pair.

## Everyday use

The Battery tab shows the time and source of the last successful reading. If no new data arrives, the old value is set apart as the last known reading. The History tab shows real readings for 24 hours and for 7 days. Gaps between points are not filled in. CSV export contains the stored history of the selected device. A charging estimate appears only when there are enough recent, uninterrupted charging readings from the same device.

You can scroll the tab strip horizontally, or swipe left and right inside the panel to change tabs.

In Settings you can choose the menu bar appearance and notifications. macOS may ask for permission when you enable notifications. Low battery alerts are based on crossing a threshold. The first reading alone does not count as a crossing. For a scheduled check to run, the Mac must be awake, Firefly must be open and the iPhone must be reachable during the selected minute. Firefly does not wake the Mac. Turn notifications on as well if you want to be notified.

### Menu bar icon

When a current reading is below 20%, the menu bar icon turns system red. At 20% or above while charging, it turns system green. In every other case it uses the standard menu bar colour. The colour change takes 0.24 seconds and is not animated when Reduce Motion is on.

### Locked iPhone and reading intervals

Firefly reads through an open session with the paired iPhone. This can keep working while the screen is locked, as long as the iPhone still offers its network service. If iOS stops Wi-Fi access completely, no live reading is possible. When the phone is announced on the network again, Firefly retries the connection. The first connection may require unlocking the phone.

Between successful reads Firefly waits 1 second while the panel is open, 3 seconds while it is closed, and 10 seconds while it is closed and the Mac is in Low Power Mode. The device's response time is added to that interval. Over Wi-Fi, Firefly waits up to 15 seconds for a delayed battery response.

### Battery reports over cellular

For an iPhone on cellular data, choose the optional iCloud file under Settings → Battery reports over cellular. See the [shortcut setup steps](Resources/DeviceTools/MobileSetup.html). The percentage only updates after the shortcut has run on the iPhone and the file has synced.

## If the battery does not appear

- Read the explanation in the Help tab and press Try again. Start by connecting the phone over USB and unlocking it. Confirm any trust prompt you see.
- If USB works but Wi-Fi does not, check the Finder option and that both devices are on the same network. Being visible in Finder does not by itself prove that the battery can be read.
- If the device does not respond, Firefly ends the query after a timeout. For temporary errors it makes at most six attempts. After that it checks about once a minute whether the paired device is back in the Mac's USB or network device list, and it does not open a new session while the device is absent. Checks stop while the Mac sleeps. The Mac waking, network access returning or the Try again button starts a new attempt.
- If the reading tools appear to be missing, copy the whole app again from the distribution ZIP. If the tools were installed separately, Firefly also checks the standard Homebrew paths.
- If a battery alert does not appear, check both Firefly's settings and the permission under macOS System Settings → Notifications → Firefly.

The last 40 connection events are recorded in `connection-events.txt` inside `~/Library/Application Support/Firefly`, with only the time, the result and the connection type.

## Source project and distribution

Open `Firefly.xcodeproj` in Xcode. Select the `Firefly` scheme for the native menu bar app. Run the core tests with `swift test` in the project directory. A local build carries an ad-hoc code signature for development and use on your own Mac. There is no Developer ID signature and no Apple notarization.

A separate `FireflyWithWidgets` scheme provides small and medium widgets. Configure the same developer team for the app and the extension, and an App Group owned by that team. The widget only reads the shared last reading. Building this scheme has been verified. The signed shared container, adding the widget from the gallery and refresh behaviour on the desktop have not been tested. The main distribution is the menu bar version.

Battery history is kept in the user's `Application Support/Firefly` directory, and preferences in the local user defaults. Firefly does not copy pairing keys. The reading tools come from the Homebrew distribution of libimobiledevice 1.4.0. `ThirdParty/manifest.json` lists versions, source URLs and checksums. Third-party licenses and the source archives of the bundled libraries are under `ThirdParty`.

Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Drag-to-install and packaging a release

Download the DMG for your Mac from GitHub Releases and open it. Drag the Firefly app onto the Applications folder on the right of the window. When the copy finishes, eject the Firefly disk and open the app from Applications.

To prepare a local release, run this from the project root on macOS:

```sh
Scripts/build-dmg.sh /path/to/Firefly.app ./dist
```

The first argument can also be the official release ZIP. The script takes the icons directly from the app. It verifies the app's signature and, without modifying the source app, names the DMG after the version and architecture. The 800 × 500 Finder window and the Retina artwork are produced from the same design recipe on every build. The Python packages are pinned by version and SHA-256 digest.

For a new GitHub release, first attach `Firefly-VERSION-macOS-arm64.zip`, which contains the signed app, to the release draft, then publish it with the `vVERSION` tag. The **Package Firefly installer** workflow builds the DMG, mounts it to check it and attaches it to the same release. If the ZIP was added later, run the same workflow from the Actions tab with that tag. The packager does not produce a Developer ID signature or Apple notarization.

## Updating from inside the app

Copy the first version that includes the updater into Applications and open it from there. Firefly checks `appcast.xml` on GitHub Pages at first launch and then at most once an hour. If a newer, compatible version exists, an Update available button appears next to the connection status. The button opens Sparkle's download, verification and relaunch window. macOS may ask for confirmation if the app is in a location that is not writable.

The person preparing a release builds and signs the app with a new `CFBundleVersion`. They attach `Firefly-VERSION-macOS-arm64.zip` to the `vVERSION` GitHub release. They point `SPARKLE_TOOLS` at the `bin` folder of the Sparkle distribution and pass the ZIP to `Scripts/prepare-update.sh`. The script does not change the feed until it has verified the correct public key and the signature. Publish the generated `docs/updates/appcast.xml` to Pages. Users only ever download the signed ZIP update. The DMG remains for first-time installation.
