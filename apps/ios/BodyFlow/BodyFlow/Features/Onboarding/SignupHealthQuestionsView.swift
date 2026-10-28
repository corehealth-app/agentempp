import SwiftUI

@MainActor struct SignupHealthQuestionsView:View {
    let model:OnboardingFlowModel
    @Environment(\.locale) private var locale
    var body:some View {
        VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
            Text(copy("onboarding.health.title",fallback:"Informações de saúde"))
                .font(BodyFlowTypography.headline).accessibilityAddTraits(.isHeader)
            Text(copy("onboarding.health.instructions",fallback:"Se alguma situação se aplica a você, marque abaixo. Ao tocar em Continuar, você declara as situações selecionadas com os documentos acima. Você também pode continuar sem marcar opções."))
                .font(BodyFlowTypography.callout).fixedSize(horizontal:false,vertical:true)
            ForEach(ClinicalFullHealthRisk.allCases,id:\.rawValue) {risk in
                Button {model.updateHealthRisk(risk,selected:!model.healthRisks.contains(risk))} label: {
                    HStack(alignment:.top,spacing:BodyFlowSpacing.sm) {
                        Image(symbol:model.healthRisks.contains(risk) ? .checkboxOn : .checkboxOff).accessibilityHidden(true)
                        Text(label(risk)).font(BodyFlowTypography.body).fixedSize(horizontal:false,vertical:true)
                        Spacer(minLength:0)
                    }.frame(maxWidth:.infinity,minHeight:BodyFlowSpacing.minimumTapTarget,alignment:.leading)
                }.buttonStyle(.bodyFlowRow)
                    .disabled(!model.allowsDraftEditing || model.operationState == .saving)
                    .accessibilityAddTraits(model.healthRisks.contains(risk) ? .isSelected : [])
                    .accessibilityIdentifier("onboarding.health.\(risk.rawValue)")
            }
            Text(copy("onboarding.health.preserved",fallback:"Desmarcar uma opção não apaga uma declaração já registrada."))
                .font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
            if model.canReviewClinicalHealth {
                Button {Task {await model.reviewClinicalHealthDeclaration()}} label: {
                    Text(copy("onboarding.health.review",fallback:"Rever documentos e cadastro"))
                }.buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(model.operationState == .saving)
                    .accessibilityIdentifier("onboarding.health.review")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("onboarding.health")
    }
    private func label(_ risk:ClinicalFullHealthRisk)->String {
        switch risk {
        case .unintendedWeightLoss:copy("onboarding.health.unintended_weight_loss",fallback:"Perda de peso sem intenção")
        case .reducedIntake:copy("onboarding.health.reduced_intake",fallback:"Redução importante da ingestão de alimentos")
        case .persistentFatigue:copy("onboarding.health.persistent_fatigue_weakness_dizziness",fallback:"Cansaço, fraqueza ou tontura persistentes")
        case .menstrualChange:copy("onboarding.health.menstrual_change",fallback:"Mudança no ciclo menstrual")
        case .lossOfControlEating:copy("onboarding.health.loss_of_control_eating",fallback:"Perda de controle ao comer")
        case .appetiteWeightTreatment:copy("onboarding.health.appetite_weight_treatment",fallback:"Tratamento que afeta o apetite ou o peso")
        case .professionalDiet:copy("onboarding.health.professional_diet",fallback:"Acompanhamento profissional da alimentação ou proteína por uma condição de saúde")
        case .pregnantOrBreastfeeding:copy("onboarding.health.pregnant_or_breastfeeding",fallback:"Gestação ou amamentação")
        }
    }
    private func copy(_ key:String.LocalizationValue,fallback:String)->String {PremiumPresentationCopy.string(key,locale:locale,fallback:fallback)}
}
