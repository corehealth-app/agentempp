import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class BodyFlowPremiumRenderingTests: XCTestCase {
    private let sizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    func testAllTabsAndStateFamiliesAXXXL() throws {
        let states: [ScreenState] = [
            .loading, .empty, .recoverableError, .offline, .unavailable,
        ]

        XCTAssertEqual(
            BodyFlowCard { EmptyView() }.surface,
            .card,
            "Reviewed public cards should use the semantic card surface by default"
        )

        for language in SupportedAppLanguage.allCases {
            let locale = language.formattingLocale
            for dark in [false, true] {
                for width: CGFloat in [375, 393, 430] {
                    for size in sizes {
                        for tab in AppTab.allCases {
                            let title = tab.title(for: language)
                            let label = Button(title, action: {})
                                .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
                                .accessibilityIdentifier("convergence.tab.\(tab.rawValue)")
                            let frame = PremiumRenderingTestSupport.fittingSize(
                                label,
                                width: width,
                                dark: dark,
                                size: size,
                                locale: locale
                            )
                            XCTAssertLessThanOrEqual(frame.width, width + 1)
                            XCTAssertGreaterThanOrEqual(frame.height, 44)
                            let probe = PremiumRenderingTestSupport.accessibilityProbe(
                                label,
                                width: width,
                                size: size
                            )
                            XCTAssertEqual(
                                probe.filter { $0.label == title && $0.isButton }.count,
                                1,
                                "One accessible tab label: \(tab) / \(language) / \(size)"
                            )
                            XCTAssertTrue(probe.contains {
                                $0.label == title && $0.frame.width >= 44 && $0.frame.height >= 44
                            })
                        }

                        for state in states {
                            let view = ScreenStateView(
                                state: state,
                                retryAction: {},
                                accessibilityIdentifier: "convergence.\(state.accessibilityIdentifier)"
                            )
                            let frame = PremiumRenderingTestSupport.fittingSize(
                                view,
                                width: width,
                                dark: dark,
                                size: size,
                                locale: locale
                            )
                            XCTAssertLessThanOrEqual(frame.width, width + 1)
                            XCTAssertGreaterThan(frame.height, 0)
                        }
                    }
                }
            }
        }
    }

    func testNativeComponentsAcrossPresentationMatrix() throws {
        for language in SupportedAppLanguage.allCases {
            let locale = language.formattingLocale
            let label = language == .portugueseBrazil
                ? "Continuar com minha jornada personalizada e revisar todas as informações"
                : "Continue my personalized journey and review all the information"
            let body = language == .portugueseBrazil
                ? "Informações sintéticas para testar a leitura completa. Este cartão contém um texto longo, sem omitir detalhes ou modificar dados."
                : "Synthetic information for testing complete reading. This card contains a long text, without omitting details or changing data."
            for dark in [false, true] {
                for width: CGFloat in [375, 393, 430] {
                    for (index, size) in sizes.enumerated() {
                        try autoreleasepool {
                        let innerWidth = width - 2 * BodyFlowSpacing.screenGutter(usableWidth: width)
                        let textHeight = PremiumRenderingTestSupport.fittingSize(
                            Text(label).font(BodyFlowTypography.button)
                                .fixedSize(horizontal: false, vertical: true),
                            width: innerWidth - 32, dark: dark, size: size, locale: locale
                        ).height
                        for role in BodyFlowButtonRole.allCases {
                            let button = Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: role))
                            let frame = PremiumRenderingTestSupport.fittingSize(
                                button, width: innerWidth, dark: dark, size: size, locale: locale
                            )
                            XCTAssertGreaterThanOrEqual(frame.width, 44)
                            XCTAssertGreaterThanOrEqual(frame.height, 44)
                            XCTAssertGreaterThanOrEqual(frame.height + 1, textHeight + 24,
                                "Full label must fit: \(language) \(dark) \(width) \(size) \(role)")
                        }
                        let bodyHeight = PremiumRenderingTestSupport.fittingSize(
                            Text(body).font(BodyFlowTypography.body), width: innerWidth - 32,
                            dark: dark, size: size, locale: locale
                        ).height
                        let card = BodyFlowCard(surface: .card) { Text(body).font(BodyFlowTypography.body) }
                        let cardFrame = PremiumRenderingTestSupport.fittingSize(
                            card, width: innerWidth, dark: dark, size: size, locale: locale
                        )
                        XCTAssertGreaterThanOrEqual(cardFrame.height + 1, bodyHeight + 32)
                        let field = TextField("QA", text: .constant("QA")).font(BodyFlowTypography.body).bodyFlowField()
                        let fieldFrame = PremiumRenderingTestSupport.fittingSize(
                            field, width: innerWidth, dark: dark, size: size, locale: locale
                        )
                        XCTAssertGreaterThanOrEqual(fieldFrame.height, 44)
                        XCTAssertGreaterThanOrEqual(fieldFrame.width, 44)
                        let nativeFieldImage = PremiumRenderingTestSupport.nativeImage(
                            field.padding(BodyFlowSpacing.md).background(BodyFlowColor.color(.backgroundPrimary)),
                            width: width, dark: dark, size: size, locale: locale
                        )
                        let fieldAttachment = XCTAttachment(data: try XCTUnwrap(nativeFieldImage.pngData()), uniformTypeIdentifier: "public.png")
                        fieldAttachment.name = "s0-native-field-\(dark ? "dark" : "light")-\(language.rawValue)-\(Int(width))-DT\(index)"
                        fieldAttachment.lifetime = .keepAlways
                        add(fieldAttachment)
                        // Split the native canvas, not the font or content: very tall
                        // AX5 canvases exceed ImageRenderer's bitmap backing limit.
                        for panel in 0..<3 {
                            let image = PremiumRenderingTestSupport.image(
                                fixture(label: label, body: body, locale: locale, width: width, panel: panel),
                                width: width, dark: dark, size: size
                            )
                            XCTAssertEqual(image.size.width, width, accuracy: 0.5)
                            XCTAssertGreaterThan(image.size.height, 44)
                            let data = try XCTUnwrap(image.pngData(), "Native bitmap: \(image.size), DT\(index), panel\(panel)")
                            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                            attachment.name = "s0-components-\(dark ? "dark" : "light")-\(language.rawValue)-\(Int(width))-DT\(index)-panel\(panel)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                        }
                    }
                }
            }
        }
    }

    func testNativeButtonAccessibility() throws {
        let label = "Continuar / Continue"
        for role in BodyFlowButtonRole.allCases {
        for size in [DynamicTypeSize.large, .accessibility5] {
        let probe = PremiumRenderingTestSupport.accessibilityProbe(
            Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: role))
                .accessibilityIdentifier("fixture.button"),
            width: 375, size: size
        )
        XCTAssertTrue(probe.contains { $0.label == label && $0.isButton && $0.frame.width >= 44 && $0.frame.height >= 44 },
            "Styled native button must retain one readable button target: \(probe)")
        XCTAssertEqual(probe.filter { $0.label == label && $0.isButton }.count, 1)
        }
        }
        let disabled = PremiumRenderingTestSupport.accessibilityProbe(
            Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: .primary)).disabled(true),
            width: 375
        )
        XCTAssertTrue(disabled.contains { $0.label == label && $0.isButton && !$0.isEnabled })
    }

    func testNativeFieldPreservesBaselineAccessibilityRepresentation() {
        for size in [DynamicTypeSize.large, .accessibility5] {
            let baseline = PremiumRenderingTestSupport.accessibilityProbe(
                TextField("QA", text: .constant("")).accessibilityLabel("QA"), width: 375, size: size
            )
            let probe = PremiumRenderingTestSupport.accessibilityProbe(
                TextField("QA", text: .constant("")).accessibilityLabel("QA").textContentType(.username)
                    .keyboardType(.emailAddress).bodyFlowField(), width: 375, size: size
            )
            // UIKit-backed fields do not expose AX nodes in this unit host even
            // without the modifier. Preserve observed baseline representation;
            // verify actual control identity/properties separately, not a fake node.
            XCTAssertEqual(probe.map(\.label), baseline.map(\.label))
            XCTAssertEqual(probe.map(\.isButton), baseline.map(\.isButton))
            XCTAssertEqual(probe.map(\.isEnabled), baseline.map(\.isEnabled))
        }
    }

    func testNativeEditableFieldPreservesControlAndConfiguration() {
        for size in [DynamicTypeSize.large, .accessibility5] {
            let original = TextField("QA", text: .constant("")).font(BodyFlowTypography.body)
                .textContentType(.username).keyboardType(.emailAddress)
            let baseline = PremiumRenderingTestSupport.nativeFields(original, width: 375, size: size)
            let fields = PremiumRenderingTestSupport.nativeFields(
                original.bodyFlowField(),
                width: 375, size: size
            )
            XCTAssertEqual(fields.count, 1, "Exactly one native editable field: \(fields)")
            XCTAssertEqual(baseline.count, 1)
            for (field, unstyled) in zip(fields, baseline) {
                XCTAssertEqual(field.placeholder, "QA")
                XCTAssertEqual(field.keyboardType, .emailAddress)
                XCTAssertEqual(field.contentType, .username)
                XCTAssertEqual(field.isEnabled, unstyled.isEnabled)
                XCTAssertEqual(field.isSecure, unstyled.isSecure)
                XCTAssertEqual(field.isAccessibilityElement, unstyled.isAccessibilityElement)
                XCTAssertEqual(field.accessibilityLabel, unstyled.accessibilityLabel)
                XCTAssertEqual(field.traits, unstyled.traits)
                XCTAssertEqual(field.fontSize, unstyled.fontSize)
            }
            // Tap/chrome target includes padding. Inner font/glyph bounds are
            // deliberately native and must not be forced to a 44-point font box.
            let frame = PremiumRenderingTestSupport.fittingSize(original.bodyFlowField(), width: 375,
                dark: false, size: size, locale: Locale(identifier: "pt_BR"))
            XCTAssertGreaterThanOrEqual(frame.width, 44)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            let secure = PremiumRenderingTestSupport.nativeFields(
                SecureField("QA", text: .constant("")).textContentType(.newPassword).bodyFlowField(),
                width: 375, size: size
            )
            XCTAssertEqual(secure.count, 1)
            XCTAssertTrue(secure.allSatisfy { $0.isSecure && $0.contentType == .newPassword })
        }
    }

    func testAccessibilityAdaptationsKeepOpaqueSurfacesAndNoMotion() {
        XCTAssertEqual(BodyFlowMotion.duration(reduceMotion: true, disclosure: false), 0)
        XCTAssertEqual(BodyFlowMotion.duration(reduceMotion: true, disclosure: true), 0)
        for dark in [false, true] {
            for role in BodyFlowColor.Role.allCases {
                let color = UIColor(BodyFlowColor.color(role)).resolvedColor(with: UITraitCollection {
                    $0.userInterfaceStyle = dark ? .dark : .light
                    $0.accessibilityContrast = .high
                })
                XCTAssertEqual(color.cgColor.alpha, 1)
            }
        }
    }

    func testReviewedPublicCallsitesDoNotKeepHardCodedLanguageDebt() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reviewedSources: [(path: String, forbidden: [String])] = [
            (
                "BodyFlow/Features/Mascot/MascotCardView.swift",
                ["Button(\"Tentar novamente\")", "?? \"indisponível\"", "\"Equilibrada\""]
            ),
            (
                "BodyFlow/Features/Today/TodayRecommendationsSection.swift",
                [
                    "Text(\"Tentar novamente\")",
                    "static let heading = \"Conteúdos para hoje\"",
                    "static let emptyCopy = \"Nenhum conteúdo selecionado para hoje\"",
                    "recoverableState(\"Sem conexão para carregar conteúdos.\")",
                    "\"min de leitura\"",
                ]
            ),
            (
                "BodyFlow/Features/Today/TodayRecordsSection.swift",
                ["\"Referência confirmada\"", "\"Origem não informada\""]
            ),
            (
                "BodyFlow/Features/Shared/FeatureDetailView.swift",
                ["Text(route.tab.title)"]
            ),
            (
                "BodyFlow/Features/Library/BodyFlowMarkdownView.swift",
                ["\"Lista ordenada\"", "\"Item da lista\""]
            ),
            (
                "BodyFlow/Features/Library/PublishedContentDetailView.swift",
                [
                    "Label(presentation.message",
                    "Text(presentation.message)",
                    "Button(action == .back ? \"Voltar\" : \"Biblioteca\")",
                ]
            ),
        ]

        for review in reviewedSources {
            let source = try String(
                contentsOf: projectRoot.appendingPathComponent(review.path),
                encoding: .utf8
            )
            for literal in review.forbidden {
                XCTAssertFalse(
                    source.contains(literal),
                    "Reviewed public copy must use the bilingual catalog: \(review.path) / \(literal)"
                )
            }
        }
    }

    func testReviewedMaterialHasOpaqueReduceTransparencyFallback() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "BodyFlow/Features/Profile/CoachPersonaPickerView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(source.contains("BodyFlowColor.color(.surfaceElevated)"))
    }

    private func fixture(label: String, body: String, locale: Locale, width: CGFloat, panel: Int) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text("Performe AI · Flow").font(BodyFlowTypography.screenTitle)
            Text("Native component baseline · QA").font(BodyFlowTypography.caption)
            if panel == 0 {
                BodyFlowCard(surface: .legacy) { Text(body).font(BodyFlowTypography.body) }
                BodyFlowCard(surface: .card) { Text(body).font(BodyFlowTypography.body) }
                BodyFlowCard(surface: .hero) { Text(label).font(BodyFlowTypography.cardTitle) }
            } else if panel == 1 {
                ForEach(Array(BodyFlowButtonRole.allCases.prefix(3).enumerated()), id: \.offset) { _, role in
                    Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: role))
                }
            } else {
                Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: .destructive))
                Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: .primary)).disabled(true)
                StaleDataBanner()
            }
        }
        .padding(BodyFlowSpacing.screenGutter(usableWidth: width))
        .foregroundStyle(BodyFlowColor.color(.textPrimary))
        .background(BodyFlowColor.color(.backgroundPrimary))
        .environment(\.locale, locale)
    }
}
