import WidgetKit
import SwiftUI
struct BatteryEntry: TimelineEntry { let date: Date; let value: WidgetSnapshot? }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { BatteryEntry(date: Date(), value: nil) }
    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) { completion(BatteryEntry(date: Date(), value: WidgetSnapshot.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let value = WidgetSnapshot.load(), now = Date()
        var entries = [BatteryEntry(date: now, value: value)]
        if let value, value.live(at: now) { entries.append(BatteryEntry(date: value.timestamp.addingTimeInterval(300), value: value)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
struct BatteryWidgetView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        // Without a snapshot there is no app choice to follow, so use the system language.
        let tr = (entry.value?.language ?? AppLanguage.initial()) != "en"
        let live = entry.value?.live(at: entry.date) == true
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if let url = Bundle.main.url(forResource: "WidgetLogo", withExtension: "png"), let icon = NSImage(contentsOf: url) { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                Text("Firefly").font(.headline)
            }
            Text(entry.value?.name ?? "iPhone").font(.caption).lineLimit(1)
            Text(live ? "\(entry.value!.percent)%" : "—").font(.title.bold()).monospacedDigit()
            if live, let value = entry.value { ProgressView(value: Double(value.percent), total: 100) }
            if let value = entry.value {
                if !live { Text(tr ? "Son ölçüm: %\(value.percent)" : "Last reading: \(value.percent)%").font(.caption2) }
                Text(value.timestamp, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                if family == .systemMedium { Text(live ? (tr ? "Yakın zamanda ölçüldü" : "Recently measured") : (tr ? "Güncel ölçüm yok" : "No current reading")).font(.caption) }
            } else { Text(tr ? "Firefly’ı açın" : "Open Firefly").font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading).containerBackground(.fill.tertiary, for: .widget)
    }
}
@main struct FireflyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FireflyBattery", provider: Provider()) { BatteryWidgetView(entry: $0) }
            .configurationDisplayName("Firefly").description("iPhone · Battery / Pil").supportedFamilies([.systemSmall, .systemMedium])
    }
}
