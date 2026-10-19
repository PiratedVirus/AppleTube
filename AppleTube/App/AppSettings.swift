import SwiftUI

/// User preferences, saved on the device. Views read these directly, so changes apply immediately.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Accent: String, CaseIterable, Identifiable {
        case red, pink, orange, green, teal, blue, purple
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .red: Color(red: 0.98, green: 0.18, blue: 0.28)    // Apple Music #FA2D48
            case .pink: Color(red: 1, green: 0.36, blue: 0.62)
            case .orange: Color(red: 1, green: 0.55, blue: 0.16)
            case .green: Color(red: 0.2, green: 0.78, blue: 0.4)
            case .teal: Color(red: 0.1, green: 0.72, blue: 0.75)
            case .blue: Color(red: 0.2, green: 0.5, blue: 1)
            case .purple: Color(red: 0.6, green: 0.35, blue: 0.95)
            }
        }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    }

    var accent: Accent { didSet { save() } }
    var theme: Theme { didSet { save() } }
    /// Library rows in display order; categories not listed are hidden.
    var libraryCategories: [LibraryCategory] { didSet { save() } }
    /// Home shelf titles in the order you arranged them; shelves not listed keep YouTube's order after these.
    var homeOrder: [String] { didSet { save() } }
    var hiddenHomeSections: Set<String> { didSet { save() } }
    /// Every shelf title seen on Home, so Customize Home can list them.
    var knownHomeSections: [String] { didSet { save() } }
    var largeTopPicks: Bool { didSet { save() } }
    var generatedCovers: Bool { didSet { save() } }
    /// Push play again after the phone locks (works around the web player pausing).
    var resumeAfterLock: Bool { didSet { save() } }
    /// Chosen in Settings when Google's photo can't be loaded (or to override it).
    var customProfilePhoto: Data? { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        accent = Accent(rawValue: d.string(forKey: "accent") ?? "") ?? .red
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        libraryCategories = (d.stringArray(forKey: "libraryCategories") ?? LibraryCategory.allCases.map(\.rawValue))
            .compactMap(LibraryCategory.init(rawValue:))
        homeOrder = d.stringArray(forKey: "homeOrder") ?? []
        hiddenHomeSections = Set(d.stringArray(forKey: "hiddenHomeSections") ?? [])
        knownHomeSections = d.stringArray(forKey: "knownHomeSections") ?? []
        largeTopPicks = d.object(forKey: "largeTopPicks") as? Bool ?? true
        generatedCovers = d.object(forKey: "generatedCovers") as? Bool ?? true
        resumeAfterLock = d.object(forKey: "resumeAfterLock") as? Bool ?? true
        customProfilePhoto = d.data(forKey: "customProfilePhoto")
    }

    private func save() {
        defaults.set(accent.rawValue, forKey: "accent")
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(libraryCategories.map(\.rawValue), forKey: "libraryCategories")
        defaults.set(homeOrder, forKey: "homeOrder")
        defaults.set(Array(hiddenHomeSections), forKey: "hiddenHomeSections")
        defaults.set(knownHomeSections, forKey: "knownHomeSections")
        defaults.set(largeTopPicks, forKey: "largeTopPicks")
        defaults.set(generatedCovers, forKey: "generatedCovers")
        defaults.set(resumeAfterLock, forKey: "resumeAfterLock")
        defaults.set(customProfilePhoto, forKey: "customProfilePhoto")
    }

    /// Applies your arrangement to Home's shelves and remembers any new shelf titles.
    func arrange(_ sections: [HomeSection]) -> [HomeSection] {
        let titles = sections.map(\.title)
        let newTitles = titles.filter { !knownHomeSections.contains($0) }
        if !newTitles.isEmpty { knownHomeSections += newTitles }
        let rank = Dictionary(homeOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return sections
            .filter { !hiddenHomeSections.contains($0.title) }
            .enumerated()
            .sorted { lhs, rhs in
                switch (rank[lhs.element.title], rank[rhs.element.title]) {
                case let (l?, r?): l < r
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}

extension Color {
    /// The accent colour chosen in Settings (Apple Music red by default).
    @MainActor static var musicAccent: Color { AppSettings.shared.accent.color }
}
