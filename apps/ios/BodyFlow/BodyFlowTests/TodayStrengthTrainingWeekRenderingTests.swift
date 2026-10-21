import SwiftUI
import XCTest

@testable import BodyFlow

@MainActor
final class TodayStrengthTrainingWeekRenderingTests: XCTestCase {
    func testLocalizedWeeklyLabelsExistInBothLanguages() throws {
        for language in SupportedAppLanguage.allCases {
            let portuguese = language == .portugueseBrazil
            XCTAssertEqual(try AppLocalization.string("today.records.workouts", for: language),
                           portuguese ? "Treinos confirmados" : "Confirmed workouts")
            XCTAssertEqual(try AppLocalization.string("today.strength-week.title", for: language),
                           portuguese ? "Força nesta semana" : "Strength this week")
            XCTAssertEqual(try AppLocalization.string("today.strength-week.unavailable", for: language),
                           portuguese ? "Acompanhamento semanal indisponível" : "Weekly tracking unavailable")
            XCTAssertEqual(try AppLocalization.string("today.strength-week.absent", for: language),
                           portuguese ? "Sem meta informada para esta semana" : "No target reported for this week")
        }
    }

    func testPresentationKeepsWeeklyScopeSeparateFromDailyDateAndObservation() throws {
        var section = TodayWeeklyStrengthContractTests.section()
        section["time_zone"] = "America/Los_Angeles"
        section["as_of_local_date"] = "2026-10-13"
        section["observed_at"] = "2026-10-14T00:30:00.123457Z"
        let response = try TodayWeeklyStrengthContractTests.response(section)
        let pt = TodayPresentation(snapshot: response.data, language: .portugueseBrazil)
        let en = TodayPresentation(snapshot: response.data, language: .englishUnitedStates)
        XCTAssertEqual(pt.header.localDate, "2026-07-20")
        XCTAssertEqual(pt.strengthTrainingWeek?.calendarLines, [
            "Semana de 12/10/2026", "Até 13/10/2026", "Fuso: America/Los_Angeles",
        ])
        XCTAssertEqual(en.strengthTrainingWeek?.calendarLines, [
            "Week of 10/12/2026", "As of 10/13/2026", "Time zone: America/Los_Angeles",
        ])
        let old = try BodyFlowTestFixtures.decodeInconsistentToday().data
        XCTAssertNil(TodayPresentation(snapshot: old).strengthTrainingWeek)
        XCTAssertEqual(pt.sectionOrder, TodayPresentation(snapshot: old).sectionOrder)
    }

    func testPositiveTargetDisplaysTheOfficialPercentageAndSourceWithoutClientMath() throws {
        var section = TodayWeeklyStrengthContractTests.section()
        section["percentage"] = 91
        let pt = try descriptor(section, .portugueseBrazil)
        XCTAssertEqual(pt.countText, "2 de 3")
        XCTAssertEqual(pt.percentageText, "91% da meta semanal")
        XCTAssertEqual(pt.sourceText, "Origem: plano de treino aceito")
        section["completed_strength_days"] = 4
        section["percentage"] = 100
        section["target_source"] = "informed_frequency"
        let en = try descriptor(section, .englishUnitedStates)
        XCTAssertEqual(en.countText, "4 of 3")
        XCTAssertEqual(en.percentageText, "100% of the weekly target")
        XCTAssertEqual(en.sourceText, "Source: reported frequency")
    }

    func testZeroAndAbsentTargetsKeepXWithoutPercentageOrAnInventedDenominator() throws {
        for language in SupportedAppLanguage.allCases {
            for kind in ["zero", "absent"] {
                var section = TodayWeeklyStrengthContractTests.section()
                section["target_availability"] = kind
                section["target_source"] = kind == "zero" ? "informed_frequency" : "absent"
                if kind == "zero" { section["planned_days"] = 0 }
                else { section["planned_days"] = NSNull() }
                section["percentage"] = NSNull()
                let value = try descriptor(section, language)
                XCTAssertEqual(value.countText, "2")
                XCTAssertNil(value.percentageText)
                XCTAssertEqual(value.targetDetail, language == .portugueseBrazil
                    ? (kind == "zero" ? "Frequência planejada: 0 dias" : "Sem meta informada para esta semana")
                    : (kind == "zero" ? "Planned frequency: 0 days" : "No target reported for this week"))
                XCTAssertEqual(value.calendarLines.count, 3)
                if kind == "absent" { XCTAssertNil(value.sourceText) }
            }
        }
    }

    func testNegativeStatusesExposeNoPartialMetricsOrInternalReason() throws {
        for language in SupportedAppLanguage.allCases {
            for status in ["unavailable", "conflict", "future_status"] {
                let value = try descriptor([
                    "status": status, "reason": "private_reason_001",
                    "completed_strength_days": 6, "planned_days": 7, "percentage": 99,
                ], language)
                XCTAssertTrue(value.calendarLines.isEmpty)
                XCTAssertNil(value.countText)
                XCTAssertNil(value.percentageText)
                XCTAssertNil(value.sourceText)
                XCTAssertNil(value.targetDetail)
                XCTAssertEqual(value.message, language == .portugueseBrazil
                    ? (status == "conflict" ? "O acompanhamento mudou. Atualize para consultar." : "Acompanhamento semanal indisponível")
                    : (status == "conflict" ? "Tracking changed. Refresh to check." : "Weekly tracking unavailable"))
            }
        }
    }

