import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// A plan's notes are free text written by the plan generator (up to 500
/// characters). Seen on the staging plan on 2026-10-05 — light mode, regular
/// text size, 402 pt screen: in the two-column row the note became a narrow
/// right-aligned column about twenty lines tall beside "Observações".
@MainActor
final class PlanNotesRenderingTests: XCTestCase {
    /// The share of the card's content width the note's ink must span: 0.9,
    /// that is 279.9 of 311 pt on the 375 pt phone and 304.2 of 338 pt on the
    /// 402 pt one.
    ///
    /// Below its label, the paragraph wraps at word boundaries of the whole
    /// width, so each of its ten or more lines falls short of the edge by
    /// less than the word that did not fit, and the widest of them by a few
    /// characters at most. Beside its label, the note can never get more
    /// than the card minus the label and the row's three gaps: measured on
    /// the two-column row, 55.6 % (375 pt) and 58.9 % (402 pt) under
    /// "Observações", 72.7 % and 75.1 % under "Notes". 0.9 sits between the
    /// two with room on both sides.
    private static let minimumNoteWidthShare: CGFloat = 0.9

    /// 375 is the narrow phone; 402 is the screen the defect was seen on.
    private static let viewports: [CGFloat] = [375, 402]

    func testLongNoteUsesTheCardWidthBelowItsLabelAtRegularSize() throws {
        for language in SupportedAppLanguage.allCases {
            let note = Self.note(for: language)
            XCTAssertEqual(note.count, 400, "Fixture must be the 400-character note")
            let presentation = PlanPresentation(
                snapshot: Self.snapshot(note: note), language: language
            )
            let label = try XCTUnwrap(
                presentation.trainingFields.first { $0.id == "plan.training.notes" }
            ).title
            let locale = language.formattingLocale
            // The Plan tab as `PlanReadContent` lays it out: the cards inset
            // by the screen gutter, on the app's canvas.
            let screen = PlanContentView(presentation: presentation)
                .padding(BodyFlowSpacing.md)
                .background(BodyFlowColor.background)
                .environment(\.locale, locale)

            for viewport in Self.viewports {
                for dark in [false, true] {
                    let variant = "\(language.rawValue)-\(Int(viewport))-\(dark ? "dark" : "light")"
                    // The off-screen renderer: every pixel is measured, and a
                    // window snapshot taken before the first frame is blank.
                    let image = PremiumRenderingTestSupport.image(
                        screen, width: viewport, dark: dark, size: .large
                    )
                    let picture = XCTAttachment(
                        data: try XCTUnwrap(image.pngData()),
                        uniformTypeIdentifier: "public.png"
                    )
                    picture.name = "plan-notes-\(variant)"
                    picture.lifetime = .keepAlways
                    add(picture)

                    // Screen gutter plus card padding on each side.
                    let contentLeft = 2 * BodyFlowSpacing.md
                    let contentWidth = viewport - 4 * BodyFlowSpacing.md
                    let labelLine = PremiumRenderingTestSupport.fittingSize(
                        Text(label).font(BodyFlowTypography.body),
                        width: contentWidth, dark: dark, size: .large, locale: locale
                    ).height
                    // The note alone, in the row's value font, wrapped at the
                    // card's whole width: every line of it.
                    let noteLine = PremiumRenderingTestSupport.fittingSize(
                        Text("Ag").font(BodyFlowTypography.headline),
                        width: contentWidth, dark: dark, size: .large, locale: locale
                    ).height
                    let wholeNote = PremiumRenderingTestSupport.fittingSize(
                        Text(note).font(BodyFlowTypography.headline)
                            .fixedSize(horizontal: false, vertical: true),
                        width: contentWidth, dark: dark, size: .large, locale: locale
                    ).height
                    let row = try notesRow(in: image, viewport: viewport, dark: dark)

                    let measured: String = [
                        "\(variant): \(row)",
                        "card content \(points(contentWidth)) pt wide from x \(points(contentLeft))",
                        "note ink spans \(points(100 * row.noteWidth / contentWidth)) % of it",
                        "one label line \(points(labelLine)) pt",
                        "the whole note at the card's width \(points(wholeNote)) pt tall",
                        "one line of it \(points(noteLine)) pt",
                    ].joined(separator: "; ")
                    let record = XCTAttachment(string: measured)
                    record.name = "plan-notes-measured-\(variant)"
                    record.lifetime = .keepAlways
                    add(record)

                    XCTAssertGreaterThan(
                        wholeNote, 4 * noteLine,
                        "Fixture must be a paragraph of several lines; \(measured)"
                    )
                    // No line limit: an ellipsis would cost at least one line.
                    XCTAssertGreaterThanOrEqual(
                        row.noteHeight + noteLine, wholeNote,
                        "Every line of the note must be painted; \(measured)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        row.noteWidth, Self.minimumNoteWidthShare * contentWidth,
                        "The note must use the card's width: its ink spans "
                            + "\(points(row.noteWidth)) of \(points(contentWidth)) pt; \(measured)"
                    )
                    XCTAssertLessThanOrEqual(
                        row.noteLeft, contentLeft + BodyFlowSpacing.xxs,
                        "The note must start at the card's leading edge "
                            + "(x \(points(contentLeft))), not beside its label; \(measured)"
                    )
                    guard row.noteTop - row.labelTop >= labelLine else {
                        XCTFail("The label must have its own line above the note: the note's "
                            + "first ink is \(points(row.noteTop - row.labelTop)) pt below the "
                            + "label's, one label line is \(points(labelLine)) pt; \(measured)")
                        continue
                    }
                    XCTAssertLessThanOrEqual(
                        try XCTUnwrap(row.labelLeft), contentLeft + BodyFlowSpacing.xxs,
                        "The label above the note must start at the card's leading edge; "
                            + measured
                    )
                }
            }
        }
    }

