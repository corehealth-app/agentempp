import SwiftUI

/// The app's SF Symbol vocabulary: one glyph per meaning, so the same idea
/// (error, waiting, refresh, chat, library…) never drifts between screens.
/// Screens reference the meaning; the raw name lives here only.
enum BodyFlowSymbol: String, CaseIterable, Sendable {
    // Navigation and actions
    case flow = "bubble.left.and.text.bubble.right"
    case library = "books.vertical"
    case history = "clock.arrow.circlepath"
    case refresh = "arrow.clockwise"
    case list = "list.bullet"
    case chevron = "chevron.right"
    case send = "arrow.up"
    case stop = "stop.fill"
    case summary = "doc.text.magnifyingglass"
    case compose = "text.alignleft"
    case photo = "photo"
    case audio = "waveform"

    // Status
    case info = "info.circle"
    case warning = "exclamationmark.triangle"
    case error = "exclamationmark.circle"
    case success = "checkmark.circle"
    case clock = "clock"
    case snoozed = "clock.badge"
    case skipped = "forward.circle"
    case empty = "tray"
    case unavailable = "nosign"
    case offline = "wifi.slash"

    // Today domains
    case energy = "bolt.heart"
    case protein = "leaf"
    case hydration = "drop"
    case meals = "fork.knife"
    case workouts = "figure.run"
    case routine = "checklist"
    case attention = "bell.badge"
    case block = "circle.hexagongrid"
    case calendar = "calendar"
    case protocolDocument = "doc.text"
    case netBalance = "plusminus"

    // Progress and achievements
    case xp = "sparkles"
    case level = "rosette"
    case streak = "flame"
    case longestStreak = "trophy"
    case completedBlocks = "checkmark.seal"
    case deficit = "arrow.down.circle"
    case medal = "medal.fill"
    case weight = "scalemass"
    case bodyComposition = "figure"

    // Profile, library and selection
    case person = "person.crop.circle"
    case preferences = "slider.horizontal.3"
    case categoryFilter = "line.3.horizontal.decrease.circle"
    case picker = "chevron.up.chevron.down"
    case save = "bookmark"
    case saved = "bookmark.fill"
    case unsave = "bookmark.slash"
    case article = "book.closed"
    case selected = "checkmark.circle.fill"
    case unselected = "circle"
    case close = "xmark"
    case confirm = "checkmark"

    var systemName: String { rawValue }
}

extension Image {
    init(symbol: BodyFlowSymbol) {
        self.init(systemName: symbol.systemName)
    }
}

extension Label where Title == Text, Icon == Image {
    /// Localized title, exactly like SwiftUI's own `Label(_:systemImage:)`:
    /// a string literal here is a localization key.
    init(_ titleKey: LocalizedStringKey, symbol: BodyFlowSymbol) {
        self.init(titleKey, systemImage: symbol.systemName)
    }

    /// Already-resolved runtime text (a value, or a string the screen has
    /// localized itself). Spelled out so a localization key can never reach
    /// this overload and render as its own raw key.
    init(verbatim title: String, symbol: BodyFlowSymbol) {
        self.init {
            Text(verbatim: title)
        } icon: {
            Image(symbol: symbol)
        }
    }
}
