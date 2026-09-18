import Foundation
import MarknoteCore

final class LocalizationTests {
    func testSystemLanguageResolution() {
        expectEqual(AppLanguage.resolve(["en-GB"]), .english)
        expectEqual(AppLanguage.resolve(["zh-Hans-SG"]), .simplifiedChinese)
        expectEqual(AppLanguage.resolve(["zh_CN"]), .simplifiedChinese)
        expectEqual(AppLanguage.resolve(["fr", "zh-Hant"]), .simplifiedChinese)
        expectEqual(AppLanguage.resolve(["de", "en-US"]), .english)
        expectEqual(AppLanguage.resolve(["ja"]), .english)
        expectEqual(AppLanguage.resolve([]), .english)
    }

    func testPreferencePersistenceAndNotifications() {
        let suiteName = "MarknoteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalizationStore(defaults: defaults, preferredLanguages: { ["zh-CN"] })
        expectEqual(store.selection, .system)
        expectEqual(store.language, .simplifiedChinese)
        final class Counter: @unchecked Sendable { var count = 0 }
        let notifications = Counter()
        let observer = NotificationCenter.default.addObserver(forName: LocalizationStore.didChange, object: store, queue: nil) { _ in notifications.count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.select(.english)
        store.select(.english)
        expectEqual(notifications.count, 1)
        expectEqual(store.string(.menuFile), "File")
        expectEqual(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["en"])
        let restored = LocalizationStore(defaults: defaults, preferredLanguages: { ["zh-CN"] })
        expectEqual(restored.selection, .english)
        expectEqual(restored.language, .english)
        store.select(.system)
        expectEqual(store.language, .simplifiedChinese)
        expectEqual(store.string(.menuFile), "文件")
        expectEqual(notifications.count, 2)
        expectNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        defaults.set("unsupported", forKey: LocalizationStore.preferenceKey)
        expectEqual(LocalizationStore(defaults: defaults, preferredLanguages: { ["de"] }).selection, .system)
    }

    func testEveryTranslationAndFormatIsAvailable() throws {
        let suiteName = "MarknoteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalizationStore(defaults: defaults)
        let format = try NSRegularExpression(pattern: "%[0-9]+\\$ld")
        var placeholders: [String: [String]] = [:]
        for language in [AppLanguage.english, .simplifiedChinese] {
            store.select(language)
            guard let url = LocalizationStore.bundle(for: language)?.url(forResource: "Localizable", withExtension: "strings"),
                  let strings = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String] else {
                expect(false, "Missing localization resource: \(language)")
                continue
            }
            expectEqual(Set(strings.keys), Set(L10n.Key.allCases.map(\.rawValue)))
            for key in L10n.Key.allCases {
                let value = strings[key.rawValue] ?? ""
                expect(!value.isEmpty && store.string(key) == value, "Missing translation: \(language).\(key)")
                let matches = format.matches(in: value, range: NSRange(location: 0, length: value.utf16.count)).map { (value as NSString).substring(with: $0.range) }.sorted()
                if language == .english { placeholders[key.rawValue] = matches }
                else { expectEqual(matches, placeholders[key.rawValue] ?? []) }
            }
            expectFalse(store.string(.statistics, arguments: [12, 40, 1]).contains("%"))
            expect(store.string(.position, arguments: [3, 14]).contains("14"))
            let guide = try String(contentsOf: store.resource("Welcome", extension: "md")!, encoding: .utf8)
            expectEqual(MarkdownText.headings(in: guide).count, 5)
            expect(guide.contains(language == .english ? "Preview" : "预览"))
        }
    }
}
