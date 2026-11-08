import AppKit
import SwiftUI

@main struct FireflyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: AppModel!
    private let updates = FireflyUpdates()
    private var imageKey = ""
    private var fade: Timer?
    private var displayedColor: NSColor?
    private var lastStateColor = "neutral"
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        popover.delegate = self; popover.behavior = .transient; popover.contentViewController = NSHostingController(rootView: FireflyView(model: model))
        model.changed = { [weak self] in self?.update() }
        updates.onChange = { [weak self] version in self?.model.updateVersion = version }
        model.installUpdate = { [weak self] in
            self?.popover.performClose(nil)
            self?.updates.install()
        }
        update(); model.start(); updates.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }; return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    func popoverWillShow(_ notification: Notification) { model.setPanelVisible(true); updates.probe(force: true) }
    func popoverDidClose(_ notification: Notification) { model.setPanelVisible(false) }
    private func update() {
        guard let button = statusItem.button else { return }
        let name = !model.live ? "FireflyDisconnectedTemplate" : (model.observation?.charging == true ? "FireflyChargingTemplate" : "FireflyNormalTemplate")
        let level = model.observation.map { min(100, max(0, Int((Double($0.percent) / 25).rounded()) * 25)) } ?? 0
        let charging = model.live && model.observation?.charging == true
        let symbol = charging ? "bolt.fill" : model.live ? "battery.\(level)percent" : "questionmark.circle"
        let image = model.preferences.appearance == 2 ? NSImage(systemSymbolName: symbol, accessibilityDescription: "Firefly") : NSImage(named: name)
        let color = model.batteryTint
        if let source = image {
            let stateColor = color == nil ? "neutral" : (model.observation?.percent ?? 100) < 20 ? "red" : "green"
            let key = [model.preferences.appearance == 2 ? symbol : name, stateColor, button.effectiveAppearance.name.rawValue].joined(separator: ":")
            if key != imageKey {
                let animate = !imageKey.isEmpty && stateColor != lastStateColor && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                imageKey = key
                lastStateColor = stateColor
                render(source, color: color, on: button, animate: animate)
            }
        }
        button.imagePosition = .imageLeading
        button.title = model.preferences.appearance == 0 ? "" : (model.live ? " \(model.observation!.percent)%" : " —")
        button.toolTip = "Firefly · " + (charging ? model.t("Şarj oluyor", "Charging") : model.status)
        if let report = model.displayedRemote {
            let recent = report.recent(at: Date())
            if model.preferences.appearance != 0 { button.title = recent ? " ☁︎ \(report.percent)%" : " —" }
            button.toolTip = model.t("iCloud son bildirimi", "Last iCloud report") + " · \(report.percent)% · " + report.date.formatted()
        }
        button.setAccessibilityLabel((button.toolTip ?? "Firefly") + button.title)
    }
    private func render(_ source: NSImage, color: NSColor?, on button: NSStatusBarButton, animate: Bool) {
        fade?.invalidate()
        let side = min(22, max(18, NSStatusBar.system.thickness - 1))
        let size = NSSize(width: side, height: side)
        var target = NSColor.white
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            target = (color ?? .labelColor).usingColorSpace(.sRGB) ?? .white
        }
        func draw(_ tint: NSColor?) {
            displayedColor = tint ?? target
            if let tint {
                let image = NSImage(size: size, flipped: false) { rect in
                    source.draw(in: rect)
                    tint.setFill(); rect.fill(using: .sourceAtop)
                    return true
                }
                image.isTemplate = false; button.image = image
            } else {
                let image = source.copy() as? NSImage
                image?.size = size; image?.isTemplate = true; button.image = image
            }
        }
        guard animate, let from = displayedColor else { draw(color == nil ? nil : target); return }
        let start = ProcessInfo.processInfo.systemUptime
        let transition = Timer(timeInterval: 1.0 / 30, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.24)
                if t >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    timer.invalidate(); draw(color == nil ? nil : target)
                } else {
                    draw(from.blended(withFraction: t * t * (3 - 2 * t), of: target) ?? target)
                }
            }
        }
        fade = transition; RunLoop.main.add(transition, forMode: .common)
    }

}

import Sparkle

// Silent probes populate the footer. Download/installation is always user initiated.
@MainActor final class FireflyUpdates: NSObject, SPUUpdaterDelegate {
    var onChange: ((String?) -> Void)?
    private var controller: SPUStandardUpdaterController?
    private var lastCheck = Date.distantPast
    private var probeTimer: Timer?
    func start() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller?.startUpdater()
        probe()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probe() }
        }
        probeTimer?.tolerance = 180
    }
    func probe(force: Bool = false) {
        guard let updater = controller?.updater, updater.canCheckForUpdates,
              force || Date().timeIntervalSince(lastCheck) >= 3600 else { return }
        lastCheck = Date()
        updater.checkForUpdateInformation()
    }
    func install() {
        guard controller?.updater.canCheckForUpdates == true else { return }
        controller?.checkForUpdates(nil)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { onChange?(item.displayVersionString) }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { onChange?(nil) }
}
