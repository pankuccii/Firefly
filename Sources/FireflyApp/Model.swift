import AppKit
import SwiftUI
import UserNotifications
import Network
import WidgetKit
#if canImport(FireflyCore)
import FireflyCore
#endif

struct Preferences: Codable {
    var language = "tr"
    var appearance = 1
    var alerts = false
    var low20 = true
    var low10 = true
    var customLow = 15
    var customEnabled = false
    var chargeAlert = true
    var unavailableMinutes = 15
    var unavailableAlert = false
    var schedule = ScheduleRule()
    var selectedID: String?
    var remoteFile: String?
}
@MainActor final class AppModel: ObservableObject {
    @Published var preferences: Preferences { didSet { savePreferences(); changed?() } }
    @Published var observation: Observation?
    @Published var state: ConnectionState = .idle { didSet { changed?() } }
    @Published var history = History()
    @Published var now = Date()
    @Published var permissionMessage = ""
    @Published var storageFailed = false
    @Published var scheduleMessage = ""
    @Published var sevenDays = false
    @Published var updateVersion: String?
    var installUpdate: (() -> Void)?
    @Published var page = 0
    var changed: (() -> Void)?
    private var service = BatteryService()
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let network = NWPathMonitor()
    private var priorNetwork: NWPath.Status?
    private var generation = 0
    private var failures = 0
    private var asleep = false
    private var sampleTimer: Timer?
    private var browser: NWBrowser?
    private var discoveryWhileBusy = false
    private var nextPoll = Date.distantPast
    private var alerts = AlertEngine()
    private var unavailableSince: Date?
    private var unavailableNotified = false
    private var scheduleDay = ""
    private var pendingSchedule = false
    private var lastWidgetReload = Date.distantPast
    private var widgetConnected: Bool?
    private let directory: URL
    init() {
        let defaults = UserDefaults.standard
        preferences = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        if let data = defaults.data(forKey: "alertState"), let saved = try? JSONDecoder().decode(AlertEngine.self, from: data) { alerts = saved }
        scheduleDay = defaults.string(forKey: "scheduleDay") ?? ""
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Firefly", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("history.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(History.self, from: Data(contentsOf: file))
                history = loaded.validated()
                observation = history.values.last { $0.deviceID == preferences.selectedID }
            }
        } catch { storageFailed = true }
    }
    func t(_ tr: String, _ en: String) -> String { preferences.language == "tr" ? tr : en }
    var freshness: Freshness { observation?.freshness(now: now, connected: state.connected) ?? .unavailable }
    var live: Bool { freshness == .fresh || freshness == .recent }
    @Published private(set) var busy = false
    @Published var panelVisible = false
    var batteryTint: NSColor? {
        guard live, let sample = observation else { return nil }
        if sample.percent < 20 { return .systemRed }
        return sample.charging == true ? .systemGreen : nil
    }
    @Published private(set) var remote: RemoteBatteryReading?
    @Published private(set) var remoteFailed = false
    private var remoteTask: Task<Void, Never>?
    var displayedRemote: RemoteBatteryReading? {
        guard !live, preferences.remoteFile != nil, let remote,
              remote.date >= (observation?.timestamp ?? .distantPast) else { return nil }
        return remote
    }
    func chooseRemoteFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = t("iPhone kestirmenizin yazdığı Firefly.txt dosyasını seçin.", "Select the Firefly.txt file written by your iPhone shortcut.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        clearRemote()
        preferences.remoteFile = url.path
        loadRemote()
    }
    func clearRemote() {
        remoteTask?.cancel(); remoteTask = nil
        preferences.remoteFile = nil; remote = nil; remoteFailed = false; changed?()
    }
    private func loadRemote() {
        guard remoteTask == nil, let path = preferences.remoteFile else { return }
        remoteTask = Task {
            let result = await Task.detached(priority: .utility) { () -> RemoteBatteryReading? in
                let url = URL(fileURLWithPath: path)
                if FileManager.default.isUbiquitousItem(at: url) { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
                guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
                defer { try? h.close() }
                guard let bytes = try? h.read(upToCount: 257) else { return nil }
                return try? RemoteBatteryReading.parse(bytes)
            }.value
            guard !Task.isCancelled, preferences.remoteFile == path else { return }
            if let result, result.date >= (remote?.date ?? .distantPast) { remote = result }
            remoteFailed = result == nil
            remoteTask = nil; changed?()
        }
    }
    var status: String {
        if displayedRemote != nil { return t("Son iCloud bildirimi", "Last iCloud report") }
        switch state {
        case .idle: return t("Bağlantı bekleniyor", "Waiting for connection")
        case .discovering: return t("iPhone aranıyor…", "Looking for iPhone…")
        case .connected: return freshness == .stale ? t("Ölçüm güncel değil", "Reading is stale") : t("Bağlı", "Connected")
        case .retrying(let count, _): return t("Yeniden deneniyor", "Retrying") + " (\(count)/6)"
        case .paused: return t("Uyku sırasında duraklatıldı", "Paused during sleep")
        case .waiting: return t("iPhone yeniden erişilebilir olduğunda bağlanacak", "Waiting for iPhone to become reachable")
        case .failed: return t("Bağlantı için yardım gerekiyor", "Connection needs attention")
        }
    }
    var issue: AcquisitionError? {
        switch state { case .failed(let e), .waiting(let e), .retrying(_, let e): return e; default: return nil }
    }
    var guidance: String {
        switch issue {
        case .dependencyMissing:
            return t("iPhone okuma araçları bulunamadı. Kurulum kılavuzundaki libimobiledevice adımını tamamlayıp Yeniden Dene’ye basın.", "The iPhone tools are missing. Complete the libimobiledevice step in the setup guide, then try again.")
        case .unsupportedTool:
            return t("Kurulu araç gerekli seçenekleri desteklemiyor. libimobiledevice sürümünü güncelleyin.", "The installed tools lack required options. Update libimobiledevice.")
        case .noDevice:
            return t("Seçili iPhone bulunamadı. USB ile bağlayın, kilidini açın ve varsa Güven istemini onaylayın. Wi-Fi için Finder’da “Wi-Fi ağına bağlıyken bu iPhone’u göster” seçeneğini açın. Kablosuz pil okuması henüz doğrulanmış olmayabilir.", "The selected iPhone was not found. Connect via USB, unlock it and accept Trust if prompted. For Wi-Fi, enable “Show this iPhone when on Wi-Fi” in Finder. Wireless battery access may still be unverified.")
        case .timeout:
            return t("Sorgu zamanında tamamlanmadı. iPhone’un kilidini açın ve USB bağlantısını deneyin.", "The request timed out. Unlock your iPhone and try USB.")
        case .invalidPayload:
            return t("Cihaz geçerli bir pil ölçümü döndürmedi. Bu iOS sürümünde erişim olmayabilir; USB ile yeniden deneyin.", "The device returned no valid battery reading. Access may be unavailable on this iOS version; retry via USB.")
        default:
            return t("Pil verisine erişilemedi. Güven eşleşmesi veya bağlantı etkilenmiş olabilir; kesin neden belirlenemedi. USB ile bağlayıp Finder’da cihazı kontrol edin.", "Battery data could not be read. Pairing or connectivity may be affected; the exact cause is unknown. Connect via USB and check the device in Finder.")
        }
    }
    func start() {
        loadRemote()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleep() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.wake() } })
        network.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                defer { self.priorNetwork = path.status }
                if self.priorNetwork != nil && self.priorNetwork != path.status && path.status == .satisfied { self.refresh(reset: true) }
            }
        }
        let nearby = NWBrowser(for: .bonjour(type: "_apple-mobdev2._tcp", domain: "local."), using: .tcp)
        nearby.browseResultsChangedHandler = { [weak self] _, changes in
            guard changes.contains(where: { if case .added = $0 { return true }; return false }) else { return }
            Task { @MainActor in
                guard let self, !self.asleep, !self.state.connected else { return }
                if self.task != nil { self.discoveryWhileBusy = true } else { self.refresh(reset: true) }
            }
        }
        nearby.start(queue: DispatchQueue(label: "Firefly.discovery")); browser = nearby
        network.start(queue: DispatchQueue(label: "Firefly.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer?.tolerance = 3
        refresh(reset: true)
    }
    func stop() { browser?.cancel(); let old = service; Task { await old.close() }; sampleTimer?.invalidate(); timer?.invalidate(); timer = nil; task?.cancel(); network.cancel(); observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver) }
    func sleep() { let old = service; service = BatteryService(); Task { await old.close() }; sampleTimer?.invalidate(); asleep = true; generation += 1; task?.cancel(); task = nil; busy = false; state = .paused; publishWidget(connected: false) }
    func wake() { asleep = false; refresh(reset: true) }
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { loadRemote(); refresh() }
        else if state.connected && !busy { scheduleSample() }
    }
    private func scheduleSample() {
        sampleTimer?.invalidate()
        let delay: TimeInterval = panelVisible ? 1 : (ProcessInfo.processInfo.isLowPowerModeEnabled ? 10 : 3)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = panelVisible ? 0.1 : 0.3
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }
    private func readSample(selected: String?) async throws -> Observation {
        if let previous = observation, previous.deviceID == selected {
            do { return try await service.readSession(previous) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if failures == 0 { recordConnectionEvent("session " + ((error as? AcquisitionError)?.rawValue ?? "closed")) }
            }
        }
        return try await service.read(preferredID: selected)
    }
    private func tick() {
        if !asleep { loadRemote() }
        now = Date(); changed?()
        guard !asleep else { return }
        let dateKey = Calendar.current.startOfDay(for: now).description
        if preferences.schedule.due(at: now), scheduleDay != dateKey {
            scheduleDay = dateKey; UserDefaults.standard.set(dateKey, forKey: "scheduleDay")
            pendingSchedule = true; refresh(reset: true)
        }
        if task == nil && now >= nextPoll {
            if case .waiting = state { probeWaitingDevice() }
            else if !state.connected && failures < 6 { refresh() }
        }
        if preferences.alerts, preferences.unavailableAlert, !unavailableNotified,
           let since = unavailableSince, now.timeIntervalSince(since) >= Double(preferences.unavailableMinutes * 60) {
            unavailableNotified = true
            notify(t("iPhone’a ulaşılamıyor", "iPhone is unavailable"), body: t("Son ölçüm güncel değil. Bağlantıyı kontrol edin.", "The last reading is outdated. Check the connection."))
        }
    }
    private func probeWaitingDevice() {
        guard let id = preferences.selectedID, !asleep, task == nil else { return }
        nextPoll = Date().addingTimeInterval(60)
        let token = generation
        task = Task {
            let listed = (try? await service.isListed(id)) == true
            guard !Task.isCancelled, token == generation else { return }
            task = nil
            let arrived = discoveryWhileBusy
            discoveryWhileBusy = false
            if listed || arrived { refresh(reset: true) }
        }
    }
    func refresh(reset: Bool = false) {
        guard !asleep, task == nil else { return }
        sampleTimer?.invalidate()
        if reset { failures = 0 }
        generation += 1; let token = generation
        busy = true
        if !state.connected { state = .discovering }
        let selected = preferences.selectedID
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await readSample(selected: selected)
                guard !Task.isCancelled, token == generation else { return }
                if !state.connected { recordConnectionEvent("connected " + value.transport.rawValue) }
                let prior = observation
                observation = value
                if preferences.selectedID != value.deviceID { preferences.selectedID = value.deviceID }
                now = Date(); failures = 0; state = .connected(value.transport)
                unavailableSince = nil; unavailableNotified = false
                let latest = history.values.last
                if latest?.deviceID != value.deviceID || latest?.percent != value.percent || latest?.charging != value.charging ||
                    latest?.transport != value.transport || value.timestamp.timeIntervalSince(latest?.timestamp ?? .distantPast) >= 60 {
                    history.append(value); persistHistory(); publishWidget(connected: true)
                } else if widgetConnected == false { publishWidget(connected: true) }
                let lows: [Int] = (preferences.low20 ? [20] : []) + (preferences.low10 ? [10] : []) + (preferences.customEnabled ? [preferences.customLow] : [])
                let events = alerts.evaluate(value, lows: lows, chargeTarget: preferences.chargeAlert ? 80 : nil)
                if prior?.percent != value.percent || !events.isEmpty, let data = try? JSONEncoder().encode(alerts) { UserDefaults.standard.set(data, forKey: "alertState") }
                if preferences.alerts { for event in events { notify(event.hasPrefix("charge") ? t("Şarj hedefi", "Charging target") : t("Düşük pil", "Low battery"), body: "\(value.name): %\(value.percent)") } }
                if pendingSchedule {
                    scheduleMessage = t("Planlanan kontrol tamamlandı", "Scheduled check completed")
                    if value.percent < preferences.schedule.threshold && preferences.alerts { notify(t("Güne hazır mısın?", "Ready for your day?"), body: "\(value.name): %\(value.percent)") }
                }
                scheduleSample()
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                let reason = error as? AcquisitionError ?? .queryFailed
                failures += 1
                if failures == 1 || failures == 6 { recordConnectionEvent("acquisition " + reason.rawValue + " attempt " + String(failures)) }
                if reason == .dependencyMissing || reason == .unsupportedTool { failures = 6 }
                if failures < 6 { state = .retrying(failures, reason) }
                else if preferences.selectedID != nil && reason != .dependencyMissing && reason != .unsupportedTool {
                    state = .waiting(reason)
                } else { state = .failed(reason) }
                publishWidget(connected: false)
                if unavailableSince == nil { unavailableSince = Date() }
                let delay: TimeInterval = failures >= 6 ? 60 : (failures == 1 ? 2 : RetryPolicy().delay(failures: failures))
                nextPoll = Date().addingTimeInterval(delay)
                if failures < 6 {
                    let retry = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                        Task { @MainActor in self?.refresh() }
                    }
                    RunLoop.main.add(retry, forMode: .common); sampleTimer = retry
                }
                if pendingSchedule { scheduleMessage = t("Planlanan kontrol yapılamadı: cihaz erişilemiyor.", "Scheduled check could not run: device unavailable.") }
            }
            pendingSchedule = false; task = nil; busy = false
            let arrived = discoveryWhileBusy
            discoveryWhileBusy = false
            if arrived && !state.connected { refresh(reset: true) }
        }
    }
    func forgetDevice() {
        generation += 1; task?.cancel(); task = nil
        preferences.selectedID = nil; observation = nil; alerts = AlertEngine()
        refresh(reset: true)
    }
    func requestNotifications() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                preferences.alerts = allowed
                permissionMessage = allowed ? t("Bildirim izni verildi", "Notifications allowed") : t("Sistem Ayarları → Bildirimler’den Firefly’a izin verin.", "Allow Firefly in System Settings → Notifications.")
            } catch { permissionMessage = t("Bildirim izni alınamadı", "Notification permission failed") }
        }
    }
    private func notify(_ title: String, body: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in }
    }
    private func savePreferences() { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences") } }
    private func recordConnectionEvent(_ event: String) {
        let url = directory.appendingPathComponent("connection-events.txt")
        let prior = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamp = ISO8601DateFormatter().string(from: Date())
        let lines = prior.split(separator: "\n").suffix(39).map(String.init) + [stamp + " " + event]
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    private func persistHistory() {
        do { try JSONEncoder().encode(history).write(to: directory.appendingPathComponent("history.json"), options: .atomic); storageFailed = false }
        catch { storageFailed = true }
    }
    private func publishWidget(connected: Bool) {
        guard let value = observation, let url = WidgetSnapshot.location() else { return }
        let snapshot = WidgetSnapshot(name: value.name, percent: value.percent, timestamp: value.timestamp, connected: connected, language: preferences.language)
        guard let data = try? JSONEncoder().encode(snapshot), (try? data.write(to: url, options: .atomic)) != nil else { return }
        if widgetConnected != connected || Date().timeIntervalSince(lastWidgetReload) >= 900 {
            WidgetCenter.shared.reloadTimelines(ofKind: "FireflyBattery"); lastWidgetReload = Date(); widgetConnected = connected
        }
    }
    func exportCSV() {
        guard let id = preferences.selectedID else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Firefly.csv"
        if panel.runModal() == .OK, let url = panel.url { do { try history.csv(deviceID: id).write(to: url, atomically: true, encoding: .utf8) } catch { storageFailed = true } }
    }
}
