# Firefly 🪲

**A lightweight, native macOS companion for monitoring your iPhone's battery wirelessly.**

Firefly displays your paired iPhone's battery percentage and charging status directly in your Mac's menu bar.

Designed to be simple, elegant, and unobtrusive, Firefly helps you keep track of your iPhone's battery without constantly checking your phone.

## Features

- **Wireless Battery Monitoring** — Monitor your iPhone over Wi-Fi after pairing it with your Mac.
- **Menu Bar Integration** — View your iPhone's battery percentage at a glance.
- **Charging Status** — See whether your device is charging when that information is available.
- **Automatic Reconnection** — Recover from temporary connection interruptions.
- **Battery Notifications** — Receive alerts based on configurable battery thresholds.
- **Connection Diagnostics** — Troubleshoot connection problems with clear guidance.
- **Battery Widgets** — View battery information from supported macOS desktop widgets.
- **Last Updated Information** — Know when your iPhone's battery was last successfully checked.
- **Native macOS Experience** — Built with Swift, SwiftUI, and AppKit.

## Requirements

- Apple Silicon Mac
- macOS 27
- Compatible iPhone
- USB connection for initial pairing
- Wi-Fi connectivity for wireless monitoring
- Xcode for building from source

## Installation

1. Download or clone this repository.
2. Open `Firefly.xcodeproj` in Xcode.
3. Select the `Firefly` scheme.
4. Build and run the application.
5. Connect your iPhone using a USB cable for initial pairing.
6. Trust your Mac when prompted on your iPhone.
7. Enable Wi-Fi synchronization in Finder if wireless monitoring is desired.

For detailed setup, pairing, notifications, and troubleshooting instructions, see [SETUP.md](SETUP.md). Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Development

Firefly is developed primarily in Swift using native Apple frameworks.

**Project structure:**

- `Sources/` — Core application and UI source code.
- `DeviceSession/` — Device connection and session management.
- `Widget/` — macOS widget extension.
- `Resources/` — Application resources and visual assets.
- `Tests/FireflyCoreTests/` — Core functionality tests.
- `ThirdParty/` — Third-party components and license information.

### Running Tests

Core tests can be executed from the project directory:

```bash
swift test
```

### Building with Xcode

Open `Firefly.xcodeproj`, select the `Firefly` scheme, and build the application.

For the optional widget extension, select the `FireflyWithWidgets` scheme and configure the appropriate signing team and App Group capabilities.

## Privacy

Firefly is designed with a local-first approach. Its core functionality does not require a user account or a cloud service.

Battery information is obtained through supported local device connections, and connection status is presented transparently.

## Project Status

**Firefly is under active development.**

Wireless battery monitoring depends on device pairing, connectivity, and operating system behavior. Availability and update frequency may vary.

Some advanced features may still be experimental or under development.

## Built With

- Swift
- SwiftUI
- AppKit
- WidgetKit
- Apple platform frameworks

---

**Firefly — Your iPhone's battery, always in sight.**
