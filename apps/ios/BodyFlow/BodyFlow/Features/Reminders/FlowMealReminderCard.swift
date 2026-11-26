import SwiftUI

@MainActor
struct FlowMealReminderCard: View {
    let model: FlowMealReminderModel
    let english: Bool
    let canAnswer: Bool
    let reply: @MainActor () -> Void
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            HStack(alignment: .top) {
                Text(verbatim: message)
                    .font(BodyFlowTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .frame(width: BodyFlowSpacing.minimumTapTarget,
                               height: BodyFlowSpacing.minimumTapTarget)
                }
                .accessibilityLabel(english ? "Close reminder" : "Fechar lembrete")
            }
            if model.hasFailure || model.reminder?.state == .processing {
                Button(english ? "Check again" : "Consultar de novo") {
                    Task { await model.refresh() }
                }
                .disabled(model.isWorking)
            } else if model.reminder?.state == .pending && model.answerMeal == nil {
                ViewThatFits(in: .horizontal) {
                    HStack { replyActions }
                    VStack(alignment: .leading) { replyActions }
                }
            }
        }
        .padding(BodyFlowSpacing.md)
        .background(BodyFlowColor.color(.surfaceElevated), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.meal-reminder")
    }

    @ViewBuilder
    private var replyActions: some View {
        Button(english ? "Tell Flow" : "Contar o que comi", action: reply)
            .disabled(model.isWorking || !canAnswer)
        Button(english ? "Already logged" : "Já registrei") {
            Task { await model.refresh(alreadyLogged: true) }
        }
        .disabled(model.isWorking)
        Button(english ? "I skipped it" : "Pulei") {
            Task { await model.refresh(skip: true) }
        }
        .disabled(model.isWorking)
    }

    private var message: String {
        if model.isWorking {
            return english ? "Checking your diary…" : "Conferindo seu diário…"
        }
        if model.hasFailure {
            return english ? "I couldn’t check this reminder right now." : "Não consegui consultar esse lembrete agora."
        }
        guard let notice = model.reminder else {
            return english ? "Checking your diary…" : "Conferindo seu diário…"
        }
        switch notice.state {
        case .processing:
            return english ? "I’ll wait for your current report to finish." : "Vou aguardar o envio que já está em andamento."
        case .resolved:
            return english ? "This reminder was already resolved." : "Esse lembrete já foi resolvido."
        case .expired:
            return english ? "The day for this reminder has ended." : "O dia desse lembrete já terminou."
        case .pending:
            if model.answerMeal != nil {
                return english ? "Tell me what you ate. You can type or send a photo or voice note."
                    : "Me conte o que você comeu. Pode escrever ou mandar uma foto ou um áudio."
            }
            if model.hasNoMatchingMeal {
                return english ? "I haven’t found \(mealName(notice.mealType)) in today’s diary yet."
                    : "Ainda não encontrei \(mealName(notice.mealType)) no diário de hoje."
            }
            return english ? "How did \(mealName(notice.mealType)) go today?"
                : "Como foi \(mealName(notice.mealType)) hoje?"
        }
    }

    private func mealName(_ meal: MealType) -> String {
        switch meal {
        case .breakfast: english ? "breakfast" : "o café da manhã"
        case .lunch: english ? "lunch" : "o almoço"
        case .snack: english ? "your snack" : "o lanche"
        case .dinner: english ? "dinner" : "o jantar"
        case .supper: english ? "your late snack" : "a ceia"
        case .other: english ? "your meal" : "a refeição"
        }
    }
}
