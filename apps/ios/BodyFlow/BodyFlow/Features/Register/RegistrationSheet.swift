import SwiftUI

@MainActor
struct RegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(sheet.id)
            }
            .navigationTitle("Demonstração")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Fechar")
                            .frame(minWidth: BodyFlowSpacing.minimumTapTarget)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .accessibilityIdentifier("sheet.fechar")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Registro · Refeição") {
    RegistrationSheet(sheet: .registration(.meal))
        .installAppDependencies(AppDependencies.scaffold())
}