    func testNativeLayoutAndImagesInBothLanguagesThemesAndLargestText() throws {
        var section = TodayWeeklyStrengthContractTests.section()
        section["time_zone"] = "America/Argentina/Buenos_Aires"
        for language in SupportedAppLanguage.allCases {
            let value = try descriptor(section, language)
            for dark in [false, true] {
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let view = TodayStrengthTrainingWeekCard(descriptor: value, refresh: {})
                        .environment(\.bodyFlowReduceMotion, true)
                    for width in [CGFloat(320), CGFloat(430)] {
                        let measured = PremiumRenderingTestSupport.fittingSize(
                            view, width: width, dark: dark, size: size, locale: language.formattingLocale
                        )
                        XCTAssertEqual(measured.width, width, accuracy: 0.5)
                        XCTAssertGreaterThan(measured.height, 200)
                        XCTAssertLessThan(measured.height, 3_000)
                    }
                    let image = PremiumRenderingTestSupport.nativeImage(
                        view, width: 320, dark: dark, size: size, locale: language.formattingLocale
                    )
                    let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
                    attachment.name = "Strength week \(language.rawValue) \(dark ? "dark" : "light") \(size) 320pt"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testRecordsCompositionAddsTheCardAndRenderingDoesNotInvokeRefresh() throws {
        let snapshot = try TodayWeeklyStrengthContractTests.response(TodayWeeklyStrengthContractTests.section()).data
        let presentation = TodayPresentation(snapshot: snapshot)
        var calls = 0
        let records = TodayRecordsSection(
            workouts: presentation.workouts,
            strengthTrainingWeek: presentation.strengthTrainingWeek,
            refresh: { calls += 1 }
        )
        let oldRecords = TodayRecordsSection(workouts: presentation.workouts)
        let oldSize = PremiumRenderingTestSupport.fittingSize(oldRecords, width: 430, dark: false, size: .large, locale: Locale(identifier: "pt_BR"))
        let size = PremiumRenderingTestSupport.fittingSize(records, width: 430, dark: false, size: .large, locale: Locale(identifier: "pt_BR"))
        XCTAssertGreaterThan(size.height, oldSize.height + 200)
        XCTAssertEqual(presentation.workouts.count, 2)
        XCTAssertEqual(presentation.workouts.map(\.id), ["workout-z", "workout-a"])
        let image = PremiumRenderingTestSupport.nativeImage(records, width: 430, dark: false, size: .large, locale: Locale(identifier: "pt_BR"))
        attach(image, name: "Weekly card and preserved daily records PT")
        XCTAssertEqual(calls, 0)
    }

    func testNativeImagesOfZeroAbsentAndNegativeStatesAndInertRefresh() throws {
        for language in SupportedAppLanguage.allCases {
            for kind in ["zero", "absent", "unavailable", "conflict", "future_status"] {
                var section: [String: Any]
                if kind == "zero" || kind == "absent" {
                    section = TodayWeeklyStrengthContractTests.section()
                    section["target_availability"] = kind
                    section["target_source"] = kind == "zero" ? "informed_frequency" : "absent"
                    if kind == "zero" { section["planned_days"] = 0 }
                    else { section["planned_days"] = NSNull() }
                    section["percentage"] = NSNull()
                } else {
                    section = ["status": kind, "reason": "private_reason_001"]
                }
                let value = try descriptor(section, language)
                // No callback means an inert presentation; rendering a loading
                // action also must not call it. Its disabled state is reviewed
                // in source; the current Simulator AX probe is not evidence.
                let image = PremiumRenderingTestSupport.nativeImage(
                    TodayStrengthTrainingWeekCard(descriptor: value), width: 375,
                    dark: false, size: .large, locale: language.formattingLocale
                )
                attach(image, name: "Weekly \(kind) \(language.rawValue)")
                var calls = 0
                _ = PremiumRenderingTestSupport.fittingSize(
                    TodayStrengthTrainingWeekCard(descriptor: value, isRefreshing: true, refresh: { calls += 1 }),
                    width: 320, dark: false, size: .large, locale: language.formattingLocale
                )
                XCTAssertEqual(calls, 0)
            }
        }
    }

    private func attach(_ image: UIImage, name: String) {
        guard let bytes = image.pngData() else { XCTFail("Native PNG missing"); return }
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descriptor(
        _ section: [String: Any], _ language: SupportedAppLanguage
    ) throws -> TodayStrengthTrainingWeekDescriptor {
        let value = try XCTUnwrap(TodayWeeklyStrengthContractTests.response(section).data.strengthTrainingWeek)
        return TodayStrengthTrainingWeekDescriptor(section: value, language: language)
    }

}
