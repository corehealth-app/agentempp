import SwiftUI

/// Dormant read-only component. Callers own trusted transport/session fencing;
/// an HTTP success or this presentation never acknowledges an outbox command.
struct ConversationFeedbackPresentationView: View {
    let feedback: ConversationFeedbackPresentationSnapshot.Bound
    var compact = false
    @Environment(\.locale) private var locale
    @State private var detailsExpanded = false

    private var english: Bool {
        BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
    }

    var body: some View {
        Group {
            if compact {
                compactContent
            } else {
                expandedContent(showHeader: true)
            }
        }
        .font(BodyFlowTypography.body)
        .foregroundStyle(BodyFlowColor.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.feedback.presentation")
    }

    private func expandedContent(showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            if showHeader {
                Text(verbatim: "Flow AI")
                    .font(BodyFlowTypography.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: historicalTitle)
                    .font(BodyFlowTypography.body)
                    .accessibilityIdentifier("conversation.feedback.historical")
            }
            switch feedback.presentation.content {
            case let .sections(_, sections), let .v3Sections(_, sections), let .placeholder(sections):
                ForEach(sections.filter { showHeader || $0.key != .saved }, id: \.key) { section in
                    Text(verbatim: FoodDisplayLocalization.message(section.text,
                        english: BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates))
                        .accessibilityIdentifier("conversation.feedback.section.\(section.key.rawValue)")
                }
            case let .legacy(body):
                RegistrationFeedbackView(feedback: .v1(body))
            }
        }
    }

    private var compactContent: some View {
        let preview = FlowFeedbackPreview(feedback.presentation, english: english)
        return VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Label {
                Text(verbatim: preview.title)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(BodyFlowColor.accent)
            }
            .font(BodyFlowTypography.headline)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("conversation.feedback.compact-title")

            if let summary = preview.summary {
                Text(verbatim: summary)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityIdentifier("conversation.feedback.compact-summary")
            }
            if preview.pending == nil, let comment = preview.education,
                !preview.isMeal || comment.count <= 110 {
                Text(verbatim: comment)
                    .lineLimit(2)
                    .accessibilityIdentifier("conversation.feedback.compact-education")
            }
            if let pending = preview.pending {
                Text(verbatim: pending)
                    .foregroundStyle(BodyFlowColor.warning)
                    .accessibilityIdentifier("conversation.feedback.photo-question")
            }
            DisclosureGroup(
                english ? "View details" : "Ver detalhes", isExpanded: $detailsExpanded
            ) {
                if detailsExpanded { expandedContent(showHeader: false).padding(.top, BodyFlowSpacing.xs) }
            }
            .tint(BodyFlowColor.accent)
            .accessibilityIdentifier("conversation.feedback.details")
        }
    }

    private var historicalTitle: String {
        let date = feedback.presentation.original.localDate
        return BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
            ? "Historical registration (\(date))" : "Registro histórico (\(date))"
    }
}

/// Short chat copy from the same bound facts as the expanded receipt. Formatting
/// changes here never generate nutrition or supplement the server's policy.
struct FlowFeedbackPreview {
    let title: String
    let summary: String?
    let education: String?
    let pending: String?
    let isMeal: Bool

    init(_ feedback: ConversationFeedbackPresentationSnapshot, english: Bool) {
        typealias Section = ConversationFeedbackPresentationSnapshot.Section
        let sections: [Section]
        var workoutTitle: String?
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .locale(Locale(identifier: english ? "en_US" : "pt_BR"))
        func mealSummary(_ kcal: Double, _ protein: Double) -> String {
            "\(english ? "Approx." : "Aprox.") \(kcal.formatted(format)) kcal · \(protein.formatted(format)) g \(english ? "of protein" : "de proteína")"
        }
        switch feedback.content {
        case let .v3Sections(recorded, savedSections):
            sections = savedSections
            switch recorded {
            case .meal(let meal):
                isMeal = true
                summary = mealSummary(meal.totals.kcal, meal.totals.proteinG)
            case .workout(let workout):
                isMeal = false
                workoutTitle = english ? "Activity registered" : "Atividade registrada"
                let name = FoodDisplayLocalization.name(workout.workoutType, english: english)
                summary = [
                    name,
                    workout.durationMin.map { "\($0.formatted(format)) min" },
                    workout.estimatedKcal.map { "\(english ? "Approx." : "Aprox.") \($0.formatted(format)) kcal" },
                ].compactMap { $0 }.joined(separator: " · ")
            }
        case let .sections(meal, savedSections):
            isMeal = true
            sections = savedSections
            summary = mealSummary(meal.totals.kcal, meal.totals.proteinG)
        case let .placeholder(savedSections):
            isMeal = false
            sections = savedSections
            summary = nil
        case .legacy:
            isMeal = false
            sections = []
            summary = nil
        }
        func text(_ key: Section.Key) -> String? {
            sections.first { $0.key == key }?.text
        }
        title = workoutTitle ?? text(.saved) ?? (english ? "Meal recorded" : "Refeição registrada")
        let educationPrefix = english
            ? "Educational comment at the time of registration:\n"
            : "Comentário educativo no momento do registro:\n"
        education = text(.education).map { comment in
            let content = comment.hasPrefix(educationPrefix)
                ? String(comment.dropFirst(educationPrefix.count)) : comment
            return FoodDisplayLocalization.message(content, english: english)
        }

        let marker = english ? "To review separately: " : "Ficou para revisar: "
        let nextStep = english ? ". If confirmed, " : ". Se confirmar, "
        if let line = text(.summary)?.components(separatedBy: "\n").first(where: { $0.hasPrefix(marker) }),
            let separator = line.range(of: nextStep) {
            let names = line[line.index(line.startIndex, offsetBy: marker.count)..<separator.lowerBound]
            let multiple = names.contains(",") || names.count > 50
            pending = multiple
                ? (english ? "What else did you eat and how much?" : "O que mais você comeu e em que quantidade?")
                : (english ? "Was that \(names)? How much did you eat?" : "Era \(names)? Quanto você comeu?")
        } else {
            pending = nil
        }
    }
}

struct FlowChatBubble<Content: View>: View {
    var outgoing = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(BodyFlowTypography.body)
            .padding(BodyFlowSpacing.sm)
            .background(
                outgoing ? BodyFlowColor.accent.opacity(0.13) : BodyFlowColor.surface,
                in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
    }
}
