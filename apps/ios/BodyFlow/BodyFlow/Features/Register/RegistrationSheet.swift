import SwiftUI

@MainActor
struct RegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let sheet: AppSheet

    private var kind: RegistrationKind {
        switch sheet {
        case let .registration(kind):
            kind
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: BodyFlowSpacing.lg) {
                            Image(systemName: kind.systemImage)
                                .font(BodyFlowTypography.largeTitle)
                                .foregroundStyle(BodyFlowColor.accent)
                                .accessibilityHidden(true)

                            Text(kind.title)
                                .font(BodyFlowTypography.title)
                                .fontWeight(.semibold)
                                .foregroundStyle(BodyFlowColor.primaryText)

                            Text(AppFixtures.registration.disclaimer)
                                .font(BodyFlowTypography.body)
                                .foregroundStyle(BodyFlowColor.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(BodyFlowSpacing.lg)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: geometry.size.height
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(sheet.id)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .navigationTitle("Demonstração")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(BodyFlowTypography.headline)
                            .frame(
                                width: BodyFlowSpacing.minimumTapTarget,
                                height: BodyFlowSpacing.minimumTapTarget
                            )
                    }
                    .accessibilityLabel("Fechar")
                    .accessibilityIdentifier("sheet.fechar")
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                }
            }
        }
        .presentationDetents(
            Self.presentationDetents(for: dynamicTypeSize)
        )
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    static func presentationDetents(
        for dynamicTypeSize: DynamicTypeSize
    ) -> Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium]
    }
}

#Preview("Registro · Refeição") {
    RegistrationSheet(sheet: .registration(.meal))
        .installAppDependencies(AppDependencies.scaffold())
}
