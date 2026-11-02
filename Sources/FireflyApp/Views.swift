import SwiftUI
import Charts
#if canImport(FireflyCore)
import FireflyCore
#endif

struct FireflyView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                if let url = Bundle.main.url(forResource: "Mascot", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion || !model.panelVisible || !model.live || model.observation?.charging != true)) { tick in
                        let pulse = 0.82 + 0.18 * sin(tick.date.timeIntervalSinceReferenceDate * 2)
                        Image(nsImage: image).resizable().scaledToFit().scaleEffect(1.26).frame(width: 70, height: 70)
                            .opacity(!model.live ? 0.45 : (model.observation?.charging == true && !reduceMotion ? pulse : 1))
                    }.frame(width: 70, height: 70).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Firefly").font(.title2.bold())
                    Text(model.observation?.name ?? model.t("iPhone’un yanında", "Here for your iPhone")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).help(model.t("Firefly’dan çık", "Quit Firefly"))
                    .accessibilityLabel(model.t("Firefly’dan çık", "Quit Firefly"))
            }
            navigation
            Group {
            if model.page == 0 {
                battery.frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    Group {
                        switch model.page {
                        case 1: insights
                        case 2: diagnostics
                        default: settings
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.frame(height: 370)
            }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { drag in
                let dx = drag.translation.width
                guard abs(dx) > 55, abs(dx) > 2 * abs(drag.translation.height) else { return }
                selectPage(model.page + (dx < 0 ? 1 : -1))
            })
            Divider()
            HStack {
                Label(model.status, systemImage: model.state.connected ? "checkmark.circle" : "info.circle")
                    .font(.caption).lineLimit(2)
                Spacer()
                Button { model.refresh(reset: true) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.busy).help(model.t("Yenile", "Refresh"))
                    .accessibilityLabel(model.t("Yenile", "Refresh")).keyboardShortcut("r", modifiers: .command)
            }
        }.padding(16).frame(width: 370).fixedSize(horizontal: false, vertical: true)
            .environment(\.locale, Locale(identifier: model.preferences.language))
    }
    private func selectPage(_ page: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { model.page = min(3, max(0, page)) }
    }
    private var navigation: some View {
        let names = [model.t("Pil", "Battery"), model.t("Geçmiş", "History"), model.t("Yardım", "Help"), model.t("Ayarlar", "Settings")]
        let icons = ["battery.75percent", "chart.xyaxis.line", "questionmark.circle", "gearshape"]
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(0..<4) { index in
                        Button { selectPage(index) } label: {
                            Label(names[index], systemImage: icons[index])
                                .font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 13).frame(minHeight: 34)
                                .foregroundStyle(model.page == index ? Color.accentColor : .primary)
                                .glassEffect(model.page == index ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
                        }.buttonStyle(.plain).id(index)
                            .accessibilityAddTraits(model.page == index ? .isSelected : [])
                    }
                }.padding(3)
            }.scrollIndicators(.hidden)
            .onChange(of: model.page) { _, value in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }
    private var battery: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let snapshot = model.displayedRemote {
                Label(model.t("iPhone’dan son bildirim", "Last report from iPhone"), systemImage: "icloud")
                Text("\(snapshot.percent)%").font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                ProgressView(value: Double(snapshot.percent), total: 100).tint(snapshot.percent < 20 ? Color.red : .secondary)
                Text(snapshot.date, format: .dateTime.year().month().day().hour().minute()).font(.callout)
                Text(model.t("iCloud üzerinden · Kestirme çalıştığında güncellenir.", "Via iCloud · Updates when the shortcut runs.")).font(.caption).foregroundStyle(.secondary)
            } else if let value = model.observation {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.live ? "\(value.percent)%" : "—").font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                        .accessibilityLabel(model.live ? model.t("Pil yüzde \(value.percent)", "Battery \(value.percent) percent") : model.t("Güncel pil verisi yok", "No current battery reading"))
                    Spacer()
                    if model.live, let charging = value.charging {
                        Label(charging ? model.t("Şarj oluyor", "Charging") : model.t("Pilde", "On battery"), systemImage: charging ? "bolt.fill" : "battery.75percent").font(.caption)
                    }
                }
                ProgressView(value: model.live ? Double(value.percent) : 0, total: 100)
                    .tint(Color(nsColor: model.batteryTint ?? .secondaryLabelColor))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: model.batteryTint)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: value.percent)
                if !model.live { Text(model.t("Son bilinen değer", "Last known reading") + ": \(value.percent)%").foregroundStyle(.secondary) }
                Label(value.transport.rawValue, systemImage: value.transport == .usb ? "cable.connector" : "wifi")
                Text(model.t("Son başarılı ölçüm", "Last successful reading")).font(.caption).foregroundStyle(.secondary)
                Text(value.timestamp, format: .dateTime.day().month().hour().minute().second()).font(.callout)
                Text(freshnessText).font(.caption).foregroundStyle(.secondary)
                if model.issue != nil { Button(model.t("Bağlantıyı düzelt", "Resolve connection")) { model.page = 2 } }
            } else {
                Text(model.t("Firefly’a hoş geldin", "Welcome to Firefly")).font(.title3.bold())
                Text(model.t("İlk gerçek ölçüm için iPhone’unu bağla.", "Connect your iPhone for the first real reading."))
                Label(model.t("USB kablosunu bağla", "Connect the USB cable"), systemImage: "1.circle")
                Label(model.t("Kilidi aç ve bu Mac’e güven", "Unlock and trust this Mac"), systemImage: "2.circle")
                Label(model.t("İlk pil ölçümünü doğrula", "Verify the first battery reading"), systemImage: "3.circle")
                if model.busy { ProgressView().controlSize(.small) }
                Button(model.t("Bağlantıyı kontrol et", "Check connection")) { model.refresh(reset: true) }.disabled(model.busy)
                if model.issue != nil { Text(model.guidance).font(.caption).foregroundStyle(.secondary) }
            }
            if model.storageFailed { Text(model.t("Yerel geçmiş kaydedilemedi. Disk alanını ve izinleri kontrol edin.", "Local history could not be saved. Check disk space and permissions.")).font(.caption).foregroundStyle(.orange) }
        }
    }
    private var freshnessText: String {
        switch model.freshness {
        case .fresh: return model.t("Güncel ölçüm", "Fresh reading")
        case .recent: return model.t("Yakın zamanda güncellendi", "Recently updated")
        case .stale: return model.t("Ölçüm eskidi; canlı veri değil", "Stale reading; not live data")
        case .disconnected: return model.t("Bağlantı yok; son ölçüm saklandı", "Disconnected; last reading retained")
        case .unavailable: return model.t("Veri yok", "Unavailable")
        }
    }
    private var filtered: [Observation] {
        model.history.values.filter { $0.deviceID == model.preferences.selectedID && model.now.timeIntervalSince($0.timestamp) <= (model.sevenDays ? 604800 : 86400) }
    }
    private var insights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(model.t("Dönem", "Period"), selection: $model.sevenDays) { Text(model.t("24 saat", "24 hours")).tag(false); Text(model.t("7 gün", "7 days")).tag(true) }.pickerStyle(.segmented)
            if filtered.isEmpty { Text(model.t("Henüz kaydedilmiş ölçüm yok.", "No readings recorded yet.")).foregroundStyle(.secondary) }
            else {
                Chart(filtered) { value in
                    PointMark(x: .value("Time", value.timestamp), y: .value("%", value.percent))
                        .foregroundStyle(value.charging == true ? Color.orange : Color.green).symbolSize(12)
                }.chartYScale(domain: 0...100).frame(height: 190)
                    .accessibilityLabel(model.t("Kaydedilen pil ölçümleri", "Recorded battery readings"))
                Text(model.t("Noktalar gerçek ölçümlerdir. Veri boşlukları birleştirilmez. Turuncu: şarj sırasında ölçüldü.", "Dots are actual readings. Gaps are not interpolated. Orange: measured while charging.")).font(.caption).foregroundStyle(.secondary)
                if let id = model.preferences.selectedID {
                    let sessions = InsightsEngine.sessions(filtered, deviceID: id)
                    Text(model.t("Gözlenen şarj aralıkları: \(sessions.count)", "Observed charging intervals: \(sessions.count)")).font(.caption)
                    if let estimate = InsightsEngine.minutesToFull(filtered, deviceID: id, now: model.now) {
                        Text(model.t("Mevcut hıza göre yaklaşık \(estimate) dk. Şarj yavaşladığında süre uzayabilir.", "Roughly \(estimate) min at the current rate. Charging may slow down.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(model.t("CSV dışa aktar", "Export CSV")) { model.exportCSV() }
            }
        }
    }
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t("Bağlantı asistanı", "Connection assistant")).font(.title3.bold())
            Text(model.state.connected ? model.t("Gerçek bir pil ölçümü alındı. Bağlantı çalışıyor.", "An actual battery reading was received. The connection works.") : model.guidance)
            Text(model.t("USB önce denenir. Aynı cihaz Wi-Fi üzerinden bulunursa kablosuz sorgu yapılır. Finder’da görünmek tek başına pil erişimini kanıtlamaz.", "USB is tried first. If the same device is discovered over Wi-Fi, a wireless query is attempted. Finder visibility alone does not prove battery access.")).font(.caption).foregroundStyle(.secondary)
            Button(model.t("Yeniden dene", "Try again")) { model.refresh(reset: true) }.disabled(model.busy)
            Text(model.t("Altı başarısız denemeden sonra Firefly, eşleştirilmiş iPhone’un geri dönüp dönmediğini dakikada bir kontrol eder. iPhone ağda yeniden göründüğünde, Mac uyandığında veya Yeniden dene’ye bastığınızda tekrar bağlanır.", "After six failed attempts, Firefly checks the local device list once a minute for the paired iPhone. Device discovery, Mac wake, a restored network or Try again starts a new attempt.")).font(.caption).foregroundStyle(.secondary)
            if let issue = model.issue { Text("Code: \(issue.rawValue)").font(.caption.monospaced()) }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup(model.t("Mobil veriden pil bildirimi", "Battery reports over cellular")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t("iPhone’daki kestirme pil yüzdesini ve ölçüm saatini iCloud Drive’a yazar. Yerel bağlantı yokken en son bildirimi görürsün.", "Your iPhone shortcut saves its battery level and measurement time to iCloud Drive. The last report appears when the local connection is unavailable.")).font(.caption)
                    Button(model.t("Kurulum kılavuzu", "Setup guide")) {
                        if let url = Bundle.main.url(forResource: "MobileSetup", withExtension: "html", subdirectory: "DeviceTools") { NSWorkspace.shared.open(url) }
                    }
                    Button(model.t("Bildirim dosyasını seç…", "Select report file…")) { model.chooseRemoteFile() }
                    if let path = model.preferences.remoteFile {
                        Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption)
                        if model.remoteFailed { Text(model.t("Dosyadan geçerli ölçüm okunamadı.", "No valid reading could be read from the file.")).font(.caption) }
                        Button(model.t("Bağlantıyı kaldır", "Remove file")) { model.clearRemote() }
                    }
                }.padding(.top, 6)
            }
            Picker(model.t("Dil", "Language"), selection: $model.preferences.language) { Text("Türkçe").tag("tr"); Text("English").tag("en") }
            Picker(model.t("Menü çubuğu", "Menu bar"), selection: $model.preferences.appearance) {
                Text(model.t("Yalnız simge", "Icon only")).tag(0)
                Text(model.t("Ateş böceği ve yüzde", "Firefly and percentage")).tag(1)
                Text(model.t("Pil ve yüzde", "Battery and percentage")).tag(2)
            }
            Divider()
            Toggle(model.t("Bildirimler", "Notifications"), isOn: $model.preferences.alerts)
                .onChange(of: model.preferences.alerts) { _, enabled in if enabled { model.requestNotifications() } }
            Button(model.t("Bildirim iznini kontrol et", "Check notification permission")) { model.requestNotifications() }
            if !model.permissionMessage.isEmpty { Text(model.permissionMessage).font(.caption) }
            Toggle(model.t("%20 altında", "Below 20%"), isOn: $model.preferences.low20)
            Toggle(model.t("%10 altında", "Below 10%"), isOn: $model.preferences.low10)
            Toggle(model.t("Şarj olurken %80", "80% while charging"), isOn: $model.preferences.chargeAlert)
            Toggle(model.t("Özel düşük pil uyarısı", "Custom low battery alert"), isOn: $model.preferences.customEnabled)
            Stepper("%\(model.preferences.customLow)", value: $model.preferences.customLow, in: 1...99)
            Toggle(model.t("Bağlantı kesilince bildir", "Notify when unavailable"), isOn: $model.preferences.unavailableAlert)
            Stepper(model.t("\(model.preferences.unavailableMinutes) dakika", "\(model.preferences.unavailableMinutes) minutes"), value: $model.preferences.unavailableMinutes, in: 5...120, step: 5)
            Divider()
            Toggle(model.t("Planlanan kontrol", "Scheduled check"), isOn: $model.preferences.schedule.enabled)
            HStack {
                Picker(model.t("Saat", "Hour"), selection: $model.preferences.schedule.hour) { ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) } }
                Picker(model.t("Dakika", "Minute"), selection: $model.preferences.schedule.minute) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }
            }
            HStack(spacing: 3) {
                ForEach(1...7, id: \.self) { day in
                    Button(dayLabel(day)) {
                        if model.preferences.schedule.weekdays.contains(day) { model.preferences.schedule.weekdays.removeAll { $0 == day } }
                        else { model.preferences.schedule.weekdays.append(day) }
                    }.tint(model.preferences.schedule.weekdays.contains(day) ? .accentColor : .secondary)
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel(dayFullLabel(day))
                        .accessibilityValue(model.preferences.schedule.weekdays.contains(day) ? model.t("Seçili", "Selected") : model.t("Seçili değil", "Not selected"))
                }
            }
            Stepper(model.t("%\(model.preferences.schedule.threshold) altında bildir", "Notify below \(model.preferences.schedule.threshold)%"), value: $model.preferences.schedule.threshold, in: 1...100)
            Text(model.t("Kontrol için Firefly açık, Mac uyanık ve iPhone erişilebilir olmalıdır. Kaçırılan saatler sonradan tamamlanmış sayılmaz. Bildirimler açık olmalıdır.", "Firefly must be running, the Mac awake and the iPhone reachable. Missed checks are not reported as completed. Notifications must be enabled.")).font(.caption).foregroundStyle(.secondary)
            if !model.scheduleMessage.isEmpty { Text(model.scheduleMessage).font(.caption) }
            Divider()
            Button(model.t("Başka bir iPhone bul", "Find another iPhone")) { model.forgetDevice() }
            Text(model.t("Ölçüm geçmişi bu Mac’te tutulur. İsteğe bağlı mobil bildirimler seçtiğiniz iCloud dosyasından okunur.", "History stays on this Mac. Optional cellular reports are read from the iCloud file you select.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func dayLabel(_ day: Int) -> String { (model.preferences.language == "tr" ? ["Pz", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"] : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"])[day - 1] }
    private func dayFullLabel(_ day: Int) -> String { let formatter = DateFormatter(); formatter.locale = Locale(identifier: model.preferences.language); return formatter.weekdaySymbols[day - 1] }
}