    /// VoiceOver reads the label and the note as one element, label first.
    func testLongNoteIsReadWithItsLabelAsOneElement() throws {
        for language in SupportedAppLanguage.allCases {
            let note = Self.note(for: language)
            let presentation = PlanPresentation(
                snapshot: Self.snapshot(note: note), language: language
            )
            let label = try XCTUnwrap(
                presentation.trainingFields.first { $0.id == "plan.training.notes" }
            ).title
            let probes = PremiumRenderingTestSupport.accessibilityProbe(
                PlanContentView(presentation: presentation)
                    .environment(\.locale, language.formattingLocale),
                width: 375, size: .large
            )
            let reading = probes.filter { $0.label.contains(note) }
            XCTAssertEqual(
                reading.count, 1,
                "The note is read once: \(language.rawValue), \(probes.map(\.label))"
            )
            XCTAssertTrue(
                reading.first?.label.hasPrefix(label) == true,
                "Label and note are one element, label first: \(language.rawValue), \(reading)"
            )
        }
    }

    // MARK: - Fixture

    /// Begins as the note in the print; the rest is synthetic and brings it
    /// to the 400 characters of the real one. The generator's text is not
    /// translated: the English note stands for a plan written in English.
    private static func note(for language: SupportedAppLanguage) -> String {
        switch language {
        case .portugueseBrazil:
            "Plano Full Body otimizado para 1x/semana com ênfase em peito e tríceps. "
                + "Comece cada sessão com cinco minutos de aquecimento articular e 2 séries "
                + "leves do primeiro exercício. Priorize a técnica antes da carga: se a "
                + "postura falhar, reduza o peso. Descanse o tempo indicado entre as séries "
                + "e anote as cargas usadas para acompanhar a evolução. Se sentir dor "
                + "articular, pare o exercício e ajuste o treino."
        case .englishUnitedStates:
            "Full Body plan optimized for one session per week with emphasis on chest "
                + "and triceps. Start every session with five minutes of joint warm-up and "
                + "two light sets of the first exercise. Put technique ahead of load: if "
                + "your posture breaks down, reduce the weight. Rest for the indicated time "
                + "between sets and note the loads used to follow your progress. If a joint "
                + "hurts, stop the exercise and adjust it."
        }
    }

