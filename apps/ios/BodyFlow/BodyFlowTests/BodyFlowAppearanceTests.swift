import Foundation
import SwiftUI
import Testing

@testable import BodyFlow

@Suite("Appearance: light, dark, by the clock")
struct BodyFlowAppearanceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
    }

    @Test("Day is 06:00–17:59; night is the rest")
    func schedule() {
        #expect(BodyFlowAppearanceMode.schedule.colorScheme(at: date(6), calendar: calendar) == .light)
        #expect(BodyFlowAppearanceMode.schedule.colorScheme(at: date(17, 59), calendar: calendar) == .light)
        #expect(BodyFlowAppearanceMode.schedule.colorScheme(at: date(18), calendar: calendar) == .dark)
        #expect(BodyFlowAppearanceMode.schedule.colorScheme(at: date(5, 59), calendar: calendar) == .dark)
        #expect(BodyFlowAppearanceMode.schedule.colorScheme(at: date(0), calendar: calendar) == .dark)
    }

    @Test("Fixed modes ignore the clock; system leaves the choice to iOS")
    func fixedModes() {
        for hour in [3, 12, 21] {
            #expect(BodyFlowAppearanceMode.light.colorScheme(at: date(hour), calendar: calendar) == .light)
            #expect(BodyFlowAppearanceMode.dark.colorScheme(at: date(hour), calendar: calendar) == .dark)
            #expect(BodyFlowAppearanceMode.system.colorScheme(at: date(hour), calendar: calendar) == nil)
        }
    }

    @Test("The next boundary is the next 06:00 or 18:00")
    func boundaries() {
        #expect(BodyFlowAppearanceSchedule.nextBoundary(after: date(12), calendar: calendar) == date(18))
        #expect(BodyFlowAppearanceSchedule.nextBoundary(after: date(5, 30), calendar: calendar) == date(6))
        let afterNight = BodyFlowAppearanceSchedule.nextBoundary(after: date(20), calendar: calendar)
        #expect(calendar.component(.hour, from: afterNight) == 6)
        #expect(calendar.component(.day, from: afterNight) == 4)
        #expect(BodyFlowAppearanceSchedule.nextBoundary(after: date(18), calendar: calendar) > date(18))
    }

    @MainActor
    @Test("Real runs default to the clock and remember the choice; demo runs follow the system in memory")
    func store() throws {
        let suite = "appearance-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = BodyFlowAppearanceStore(defaults: defaults, fallback: .schedule, now: date(12))
        #expect(first.mode == .schedule)
        first.mode = .light
        #expect(first.colorScheme == .light)
        #expect(BodyFlowAppearanceStore(defaults: defaults, fallback: .schedule, now: date(19)).mode == .light)

        let demo = BodyFlowAppearanceStore.make(isDemo: true)
        #expect(demo.mode == .system && demo.colorScheme == nil)
        demo.mode = .dark
        #expect(BodyFlowAppearanceStore.make(isDemo: true).mode == .system)
    }

    @Test("Every mode has its own glyph and copy in both languages", arguments: SupportedAppLanguage.allCases)
    func copy(_ language: SupportedAppLanguage) throws {
        #expect(Set(BodyFlowAppearanceMode.allCases.map(\.symbol)).count == 4)
        let titles = try BodyFlowAppearanceMode.allCases.map { try AppLocalization.string($0.titleKey, for: language) }
        #expect(Set(titles).count == 4 && titles.allSatisfy { !$0.isEmpty && !$0.hasPrefix("appearance.") })
        #expect(try AppLocalization.string("appearance.title", for: language) == (language == .portugueseBrazil ? "Aparência" : "Appearance"))
    }
}
