import Foundation
// The UI ships in Turkish and English. Until the user picks one in Settings,
// follow the Mac's first preferred language: Turkish if it is Turkish, English otherwise.
public enum AppLanguage {
    public static func initial(preferred: [String] = Locale.preferredLanguages) -> String {
        guard let first = preferred.first?.lowercased() else { return "en" }
        return first == "tr" || first.hasPrefix("tr-") || first.hasPrefix("tr_") ? "tr" : "en"
    }
}