    /// The whole training card: four fields of its own, the note last, then
    /// the three provenance rows.
    private static func snapshot(note: String) -> PlanSnapshot {
        PlanSnapshot(
            training: TrainingPlanSnapshot(
                id: "training-notes",
                planType: "full_body",
                daysPerWeek: 1,
                equipmentSummary: "Halteres e banco",
                generatedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_791_115_200)),
                validUntil: APITimestamp(value: Date(timeIntervalSince1970: 1_793_707_200)),
                version: 2,
                notes: note
            ),
            nutrition: []
        )
    }

    // MARK: - Painted pixels

    /// Measures what is painted, as the eye sees the row. The notes row is
    /// the card's last field before the provenance block, between its last
    /// two dividers; there only the note is painted in the primary text
    /// color — its label is in the secondary one.
    private func notesRow(in image: UIImage, viewport: CGFloat, dark: Bool) throws -> PaintedNotesRow {
        let source = try XCTUnwrap(image.cgImage)
        let width = source.width
        let height = source.height
        let scale = CGFloat(width) / viewport
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        try buffer.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let pixels = buffer
        func isNear(_ x: Int, _ y: Int, _ hex: UInt32, tolerance: Int) -> Bool {
            let offset = (y * width + x) * 4
            return abs(Int(pixels[offset]) - Int((hex >> 16) & 0xFF)) <= tolerance
                && abs(Int(pixels[offset + 1]) - Int((hex >> 8) & 0xFF)) <= tolerance
                && abs(Int(pixels[offset + 2]) - Int(hex & 0xFF)) <= tolerance
        }

        let cardFill = BodyFlowColor.hex(.backgroundSecondary, dark: dark)
        let noteColor = BodyFlowColor.hex(.textPrimary, dark: dark)
        let contentLeft = 2 * BodyFlowSpacing.md
        let contentRight = viewport - 2 * BodyFlowSpacing.md
        let content = Int(contentLeft * scale)..<Int(contentRight * scale)
        // Inside the card's own padding, where nothing is ever painted: text
        // may overhang the content edge by a side bearing, never by this much.
        let paddingLeft = Int((contentLeft - BodyFlowSpacing.xs) * scale)
        let paddingRight = Int((contentRight + BodyFlowSpacing.xs) * scale)

        // A divider is the only thing painted across the whole content width.
        var dividers: [ClosedRange<Int>] = []
        for y in 0..<height where isNear(paddingLeft, y, cardFill, tolerance: 4) {
            var painted = 0
            for x in content where !isNear(x, y, cardFill, tolerance: 4) { painted += 1 }
            guard painted * 20 >= content.count * 19 else { continue }
            if let last = dividers.last, last.upperBound + 1 == y {
                dividers[dividers.count - 1] = last.lowerBound...y
            } else {
                dividers.append(y...y)
            }
        }
        XCTAssertEqual(
            dividers.count, 4,
            "The fixture card has four fields of its own and a provenance block: \(dividers)"
        )
        guard dividers.count >= 2 else { throw NotesRowNotFound() }
        let band = (dividers[dividers.count - 2].upperBound + 1)..<dividers[dividers.count - 1].lowerBound

        var inkRows: [(y: Int, left: Int)] = []
        var noteRows: [Int] = []
        var noteLeft = Int.max
        var noteRight = Int.min
        for y in band {
            var inkLeft: Int?
            var hasNote = false
            for x in paddingLeft..<paddingRight {
                if inkLeft == nil, !isNear(x, y, cardFill, tolerance: 24) { inkLeft = x }
                if isNear(x, y, noteColor, tolerance: 48) {
                    hasNote = true
                    noteLeft = min(noteLeft, x)
                    noteRight = max(noteRight, x)
                }
            }
            if let inkLeft { inkRows.append((y, inkLeft)) }
            if hasNote { noteRows.append(y) }
        }
        let labelTop = try XCTUnwrap(inkRows.first?.y, "The notes row must paint something")
        let noteTop = try XCTUnwrap(noteRows.first, "The notes row must paint the note")
        let noteBottom = try XCTUnwrap(noteRows.last)
        let labelLeft = inkRows.filter { $0.y < noteTop }.map(\.left).min()
        return PaintedNotesRow(
            labelTop: CGFloat(labelTop) / scale,
            labelLeft: labelLeft.map { CGFloat($0) / scale },
            noteTop: CGFloat(noteTop) / scale,
            noteLeft: CGFloat(noteLeft) / scale,
            noteWidth: CGFloat(noteRight - noteLeft + 1) / scale,
            noteHeight: CGFloat(noteBottom - noteTop + 1) / scale
        )
    }
}

private struct NotesRowNotFound: Error {}

/// Where the notes row painted its label and its note, in points.
private struct PaintedNotesRow: CustomStringConvertible {
    let labelTop: CGFloat
    let labelLeft: CGFloat?
    let noteTop: CGFloat
    let noteLeft: CGFloat
    let noteWidth: CGFloat
    let noteHeight: CGFloat

    var description: String {
        "label ink from y \(points(labelTop)) x \(labelLeft.map(points) ?? "(none above the note)"), "
            + "note ink from y \(points(noteTop)) x \(points(noteLeft)), "
            + "\(points(noteWidth)) pt wide, \(points(noteHeight)) pt tall"
    }
}

private func points(_ value: CGFloat) -> String {
    String(format: "%.1f", Double(value))
}
