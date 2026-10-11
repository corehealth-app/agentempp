import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class BodyFlowPremiumRenderingTests: XCTestCase {
    func testReadOnlyProtocolMessageClosesWithoutTheOnboardingAction() {
        let paragraphs = ["First server paragraph", "Same", "Same", "Last server paragraph"]
        let welcome = ProtocolWelcome(protocol: .maintenance, paragraphs: paragraphs)
        for language in SupportedAppLanguage.allCases {
            let view = ProtocolMessageView(welcome: welcome, context: .currentObjective, onContinue: {})
                .environment(\.locale, language.formattingLocale)
            let probe = PremiumRenderingTestSupport.accessibilityProbe(view, width: 375)
            let close = language == .portugueseBrazil ? "Fechar" : "Close"
            XCTAssertTrue(probe.contains { $0.isButton && $0.label == close })
            XCTAssertFalse(probe.contains { $0.isButton && ($0.label == "Ir para Hoje" || $0.label == "Go to Today") })
            XCTAssertEqual(probe.filter { $0.label == "Same" }.count, 2)
            XCTAssertTrue(probe.contains { $0.label == "Last server paragraph" })
            for width: CGFloat in [375, 393, 430] {
                for dark in [false, true] {
                    let regular = PremiumRenderingTestSupport.fittingSize(view, width: width, dark: dark, size: .large, locale: language.formattingLocale)
                    let large = PremiumRenderingTestSupport.fittingSize(view, width: width, dark: dark, size: .accessibility5, locale: language.formattingLocale)
                    XCTAssertLessThanOrEqual(large.width, width + 1)
                    XCTAssertGreaterThan(large.height, regular.height)
                }
            }
        }
    }

    func testObjectiveWithoutServerDecisionExposesNoSelectableButtons() {
        let model = OnboardingFlowModel.preview(step: .objective, decision: nil)
        let probe = PremiumRenderingTestSupport.accessibilityProbe(
            ObjectiveStepView(model: model), width: 375, size: .accessibility5
        )
        XCTAssertFalse(probe.contains { $0.isButton },
            "No objective is selectable before a server decision: \(probe)")
    }

    func testServerAssignedObjectiveKeepsStaticSelectionAndClosedDisclosure() async throws {
        let model = await E3Fixtures.model(repository: E3Repository(decision: E3Fixtures.assigned))
        await model.continueFromCurrentStep()
        for language in SupportedAppLanguage.allCases {
            for dark in [false, true] {
                for width: CGFloat in [375, 393, 430] {
                    let view = ObjectiveStepView(model: model).environment(\.locale, language.formattingLocale)
                    let probe = PremiumRenderingTestSupport.accessibilityProbe(view, width: width, size: .accessibility5)
                    XCTAssertTrue(probe.contains { $0.label.contains("Server assigned notice") })
                    XCTAssertFalse(probe.contains { $0.isButton && ($0.label.contains("Recomposição") || $0.label.contains("recomposition")) })
                    XCTAssertFalse(probe.contains { $0.label.contains("Server gain blocked") }, "Disclosure starts closed")
                    let image = PremiumRenderingTestSupport.nativeImage(view, width: width, dark: dark,
                        size: .accessibility5, locale: language.formattingLocale)
                    let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
                    attachment.name = "e3-assigned-native-\(language.rawValue)-\(dark ? "dark" : "light")-\(Int(width))-axxxl"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testLongProtocolMessagePreservesAllParagraphsAndScales() {
        for language in SupportedAppLanguage.allCases {
            let paragraphs = OnboardingPreviewRepository.welcomeParagraphs(locale: language.rawValue)
            XCTAssertGreaterThanOrEqual(paragraphs.joined(separator: "\n\n").count, 2850)
            XCTAssertLessThanOrEqual(paragraphs.joined(separator: "\n\n").count, 2900)
            let view = ProtocolMessageView(welcome: .init(protocol: .maintenance, paragraphs: paragraphs), onContinue: {})
            for dark in [false, true] {
                for width: CGFloat in [375, 393, 430] {
                    let large = PremiumRenderingTestSupport.fittingSize(view, width: width, dark: dark,
                        size: .large, locale: language.formattingLocale)
                    let ax = PremiumRenderingTestSupport.fittingSize(view, width: width, dark: dark,
                        size: .accessibility5, locale: language.formattingLocale)
                    XCTAssertLessThanOrEqual(ax.width, width + 1)
                    XCTAssertGreaterThan(ax.height, large.height)
                }
            }
            let probe = PremiumRenderingTestSupport.accessibilityProbe(view, width: 375)
            XCTAssertTrue(probe.contains { $0.label == paragraphs.first! })
            XCTAssertTrue(probe.contains { $0.label == paragraphs.last! })
            XCTAssertEqual(probe.filter { $0.label == paragraphs[1] }.count, 10, "Repeated paragraphs must not be deduplicated")
        }
    }

    func testNewProtocolSurfacesKeepVerbatimTextAndScalableTokens() throws {
        for file in ["ObjectiveStepView.swift", "ProtocolMessageView.swift"] {
            let source = try reviewedSource("BodyFlow/Features/Onboarding/" + file)
            XCTAssertTrue(source.contains("Text(verbatim:"))
            XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"))
            for forbidden in [".lineLimit(", ".minimumScaleFactor(", ".font(.system(size:", ".shadow(", ".blur(", ".glassEffect("] {
                XCTAssertFalse(source.contains(forbidden), "\(file): \(forbidden)")
            }
        }
        let container = try reviewedSource("BodyFlow/Features/Onboarding/OnboardingContainerView.swift")
        XCTAssertTrue(container.contains("model.visibleSteps"))
        XCTAssertTrue(container.contains(".onChange(of: model.pendingProtocolWelcome != nil)"))
    }

    private let sizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    /// Local documentary render only — the launch is never delayed for a real
    /// screenshot, so this attaches the native `SplashView` render for visual
    /// review. It is not a captured app-launch frame.
    func testSplashNativeRenderForDocumentaryReview() throws {
        for language in SupportedAppLanguage.allCases {
            let locale = language.formattingLocale
            let image = PremiumRenderingTestSupport.nativeImage(
                SplashView(),
                width: 393,
                dark: false,
                size: .large,
                locale: locale
            )
            let attachment = XCTAttachment(
                data: try XCTUnwrap(image.pngData()),
                uniformTypeIdentifier: "public.png"
            )
            attachment.name = "splash-native-render-\(language.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// The compact shell wordmark must keep scaling with Dynamic Type at every
    /// step. XCTest's accessibility audit flags any element whose text stops
    /// growing between categories ("Dynamic Type font sizes are partially
    /// unsupported"), so both brand presentations must yield a strictly
    /// increasing rendered height across all twelve sizes.
    func testBrandIdentityGrowsStrictlyAcrossDynamicTypeSizes() {
        for presentation in [BodyFlowBrandIdentityView.Presentation.standard, .compact] {
            for dark in [false, true] {
                let heights = sizes.map { size in
                    PremiumRenderingTestSupport.fittingSize(
                        BodyFlowBrandIdentityView(presentation: presentation),
                        width: 375,
                        dark: dark,
                        size: size,
                        locale: SupportedAppLanguage.portugueseBrazil.formattingLocale
                    ).height
                }
                let rendered = zip(sizes, heights)
                    .map { "\($0): \(String(format: "%.1f", $1))" }
                    .joined(separator: ", ")
                for index in 1..<heights.count {
                    XCTAssertGreaterThan(
                        heights[index],
                        heights[index - 1],
                        "\(presentation) brand must grow at \(sizes[index - 1]) → "
                            + "\(sizes[index]) (dark: \(dark)); rendered: \(rendered)"
                    )
                }
            }
        }
    }

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
                            let loading = Button(label, action: {})
                                .buttonStyle(BodyFlowButtonStyle(role: role, isLoading: true))
                                .disabled(true)
                            let loadingFrame = PremiumRenderingTestSupport.fittingSize(
                                loading, width: innerWidth, dark: dark, size: size, locale: locale
                            )
                            XCTAssertGreaterThanOrEqual(loadingFrame.width, 44)
                            XCTAssertGreaterThanOrEqual(loadingFrame.height, 44)
                            XCTAssertGreaterThanOrEqual(loadingFrame.height + 1, textHeight + 24,
                                "Loading label must fit: \(language) \(dark) \(width) \(size) \(role)")
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
                        let compact = Button(action: {}) { Image(symbol: .send) }
                            .buttonStyle(BodyFlowButtonStyle(role: .primary, isCompact: true))
                        let compactFrame = PremiumRenderingTestSupport.fittingSize(
                            compact, width: innerWidth, dark: dark, size: size, locale: locale
                        )
                        XCTAssertGreaterThanOrEqual(compactFrame.width, 44)
                        XCTAssertGreaterThanOrEqual(compactFrame.height, 44)
                        XCTAssertLessThan(compactFrame.width, innerWidth / 2,
                            "Compact buttons hug their glyph: \(language) \(dark) \(width) \(size)")
                        let header = BodyFlowSectionHeader(label, symbol: .energy) {
                            Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: .tertiary, isCompact: true))
                        }
                        let headerFrame = PremiumRenderingTestSupport.fittingSize(
                            header, width: innerWidth, dark: dark, size: size, locale: locale
                        )
                        XCTAssertLessThanOrEqual(headerFrame.width, innerWidth + 1)
                        XCTAssertGreaterThan(headerFrame.height, 0)
                        let status = BodyFlowStatusLine(body, kind: .warning)
                        let statusFrame = PremiumRenderingTestSupport.fittingSize(
                            status, width: innerWidth, dark: dark, size: size, locale: locale
                        )
                        // The message wraps inside the glyph column, so its exact height
                        // depends on the glyph width; the contract is that the line fits
                        // the width and never collapses below one line of its own font.
                        let supportingLine = PremiumRenderingTestSupport.fittingSize(
                            Text("Ag").font(BodyFlowTypography.supporting),
                            width: innerWidth, dark: dark, size: size, locale: locale
                        ).height
                        XCTAssertLessThanOrEqual(statusFrame.width, innerWidth + 1)
                        XCTAssertGreaterThanOrEqual(statusFrame.height + 1, supportingLine,
                            "Status lines never clip their message: \(language) \(dark) \(width) \(size)")
                        let rowLink = Button(action: {}) {
                            BodyFlowCard(surface: .card) { Text(body).font(BodyFlowTypography.body) }
                        }
                        .buttonStyle(.bodyFlowRow)
                        let rowFrame = PremiumRenderingTestSupport.fittingSize(
                            rowLink, width: innerWidth, dark: dark, size: size, locale: locale
                        )
                        XCTAssertGreaterThanOrEqual(rowFrame.height, 44)
                        XCTAssertGreaterThanOrEqual(rowFrame.height + 1, cardFrame.height,
                            "Row press feedback must not shrink the card: \(language) \(dark) \(width) \(size)")
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
        // A submitting button keeps one readable, disabled button element;
        // the progress indicator is decorative.
        let loading = PremiumRenderingTestSupport.accessibilityProbe(
            Button(label, action: {})
                .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: true))
                .disabled(true),
            width: 375
        )
        XCTAssertEqual(loading.filter { $0.label == label && $0.isButton }.count, 1)
        XCTAssertTrue(loading.contains { $0.label == label && $0.isButton && !$0.isEnabled })
        // A compact icon-only action keeps its spoken label and 44 pt target.
        for size in [DynamicTypeSize.large, .accessibility5] {
            let compact = PremiumRenderingTestSupport.accessibilityProbe(
                Button(action: {}) { Image(symbol: .send) }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary, isCompact: true))
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("fixture.compact"),
                width: 375, size: size
            )
            XCTAssertEqual(compact.filter { $0.label == label && $0.isButton }.count, 1, "Compact: \(compact)")
            XCTAssertTrue(compact.contains { $0.label == label && $0.isButton && $0.frame.width >= 44 && $0.frame.height >= 44 })
            // A status line reads as one element carrying the message.
            let status = PremiumRenderingTestSupport.accessibilityProbe(
                BodyFlowStatusLine(label, kind: .error).accessibilityIdentifier("fixture.status"),
                width: 375, size: size
            )
            XCTAssertEqual(status.filter { $0.label.contains(label) }.count, 1, "Status: \(status)")
        }
        // A card link with press feedback stays one readable button target.
        for size in [DynamicTypeSize.large, .accessibility5] {
            let row = PremiumRenderingTestSupport.accessibilityProbe(
                Button(action: {}) {
                    BodyFlowCard(surface: .card) { Text(label).font(BodyFlowTypography.headline) }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("fixture.row"),
                width: 375, size: size
            )
            XCTAssertEqual(row.filter { $0.label == label && $0.isButton }.count, 1, "Row link: \(row)")
            XCTAssertTrue(row.contains { $0.label == label && $0.isButton && $0.frame.width >= 44 && $0.frame.height >= 44 })
        }
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

    /// In-button progress indicators must take the button role's foreground
    /// (white on teal in light, near-black on mint in dark). A literal white
    /// tint is invisible on the dark primary button.
    func testReviewedSubmitSpinnersNeverHardCodeAWhiteTint() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let reviewedSources = [
            "BodyFlow/Features/Auth/SignInView.swift",
            "BodyFlow/Features/Auth/SignUpView.swift",
            "BodyFlow/Features/Auth/PasswordRecoveryView.swift",
            "BodyFlow/Features/Auth/EmailConfirmationView.swift",
            "BodyFlow/Features/Onboarding/OnboardingCompletionView.swift",
            "BodyFlow/Features/Onboarding/OnboardingContainerView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try String(
                contentsOf: projectRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            let count = source.components(separatedBy: ".tint(.white)").count - 1
            if count > 0 { offenders.append("\(path): \(count)") }
        }
        XCTAssertTrue(offenders.isEmpty, "Hard-coded white spinner tints: \(offenders)")
    }

    private func reviewedSource(_ path: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: projectRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// Stale data recovery is one shared block (banner + secondary retry with
    /// the `state.retry` identifier), not a hand-rolled headline button per
    /// screen. The Library pagination controls keep their own identifiers.
    func testReviewedStaleRecoverySitesUseTheSharedComponent() throws {
        let reviewedSources = [
            "BodyFlow/Features/Today/TodayRootView.swift",
            "BodyFlow/Features/Plan/PlanRootView.swift",
            "BodyFlow/Features/History/MainHistoryView.swift",
            "BodyFlow/Features/Progress/Block7700DetailView.swift",
            "BodyFlow/Features/Library/LibraryRootView.swift",
            "BodyFlow/Features/Mascot/MascotDetailView.swift",
            "BodyFlow/Features/Shared/FeatureComponents.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            let handRolled = occurrences(of: ".accessibilityIdentifier(\"state.retry\")", in: source)
            if handRolled > 0 { offenders.append("\(path): \(handRolled) hand-rolled state.retry") }
            // Either the block itself or the shared stack that owns it.
            let usesShared = source.contains("FeatureStaleRecovery(")
                || (source.contains("FeatureStateContentStack(") && source.contains("retryAction:"))
            if !usesShared { offenders.append("\(path): no FeatureStaleRecovery") }
        }
        XCTAssertTrue(offenders.isEmpty, "Stale recovery outside the shared component: \(offenders)")
    }

    /// Grouped lists and forms share one brand-backed style; the system
    /// grouped gray never shows through reviewed screens.
    func testReviewedListsUseTheSharedListStyle() throws {
        let reviewedSources = [
            "BodyFlow/Features/Routine/RoutineListView.swift",
            "BodyFlow/Features/Routine/RoutineHistoryView.swift",
            "BodyFlow/Features/Onboarding/WelcomeStepView.swift",
            "BodyFlow/Features/Register/MealProposalEditorView.swift",
            "BodyFlow/Features/Profile/ProfileRootView.swift",
            "BodyFlow/Features/Profile/CoachPersonaPickerView.swift",
        ]
        let inlined = [".listStyle(", ".scrollContentBackground(", ".listRowBackground("]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            for literal in inlined where source.contains(literal) {
                offenders.append("\(path) \(literal)")
            }
            if !source.contains(".bodyFlowList()") { offenders.append("\(path): no .bodyFlowList()") }
        }
        XCTAssertTrue(offenders.isEmpty, "List styling outside the shared modifier: \(offenders)")
    }

    /// Pushed screens use the inline native bar through one modifier, so no
    /// destination falls back to a large-title band.
    func testReviewedPushedScreensUseTheSharedChrome() throws {
        let reviewedSources = [
            "BodyFlow/Features/Profile/CurrentObjectiveView.swift",
            "BodyFlow/Features/Progress/Block7700DetailView.swift",
            "BodyFlow/Features/Plan/PlanDetailView.swift",
            "BodyFlow/Features/Routine/RoutineListView.swift",
            "BodyFlow/Features/Routine/RoutineHistoryView.swift",
            "BodyFlow/Features/Routine/RoutineDetailView.swift",
            "BodyFlow/Features/History/MainHistoryView.swift",
            "BodyFlow/Features/History/HistoryMealLogDetailView.swift",
            "BodyFlow/Features/History/HistoryWorkoutDetailView.swift",
            "BodyFlow/Features/Mascot/MascotDetailView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            if source.contains(".navigationTitle(") { offenders.append("\(path): inline navigationTitle") }
            if !source.contains(".bodyFlowScreenChrome(") { offenders.append("\(path): no .bodyFlowScreenChrome") }
        }
        XCTAssertTrue(offenders.isEmpty, "Chrome outside the shared modifier: \(offenders)")
    }

    /// Card links give press feedback; `.plain` stays only on the icon-only
    /// refresh control the accessibility audit allowlists.
    func testReviewedCardLinksUseTheRowButtonStyle() throws {
        let reviewedSources: [(path: String, allowedPlain: Int)] = [
            ("BodyFlow/Features/Plan/PlanRootView.swift", 0),
            ("BodyFlow/Features/Progress/ProgressRootView.swift", 0),
            ("BodyFlow/Features/History/MainHistoryView.swift", 0),
            ("BodyFlow/Features/Today/TodayRootView.swift", 1),
            ("BodyFlow/Features/Library/PublishedContentCard.swift", 0),
            ("BodyFlow/Features/Mascot/MascotCardView.swift", 0),
            ("BodyFlow/Features/Profile/ProfileRootView.swift", 0),
            ("BodyFlow/Features/Profile/CoachPersonaPickerView.swift", 0),
            ("BodyFlow/Features/Routine/RoutineDetailView.swift", 0),
        ]
        var offenders: [String] = []
        for review in reviewedSources {
            let source = try reviewedSource(review.path)
            let plain = occurrences(of: ".buttonStyle(.plain)", in: source)
            if plain != review.allowedPlain { offenders.append("\(review.path): \(plain) .plain") }
            if !source.contains(".buttonStyle(.bodyFlowRow)") { offenders.append("\(review.path): no .bodyFlowRow") }
        }
        XCTAssertTrue(offenders.isEmpty, "Card links without press feedback: \(offenders)")
    }

    /// Authenticated roots give their vertical space to content; the central
    /// action owns the brand. The persona sheet keeps the shared header.
    func testReviewedBrandBandsUseTheSharedHeader() throws {
        let reviewedSources = [
            "BodyFlow/Features/Profile/CoachPersonaPickerView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            if source.contains("BodyFlowBrandIdentityView(") { offenders.append("\(path): inline BodyFlowBrandIdentityView") }
            if !source.contains("BodyFlowBrandHeader(") { offenders.append("\(path): no BodyFlowBrandHeader") }
        }
        let shell = try reviewedSource("BodyFlow/App/AppShellView.swift")
        if shell.contains("BodyFlowBrandHeader(") { offenders.append("AppShellView: repeated root brand band") }
        if !shell.contains("PerformeTabBar(") { offenders.append("AppShellView: missing central brand navigation") }
        XCTAssertTrue(offenders.isEmpty, "Brand bands outside the shared header: \(offenders)")
    }

    /// `Label(verbatim:symbol:)` takes resolved text. A localization key
    /// passed there renders as its own raw key — the Flow guidance line did,
    /// before this contract existed.
    func testReviewedSourcesNeverPassALocalizationKeyAsVerbatimText() throws {
        let reviewedSources = [
            "BodyFlow/Features/Profile/CurrentObjectiveView.swift",
            "BodyFlow/Features/Today/TodayRootView.swift",
            "BodyFlow/Features/Today/TodayHeaderSection.swift",
            "BodyFlow/Features/Today/TodayEnergySection.swift",
            "BodyFlow/Features/Today/TodayProteinSection.swift",
            "BodyFlow/Features/Today/TodayHydrationSection.swift",
            "BodyFlow/Features/Today/TodayAttentionSection.swift",
            "BodyFlow/Features/Today/TodayRecommendationsSection.swift",
            "BodyFlow/Features/Today/TodayRoutineSection.swift",
            "BodyFlow/Features/Today/TodayRecordsSection.swift",
            "BodyFlow/Features/Today/TodayBlockCard.swift",
            "BodyFlow/Features/FlowChat/FlowChatView.swift",
            "BodyFlow/DesignSystem/Components/BodyFlowSectionHeader.swift",
            "BodyFlow/Features/Library/PublishedContentCard.swift",
            "BodyFlow/Features/Library/PublishedContentDetailView.swift",
            "BodyFlow/Features/Library/LibraryRootView.swift",
            "BodyFlow/Features/Routine/RoutineListView.swift",
            "BodyFlow/Features/Routine/RoutineHistoryView.swift",
            "BodyFlow/Features/Routine/RoutineDetailView.swift",
            "BodyFlow/Features/Mascot/MascotDetailView.swift",
        ]
        // `verbatim: "today.something"`: a dotted, space-free literal is a key.
        let pattern = try NSRegularExpression(
            pattern: #"verbatim:\s*"[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9-]+)+""#
        )
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            let matches = pattern.numberOfMatches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            )
            if matches > 0 { offenders.append("\(path): \(matches)") }
        }
        XCTAssertTrue(offenders.isEmpty, "Localization keys passed as verbatim text: \(offenders)")
    }

    /// Today and Flow name their glyphs through the shared vocabulary; raw
    /// SF Symbol literals belong to `BodyFlowSymbol` only.
    func testReviewedTodayAndFlowSourcesUseTheSymbolVocabulary() throws {
        let reviewedSources = [
            "BodyFlow/Features/Today/TodayRootView.swift",
            "BodyFlow/Features/Today/TodayHeaderSection.swift",
            "BodyFlow/Features/Today/TodayEnergySection.swift",
            "BodyFlow/Features/Today/TodayProteinSection.swift",
            "BodyFlow/Features/Today/TodayHydrationSection.swift",
            "BodyFlow/Features/Today/TodayAttentionSection.swift",
            "BodyFlow/Features/Today/TodayRecommendationsSection.swift",
            "BodyFlow/Features/Today/TodayRoutineSection.swift",
            "BodyFlow/Features/Today/TodayRecordsSection.swift",
            "BodyFlow/Features/Today/TodayBlockCard.swift",
            "BodyFlow/Features/FlowChat/FlowChatView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            let literals = occurrences(of: "systemName: \"", in: source)
                + occurrences(of: "systemImage: \"", in: source)
            if literals > 0 { offenders.append("\(path): \(literals) raw symbol literals") }
        }
        XCTAssertTrue(offenders.isEmpty, "Raw SF Symbol names outside the vocabulary: \(offenders)")
    }

    /// Today's section headings and card links, and Flow's status messages,
    /// go through the shared components (one heading style with the header
    /// trait; one status line; press feedback on every card link).
    func testReviewedTodayAndFlowSourcesUseTheSharedHeadingsStatusAndRowLinks() throws {
        // The day panel is the summary itself and carries no heading; the
        // sections below it do.
        let headingSources = [
            "BodyFlow/Features/Today/TodayRecordsSection.swift",
            "BodyFlow/Features/Today/TodayRecommendationsSection.swift",
            "BodyFlow/Features/Today/TodayRoutineSection.swift",
        ]
        let statusSources = [
            "BodyFlow/Features/FlowChat/FlowChatView.swift",
            "BodyFlow/Features/Today/TodayRecommendationsSection.swift",
            "BodyFlow/Features/Today/TodayRoutineSection.swift",
            "BodyFlow/Features/Today/TodayAttentionSection.swift",
        ]
        let plainFreeSources = [
            "BodyFlow/Features/Today/TodayRecommendationsSection.swift",
            "BodyFlow/Features/Today/TodayRoutineSection.swift",
        ]
        var offenders: [String] = []
        for path in headingSources where try !reviewedSource(path).contains("BodyFlowSectionHeader(") {
            offenders.append("\(path): no BodyFlowSectionHeader")
        }
        for path in statusSources where try !reviewedSource(path).contains("BodyFlowStatusLine(") {
            offenders.append("\(path): no BodyFlowStatusLine")
        }
        for path in plainFreeSources {
            let plain = occurrences(of: ".buttonStyle(.plain)", in: try reviewedSource(path))
            if plain > 0 { offenders.append("\(path): \(plain) .plain") }
        }
        let flow = try reviewedSource("BodyFlow/Features/FlowChat/FlowChatView.swift")
        if !flow.contains("isCompact:") { offenders.append("FlowChatView: composer action not compact") }
        if flow.contains(".frame(width: BodyFlowSpacing.minimumTapTarget)") {
            offenders.append("FlowChatView: composer action still forced to a 44 pt frame")
        }
        XCTAssertTrue(offenders.isEmpty, "Shared components missing: \(offenders)")
    }

    /// The I5 surfaces (Progress, Profile, Library card/article, Routine,
    /// History, Mascot) name their glyphs through the shared vocabulary; raw
    /// SF Symbol literals belong to `BodyFlowSymbol` only.
    func testReviewedI5SourcesUseTheSymbolVocabulary() throws {
        let reviewedSources = [
            "BodyFlow/Features/Profile/CurrentObjectiveView.swift",
            "BodyFlow/Features/Progress/ProgressComponents.swift",
            "BodyFlow/Features/Progress/ProgressRootView.swift",
            "BodyFlow/Features/Progress/Block7700DetailView.swift",
            "BodyFlow/Features/Profile/ProfileRootView.swift",
            "BodyFlow/Features/Profile/CoachPersonaPickerView.swift",
            "BodyFlow/Features/Library/PublishedContentCard.swift",
            "BodyFlow/Features/Library/PublishedContentDetailView.swift",
            "BodyFlow/Features/Library/ContentCoverView.swift",
            "BodyFlow/Features/Routine/RoutineListView.swift",
            "BodyFlow/Features/Routine/RoutineHistoryView.swift",
            "BodyFlow/Features/Routine/RoutineDetailView.swift",
            "BodyFlow/Features/Routine/RoutineActionSheet.swift",
            "BodyFlow/Features/Routine/RoutineSnoozeView.swift",
            "BodyFlow/Features/History/MainHistoryView.swift",
            "BodyFlow/Features/History/HistoryMealLogRowView.swift",
            "BodyFlow/Features/History/HistoryMealLogDetailView.swift",
            "BodyFlow/Features/History/HistoryWorkoutDetailView.swift",
            "BodyFlow/Features/Mascot/MascotCardView.swift",
            "BodyFlow/Features/Mascot/MascotDetailView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            let literals = occurrences(of: "systemName: \"", in: source)
                + occurrences(of: "systemImage: \"", in: source)
            if literals > 0 { offenders.append("\(path): \(literals) raw symbol literals") }
        }
        XCTAssertTrue(offenders.isEmpty, "Raw SF Symbol names outside the vocabulary: \(offenders)")
    }

    /// Actions on the I5 surfaces take a `BodyFlowButtonStyle` role; the
    /// system bordered styles (and their dark-mode accent) are gone.
    func testReviewedI5ActionsUseTheRoleButtonStyles() throws {
        let reviewedSources = [
            "BodyFlow/Features/Progress/ProgressComponents.swift",
            "BodyFlow/Features/Library/PublishedContentDetailView.swift",
            "BodyFlow/Features/Library/LibraryRootView.swift",
            "BodyFlow/Features/Routine/RoutineDetailView.swift",
            "BodyFlow/Features/Routine/RoutineActionSheet.swift",
            "BodyFlow/Features/Routine/RoutineSnoozeView.swift",
            "BodyFlow/Features/Routine/RoutineHistoryView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            for literal in [".buttonStyle(.bordered)", ".buttonStyle(.borderedProminent)"]
                where source.contains(literal) {
                offenders.append("\(path) \(literal)")
            }
            if !source.contains("BodyFlowButtonStyle(role:") { offenders.append("\(path): no role button") }
        }
        XCTAssertTrue(offenders.isEmpty, "Actions outside the role styles: \(offenders)")
    }

    /// Operation outcomes and stale/paging notices on the I5 surfaces go
    /// through the shared status line.
    func testReviewedI5SourcesUseTheSharedStatusLine() throws {
        let reviewedSources = [
            "BodyFlow/Features/Progress/ProgressComponents.swift",
            "BodyFlow/Features/Library/PublishedContentDetailView.swift",
            "BodyFlow/Features/Library/LibraryRootView.swift",
            "BodyFlow/Features/Routine/RoutineActionSheet.swift",
            "BodyFlow/Features/Mascot/MascotCardView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources where try !reviewedSource(path).contains("BodyFlowStatusLine(") {
            offenders.append("\(path): no BodyFlowStatusLine")
        }
        XCTAssertTrue(offenders.isEmpty, "Status outside the shared component: \(offenders)")
    }

    /// The Progress screen keeps its heading through the shared section
    /// header and groups the received figures into the three approved
    /// cards; the reference dates stay a quiet block, not a fourth card.
    func testProgressCompositionUsesTheSharedHeadingAndThreeGroupedCards() throws {
        let source = try reviewedSource("BodyFlow/Features/Progress/ProgressComponents.swift")
        XCTAssertTrue(source.contains("BodyFlowSectionHeader(copy(\"progress.title\"))"))
        XCTAssertFalse(source.contains("progress.eyebrow"), "The eyebrow is gone")
        XCTAssertEqual(occurrences(of: "BodyFlowCard(surface: .card)", in: source), 3)
        for identifier in [
            "progress.body", "progress.measurements", "progress.consistency",
            "progress.summary", "progress.achievements", "progress.streak.restart",
            "progress.streak.resume-today", "progress.badges",
            "progress.missions.unavailable", "progress.dates", "progress.received-values",
        ] {
            XCTAssertTrue(
                source.contains(".accessibilityIdentifier(\"\(identifier)\")"),
                "\(identifier) must keep a real container"
            )
        }
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"progress.medal.\\(medal.id.offset)\")"))
    }

    /// I6 (Auth, Onboarding, AppRootView) names its glyphs through the
    /// shared vocabulary; raw SF Symbol literals belong to `BodyFlowSymbol`
    /// only.
    func testReviewedAuthOnboardingSourcesUseTheSymbolVocabulary() throws {
        let reviewedSources = [
            "BodyFlow/Features/Auth/AuthFieldMessage.swift",
            "BodyFlow/Features/Auth/PasswordRecoveryView.swift",
            "BodyFlow/Features/Onboarding/OnboardingViewSupport.swift",
            "BodyFlow/Features/Onboarding/OnboardingContainerView.swift",
            "BodyFlow/Features/Onboarding/WelcomeStepView.swift",
            "BodyFlow/Features/Onboarding/ObjectiveStepView.swift",
            "BodyFlow/Features/Onboarding/ProtocolMessageView.swift",
            "BodyFlow/Features/Onboarding/PersonaStepView.swift",
            "BodyFlow/Features/Onboarding/ConsentStepView.swift",
            "BodyFlow/Features/Onboarding/OnboardingCompletionView.swift",
            "BodyFlow/App/AppRootView.swift",
            // First update (2026-10-10): the load-error screen left
            // AppRootView for its own file and stays under the same rule.
            "BodyFlow/Features/Onboarding/OnboardingLoadErrorView.swift",
            // Second update (2026-10-10): the password field with its eye.
            "BodyFlow/Features/Auth/AuthPasswordField.swift",
            // Update of 2026-10-11 (P-ACTIVITY): the rows of the activity level.
            "BodyFlow/Features/Onboarding/RoutineStepView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            let literals = occurrences(of: "systemName: \"", in: source)
                + occurrences(of: "systemImage: \"", in: source)
            if literals > 0 { offenders.append("\(path): \(literals) raw symbol literals") }
        }
        XCTAssertTrue(offenders.isEmpty, "Raw SF Symbol names outside the vocabulary: \(offenders)")
    }

    /// Onboarding's radio-style selection rows (objective, persona) and
    /// checkbox-style consent actions give press feedback like every other
    /// reviewed card link; `.plain` is gone from these sources.
    func testReviewedOnboardingSelectionControlsUseTheRowButtonStyle() throws {
        let reviewedSources = [
            "BodyFlow/Features/Onboarding/WelcomeStepView.swift",
            "BodyFlow/Features/Onboarding/ObjectiveStepView.swift",
            "BodyFlow/Features/Onboarding/PersonaStepView.swift",
            "BodyFlow/Features/Onboarding/ConsentStepView.swift",
            // Update of 2026-10-11 (P-ACTIVITY): the activity level is five
            // rows that say what each level means, no longer a menu of names.
            "BodyFlow/Features/Onboarding/RoutineStepView.swift",
        ]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try reviewedSource(path)
            let plain = occurrences(of: ".buttonStyle(.plain)", in: source)
            if plain > 0 { offenders.append("\(path): \(plain) .plain") }
            if !source.contains(".buttonStyle(.bodyFlowRow)") { offenders.append("\(path): no .bodyFlowRow") }
        }
        XCTAssertTrue(offenders.isEmpty, "Selection controls without press feedback: \(offenders)")
    }

    /// Field-level and operation-wide errors across Auth and Onboarding go
    /// through the one shared status line; onboarding's free-standing text
    /// fields take the same field surface Auth already uses.
    func testReviewedAuthOnboardingSourcesUseSharedStatusLineAndField() throws {
        let statusLineSources = [
            "BodyFlow/Features/Auth/AuthFieldMessage.swift",
            "BodyFlow/Features/Onboarding/OnboardingViewSupport.swift",
            "BodyFlow/Features/Onboarding/OnboardingContainerView.swift",
        ]
        var offenders: [String] = []
        for path in statusLineSources where try !reviewedSource(path).contains("BodyFlowStatusLine(") {
            offenders.append("\(path): no BodyFlowStatusLine")
        }
        let fieldSources = [
            "BodyFlow/Features/Onboarding/WelcomeStepView.swift",
            "BodyFlow/Features/Onboarding/BodyDataStepView.swift",
        ]
        for path in fieldSources {
            let source = try reviewedSource(path)
            if source.contains("textFieldStyle(.roundedBorder)") {
                offenders.append("\(path): still uses the native rounded border style")
            }
            if !source.contains(".bodyFlowField()") { offenders.append("\(path): no .bodyFlowField()") }
        }
        XCTAssertTrue(offenders.isEmpty, "Shared components missing: \(offenders)")
    }

    /// The decimal pad has no return key, so the body-data fields offer a
    /// keyboard "Done" action (and the onboarding scroll dismisses the
    /// keyboard on drag): the keyboard can always be closed and never has to
    /// hide the step's Continue action.
    func testOnboardingDecimalFieldsOfferAKeyboardDoneAndScrollDismissal() throws {
        var offenders: [String] = []
        let bodyData = try reviewedSource("BodyFlow/Features/Onboarding/BodyDataStepView.swift")
        if !bodyData.contains("placement: .keyboard") { offenders.append("BodyDataStepView: no keyboard toolbar") }
        if !bodyData.contains("keyboard.done") { offenders.append("BodyDataStepView: no keyboard.done copy") }
        if !bodyData.contains("@FocusState") { offenders.append("BodyDataStepView: no focus state") }
        let container = try reviewedSource("BodyFlow/Features/Onboarding/OnboardingContainerView.swift")
        if !container.contains(".scrollDismissesKeyboard(.interactively)") {
            offenders.append("OnboardingContainerView: scroll does not dismiss the keyboard")
        }
        let catalog = try reviewedSource("BodyFlow/Resources/Localizable.xcstrings")
        if !catalog.contains("\"keyboard.done\"") { offenders.append("Localizable: no keyboard.done key") }
        XCTAssertTrue(offenders.isEmpty, "Keyboard dismissal missing: \(offenders)")
    }

    /// Every onboarding step lives in one shared ScrollView, so the offset a
    /// long step (the documents) leaves behind would otherwise carry into the
    /// next, shorter one and crop its title. A step change starts at the top.
    func testOnboardingStepChangeReturnsTheScrollToTheTop() throws {
        var offenders: [String] = []
        let container = try reviewedSource("BodyFlow/Features/Onboarding/OnboardingContainerView.swift")
        if !container.contains("ScrollViewReader") { offenders.append("no ScrollViewReader") }
        if !container.contains(".onChange(of: model.step)") { offenders.append("no step-change observer") }
        if !container.contains("scrollTo(") { offenders.append("no scroll reset") }
        XCTAssertTrue(offenders.isEmpty, "Step change does not reset the scroll: \(offenders)")
    }

    /// The review card on the last onboarding step hugged its widest row, so
    /// it stopped short of the column the notice and the CTA below it fill.
    func testOnboardingSummaryCardFillsTheColumn() throws {
        let completion = try reviewedSource("BodyFlow/Features/Onboarding/OnboardingCompletionView.swift")
        let surface = try XCTUnwrap(completion.range(of: "BodyFlowColor.surface"))
        let beforeBackground = String(completion[..<surface.lowerBound].suffix(160))
        XCTAssertTrue(
            beforeBackground.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
            "The onboarding review card is not stretched to the column width before its background."
        )
    }

    /// The authenticated shell hands the Register tab its real availability
    /// and the Profile tab the signed-in account, so a build on a real
    /// backend never shows the local demonstration copy.
    func testShellPassesCapabilityTruthToRegisterAndProfile() throws {
        var offenders: [String] = []
        let shell = try reviewedSource("BodyFlow/App/AppShellView.swift")
        if shell.contains("RegisterRootView()") { offenders.append("AppShellView: RegisterRootView() without a state") }
        if !shell.contains("isRegistrationAvailable") { offenders.append("AppShellView: registration availability not read") }
        if !shell.contains("accountEmail:") { offenders.append("AppShellView: account e-mail not handed to Profile") }
        let profile = try reviewedSource("BodyFlow/Features/Profile/ProfileRootView.swift")
        if !profile.contains("accountEmail") { offenders.append("ProfileRootView: no accountEmail") }
        let dependencies = try reviewedSource("BodyFlow/App/AppDependencies.swift")
        if !dependencies.contains("var isRegistrationAvailable") { offenders.append("AppDependencies: no isRegistrationAvailable") }
        if !dependencies.contains("var presentsRealAccountIdentity") { offenders.append("AppDependencies: no presentsRealAccountIdentity") }
        XCTAssertTrue(offenders.isEmpty, "Capability truth not threaded: \(offenders)")
    }

    /// On a real account the Register surfaces drop every "local
    /// demonstration" copy and sample source, and say plainly which capture
    /// paths are not available yet.
    func testRegisterSurfacesSeparateLiveModeFromTheLocalDemonstration() throws {
        var offenders: [String] = []
        for file in [
            "BodyFlow/Features/Register/RegisterRootView.swift",
            "BodyFlow/Features/Register/RegistrationSheet.swift",
            "BodyFlow/Features/Register/MealCaptureSourceView.swift",
        ] {
            let source = try reviewedSource(file)
            if !source.contains("presentsLocalDemonstration") {
                offenders.append("\(file): no live/demonstration switch")
            }
        }
        let catalog = try reviewedSource("BodyFlow/Resources/Localizable.xcstrings")
        for key in [
            "registration.root.detail.live",
            "registration.root.open",
            "registration.sheet.title.live",
            "registration.sheet.live-notice",
            "registration.text.placeholder.live",
            "registration.capture.media-unavailable",
        ] where !catalog.contains("\"\(key)\"") {
            offenders.append("Localizable: no \(key)")
        }
        XCTAssertTrue(offenders.isEmpty, "Live Register mode not separated: \(offenders)")
    }

    /// A real account can leave the app from Profile: the shell hands the
    /// root's sign-out down, and Profile shows the action only when it has
    /// one, so the locked demonstration never grows a sign-out row.
    func testProfileOffersSignOutOnlyOnARealAccount() throws {
        var offenders: [String] = []
        let profile = try reviewedSource("BodyFlow/Features/Profile/ProfileRootView.swift")
        for marker in ["signOut", "profile.account.sign-out", "profile.account.section"]
        where !profile.contains(marker) {
            offenders.append("ProfileRootView: no \(marker)")
        }
        let shell = try reviewedSource("BodyFlow/App/AppShellView.swift")
        if !shell.contains("signOut:") {
            offenders.append("AppShellView: does not hand sign-out to Profile")
        }
        let root = try reviewedSource("BodyFlow/App/AppRootView.swift")
        if !root.contains("model.signOut()") {
            offenders.append("AppRootView: sign-out never reaches AppFlowModel.signOut()")
        }
        let catalog = try reviewedSource("BodyFlow/Resources/Localizable.xcstrings")
        for key in [
            "profile.account.section",
            "profile.account.sign-out",
            "profile.account.sign-out.confirm",
            "mascot.changed-at.unavailable",
        ] where !catalog.contains("\"\(key)\"") {
            offenders.append("Localizable: no \(key)")
        }
        XCTAssertTrue(offenders.isEmpty, "Sign-out not wired for real accounts: \(offenders)")
    }

    /// First update (2026-10-10). The liquid loader is a layer loop handed to
    /// the render server once: no per-frame SwiftUI loop (it would stall
    /// XCTest's idle wait and re-evaluate the view every frame), no timer,
    /// no fixed font, no dependency — and the block that hosts it can take
    /// the VoiceOver focus.
    func testLiquidLoaderIsALayerLoopWithNoTimerOrFixedFont() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let liquidPath = "BodyFlow/DesignSystem/Components/BodyFlowLiquidLoader.swift"
        let stagedPath = "BodyFlow/DesignSystem/Components/BodyFlowStagedLoader.swift"
        for path in [liquidPath, stagedPath] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(path).path),
                "\(path) does not exist"
            )
        }
        var offenders: [String] = []
        for path in [liquidPath, stagedPath] {
            let source = try reviewedSource(path)
            for forbidden in [
                "TimelineView", "repeatForever", "Task.sleep", "asyncAfter",
                ".font(.system(size:", "Lottie", "Timer", "DispatchQueue",
            ] where source.contains(forbidden) {
                offenders.append("\(path): \(forbidden)")
            }
        }
        let liquid = try reviewedSource(liquidPath)
        if !liquid.contains("BodyFlowLoopingView") { offenders.append("liquid loader: not a BodyFlowLoopingView") }
        let staged = try reviewedSource(stagedPath)
        if !staged.contains("BodyFlowLiquidLoader()") { offenders.append("staged loader: no liquid loader") }
        if !staged.contains(".accessibilityFocused(") { offenders.append("staged loader: cannot take VoiceOver focus") }
        if !staged.contains(".accessibilityValue(") { offenders.append("staged loader: the stage is not the status value") }
        XCTAssertTrue(offenders.isEmpty, "Liquid loader contract: \(offenders)")
    }

    /// The meal analysis shows the one shared loading block, told its stage
    /// by the sheet's single decision — which the brand mark reads too — and
    /// nothing in it waits before appearing.
    func testMealAnalysisUsesTheOneSharedLoaderAndNothingWaits() throws {
        var offenders: [String] = []
        let capture = try reviewedSource("BodyFlow/Features/Register/Media/MealLiveCaptureView.swift")
        for required in ["BodyFlowStagedLoader(", "MealAnalysisFocus.takesFocus(", "model.beginPreparing()"]
        where !capture.contains(required) {
            offenders.append("MealLiveCaptureView: no \(required)")
        }
        for forbidden in ["BodyFlowDelayedProgress(", "ProgressView(", "isStaging", "Task.sleep", "asyncAfter"]
        where capture.contains(forbidden) {
            offenders.append("MealLiveCaptureView: still has \(forbidden)")
        }
        let sheet = try reviewedSource("BodyFlow/Features/Register/RegistrationSheet.swift")
        for required in [
            "Self.mealAnalysisStage(",
            "hasProposal: mealModel.currentProposal != nil",
            "registrationPhase: mealModel.phase",
            "isSubmitting: mealModel.isSubmitting",
            "showsProgress: analysisStage == nil",
            "analysisStage: analysisStage",
        ] where !sheet.contains(required) {
            offenders.append("RegistrationSheet: no \(required)")
        }
        let brand = try reviewedSource("BodyFlow/DesignSystem/Components/PerformeBrandAction.swift")
        if !brand.contains("state == .processing && showsProgress") {
            offenders.append("PerformeBrandAction: the spinner ignores showsProgress")
        }
        let catalog = try reviewedSource("BodyFlow/Resources/Localizable.xcstrings")
        for key in ["registration.live.analysis.title", "registration.live.phase.calculating"]
        where !catalog.contains("\"\(key)\"") {
            offenders.append("Localizable: no \(key)")
        }
        XCTAssertTrue(offenders.isEmpty, "Meal analysis loader contract: \(offenders)")
    }

    /// The root and the onboarding container each key their own motion to
    /// the state that actually changed — the root to the screen it shows,
    /// the container to the current step — instead of one fade covering
    /// both, and both go through the shared token so Reduce Motion collapses
    /// them.
    func testRootAndOnboardingContainerKeyMotionToTheirOwnState() throws {
        var offenders: [String] = []
        let root = try reviewedSource("BodyFlow/App/AppRootView.swift")
        if !root.contains("BodyFlowMotion.stateTransition(reduceMotion:") {
            offenders.append("AppRootView: no root state transition")
        }
        // Eduardo (02/10): the root changes with the brand duration so the
        // mark is seen travelling from the splash into the tab bar.
        if !root.contains("BodyFlowMotion.animation(.brand, reduceMotion:") {
            offenders.append("AppRootView: no brand-motion animation")
        }
        let container = try reviewedSource("BodyFlow/Features/Onboarding/OnboardingContainerView.swift")
        if !container.contains("value: model.step") {
            offenders.append("OnboardingContainerView: step transition not keyed to model.step")
        }
        XCTAssertTrue(offenders.isEmpty, "Motion not keyed as expected: \(offenders)")
    }

    /// Decorative tint washes share one opacity token; ad-hoc alphas drift
    /// between 0.08 / 0.10 / 0.12 / 0.25 for the same intent.
    func testReviewedTintWashesUseTheSharedOpacityToken() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let reviewedSources = [
            "BodyFlow/Features/Today/TodayEnergySection.swift",
            "BodyFlow/Features/Auth/PasswordRecoveryView.swift",
            "BodyFlow/Features/Auth/AuthFieldMessage.swift",
            "BodyFlow/Features/Onboarding/OnboardingContainerView.swift",
            "BodyFlow/Features/Library/ContentCoverView.swift",
            "BodyFlow/Features/Library/LibraryRootView.swift",
            "BodyFlow/Features/Shared/FeatureComponents.swift",
        ]
        let literalAlphas = [".opacity(0.08)", ".opacity(0.10)", ".opacity(0.12)", ".opacity(0.25)"]
        var offenders: [String] = []
        for path in reviewedSources {
            let source = try String(
                contentsOf: projectRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            for literal in literalAlphas where source.contains(literal) {
                offenders.append("\(path) \(literal)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Literal wash alphas outside the token: \(offenders)")
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
                Button(label, action: {}).buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: true)).disabled(true)
                FeatureStaleRecovery(retry: {})
            }
        }
        .padding(BodyFlowSpacing.screenGutter(usableWidth: width))
        .foregroundStyle(BodyFlowColor.color(.textPrimary))
        .background(BodyFlowColor.color(.backgroundPrimary))
        .environment(\.locale, locale)
    }
}
