import Foundation

public enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let language = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if language == "en" || language.hasPrefix("en-") { return .english }
            if language == "zh" || language.hasPrefix("zh-") { return .simplifiedChinese }
        }
        return .english
    }
}

public enum AppResources {
    public static let bundle: Bundle = {
        let packaged = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Marknote_MarknoteCore.bundle")) }
        return packaged ?? Bundle.module
    }()
}

/// App-owned strings update immediately. Apple-owned panels adopt AppleLanguages on next launch.
public final class LocalizationStore: NSObject {
    public static let preferenceKey = "interfaceLanguage"
    public static let didChange = Notification.Name("MarknoteLanguageDidChange")
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    public private(set) var selection: AppLanguage
    public var language: AppLanguage { selection == .system ? AppLanguage.resolve(preferredLanguages()) : selection }

    public init(defaults: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        selection = defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        super.init()
    }

    public func select(_ selection: AppLanguage) {
        guard selection != self.selection else { return }
        self.selection = selection
        defaults.set(selection.rawValue, forKey: Self.preferenceKey)
        if selection == .system { defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set([selection.rawValue], forKey: "AppleLanguages") }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    public func string(_ key: L10n.Key, arguments: [CVarArg] = []) -> String {
        let fallback = Self.bundle(for: .english)?.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil) ?? key.rawValue
        let format = Self.bundle(for: language)?.localizedString(forKey: key.rawValue, value: fallback, table: nil) ?? fallback
        return arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    public func resource(_ name: String, extension ext: String) -> URL? {
        Self.bundle(for: language)?.url(forResource: name, withExtension: ext)
            ?? Self.bundle(for: .english)?.url(forResource: name, withExtension: ext)
    }

    public static func bundle(for language: AppLanguage) -> Bundle? {
        // SwiftPM lowercases localization directory names (for example, zh-hans.lproj).
        AppResources.bundle.url(forResource: language.rawValue.lowercased(), withExtension: "lproj").flatMap(Bundle.init(url:))
    }
}

public enum L10n {
    public static let shared = LocalizationStore()
    public static func text(_ key: Key, _ arguments: CVarArg...) -> String { shared.string(key, arguments: arguments) }

    public enum Key: String, CaseIterable {
        case appName, tagline, about, aboutCredits, aboutCopyright
        case language, languageSystem, languageNote
        case services, hideApp, hideOthers, showAll, quit
        case menuFile, newDocument, open, openRecent, close, save, saveAs, revert, exportHTML, exportPDF
        case menuEdit, undo, redo, cut, copy, paste, selectAll, find
        case menuFormat, bold, italic, insertLink, heading, list, task, quote, code, table
        case menuView, outline, editorOnly, splitView, previewOnly, focus, increaseFont, decreaseFont, fullScreen
        case menuWindow, minimize, zoom, bringAllToFront, menuHelp, userGuide
        case noRecentDocuments, clearRecent
        case outlineHint, focusHint, sourceHeader, sourceDetail, previewHeader, previewDetail
        case editorAccessibility, previewAccessibility, modesAccessibility
        case editorToggle, previewToggle, editorToggleHelp, previewToggleHelp
        case insert, export, sidebarHelp, boldHelp, italicHelp, linkHelp, focusHelp
        case statistics, position, unsaved, modified, saved, untitled, untitledHeading
        case continueList, boldPlaceholder, italicPlaceholder, linkPlaceholder, codePlaceholder, tableHeading, tableCell
        case unreadableFile, previewNotReady, emptyTitle, emptyMessage, imageUnavailable
    }
}
