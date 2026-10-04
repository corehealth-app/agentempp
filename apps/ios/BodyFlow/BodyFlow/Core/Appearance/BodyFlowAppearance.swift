import Observation
import SwiftUI

/// How the app picks light or dark (Eduardo, 03/10: a light/dark control on
/// the first screen that also follows the time of day by itself).
/// - `schedule`: light by day, dark at night, from the clock alone.
/// - `system`: whatever the iPhone is set to.
/// - `light` / `dark`: fixed.
enum BodyFlowAppearanceMode: String, CaseIterable, Sendable, Identifiable {
    case schedule, system, light, dark

    var id: String { rawValue }

    var symbol: BodyFlowSymbol {
        switch self {
        case .schedule: .appearanceSchedule
        case .system: .appearanceSystem
        case .light: .appearanceLight
        case .dark: .appearanceDark
        }
    }

    /// Literal keys: an interpolated key would be looked up as a raw string.
    var titleKey: String.LocalizationValue {
        switch self {
        case .schedule: "appearance.schedule"
        case .system: "appearance.system"
        case .light: "appearance.light"
        case .dark: "appearance.dark"
        }
    }

    /// `nil` leaves the choice to the system.
    func colorScheme(at date: Date, calendar: Calendar = .current) -> ColorScheme? {
        switch self {
        case .schedule: BodyFlowAppearanceSchedule.isDaytime(date, calendar: calendar) ? .light : .dark
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Day is 06:00–17:59 on the phone's own clock; night is the rest. No
/// location is read (no sunrise table): the rule is simple and predictable.
enum BodyFlowAppearanceSchedule {
    nonisolated static let dayStartHour = 6
    nonisolated static let nightStartHour = 18

    nonisolated static func isDaytime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= dayStartHour && hour < nightStartHour
    }

    /// The next 06:00 or 18:00 strictly after `date`.
    nonisolated static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        let candidates = [dayStartHour, nightStartHour].compactMap { hour in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: 0, second: 0),
                matchingPolicy: .nextTime
            )
        }
        return candidates.min() ?? date.addingTimeInterval(3_600)
    }
}

/// The chosen mode and the clock it is evaluated against. The choice is a
/// device preference (not account data): it survives sign-out and never
/// leaves the phone. A demo/UI-test run keeps it in memory only and starts
/// on `system`, so the simulator's own appearance stays in charge.
@MainActor
@Observable
final class BodyFlowAppearanceStore {
    nonisolated static let defaultsKey = "pai.appearance.v1"

    private let defaults: UserDefaults?
    private(set) var now: Date
    var mode: BodyFlowAppearanceMode {
        didSet { defaults?.set(mode.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults?, fallback: BodyFlowAppearanceMode, now: Date = .now) {
        self.defaults = defaults
        self.now = now
        mode = defaults?.string(forKey: Self.defaultsKey).flatMap(BodyFlowAppearanceMode.init(rawValue:)) ?? fallback
    }

    /// Real accounts: stored on the device, light/dark by the clock until the
    /// person chooses. Demo runs: in memory, following the system.
    static func make(isDemo: Bool) -> BodyFlowAppearanceStore {
        isDemo
            ? BodyFlowAppearanceStore(defaults: nil, fallback: .system)
            : BodyFlowAppearanceStore(defaults: .standard, fallback: .schedule)
    }

    var colorScheme: ColorScheme? { mode.colorScheme(at: now) }

    func refreshClock(_ date: Date = .now) { now = date }

    /// Waits for each day/night boundary while the scheduled mode may apply.
    func followSchedule() async {
        while !Task.isCancelled {
            let boundary = BodyFlowAppearanceSchedule.nextBoundary(after: .now)
            let wait = max(boundary.timeIntervalSinceNow, 1)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            refreshClock()
        }
    }
}

/// The control itself: a native menu on the first screen with the four
/// modes; the glyph shows the current one.
@MainActor
struct BodyFlowAppearanceMenu: View {
    @Bindable var store: BodyFlowAppearanceStore
    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker(title, selection: $store.mode) {
                ForEach(BodyFlowAppearanceMode.allCases) { mode in
                    Label(verbatim: copy(mode.titleKey), symbol: mode.symbol).tag(mode)
                }
            }
        } label: {
            Label(verbatim: title, symbol: store.mode.symbol)
                .labelStyle(.iconOnly)
                .frame(
                    width: BodyFlowSpacing.minimumTapTarget + 1,
                    height: BodyFlowSpacing.minimumTapTarget + 1
                )
                .contentShape(Rectangle())
        }
        // Plain, like the refresh control beside it: the toolbar otherwise
        // shrinks the control below the 44 pt target.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(copy(store.mode.titleKey))
        .accessibilityIdentifier("today.appearance")
    }

    private var title: String { copy("appearance.title") }

    private func copy(_ key: String.LocalizationValue) -> String {
        let language = BodyFlowPresentationLanguage.resolve(locale)
        return (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
}
