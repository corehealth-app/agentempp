import SwiftUI
import UIKit

@MainActor
struct FlowChatView: View {
    let model: FlowChatModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.bodyFlowReduceMotion) private var appReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.locale) private var locale
    @FocusState private var composerFocused: Bool
    @State private var atEnd = true
    @State private var userScrolling = false
    @State private var initiatedSend = false
    @State private var lastAnnouncedMessageID: String?
    @State private var hasLoadedHistory = false
    @State private var keyboardClearance: CGFloat = 0
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            ZStack {
                FlowKeyboardClearanceObserver(owner: ObjectIdentifier(model)) { clearance in
                    if keyboardClearance != clearance { keyboardClearance = clearance }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    conversation(gutter: BodyFlowSpacing.screenGutter(usableWidth: geometry.size.width))
                    FlowComposerViewport(viewportHeight: geometry.size.height,
                                         keyboardClearance: keyboardClearance) {
                        VStack(spacing: 0) {
                            if let draft = model.turnDraft {
                                proposalCard(
                                    draft,
                                    gutter: BodyFlowSpacing.screenGutter(usableWidth: geometry.size.width)
                                )
                            }
                            Divider().overlay(BodyFlowColor.color(.borderSubtle))
                            composer(text: $model.composer,
                                     gutter: BodyFlowSpacing.screenGutter(usableWidth: geometry.size.width))
                        }
                    }
                    .layoutPriority(1)
                }
                .padding(.bottom, keyboardClearance)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(BodyFlowColor.color(.backgroundPrimary))
        .navigationTitle("flow.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { composerFocused = false } label: {
                    Text("keyboard.done")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keyboard.done")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.flow-chat")
        .task {
            await model.load()
            lastAnnouncedMessageID = model.messages.last?.state == .completed ? model.messages.last?.id : nil
            hasLoadedHistory = true
        }
        .onDisappear {
            initiatedSend = false
            model.cancel()
        }
    }

    /// The proposal this turn created. It opens the review; nothing is
    /// confirmed from the chat.
    private func proposalCard(_ draft: FlowTurnDraft, gutter: CGFloat) -> some View {
        NavigationLink(value: AppRoute.planDraft(PlanDraftRoute(
            draftID: draft.id, origin: .flow
        ))) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                Label(verbatim: proposalCopy("flow.proposal.review"), symbol: .summary)
                    .font(BodyFlowTypography.button)
                Text(proposalCopy(draft.domain == .training
                    ? "flow.proposal.detail.training" : "flow.proposal.detail.nutrition"))
                    .font(BodyFlowTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
        .padding(.horizontal, gutter)
        .padding(.vertical, BodyFlowSpacing.xs)
        .accessibilityIdentifier("flow.proposal.review")
    }

    private func proposalCopy(_ key: String.LocalizationValue) -> String {
        PlanCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }

    @ViewBuilder
    private func conversation(gutter: CGFloat) -> some View {
        let isLoadingHistory = model.isLoading && model.conversationItems.isEmpty
        let transition = BodyFlowMotion.stateTransition(reduceMotion: reduceMotion)
        // Loading ↔ conversation cross-fades (220 ms); immediate under
        // Reduce Motion. The scroll policy below is untouched.
        Group {
            if isLoadingHistory {
                BodyFlowDelayedProgress(label: flowCopy("flow.loading"))
                    .font(BodyFlowTypography.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("flow.loading")
                    .transition(transition)
            } else {
                history(gutter: gutter)
                    .transition(transition)
            }
        }
        .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: isLoadingHistory)
    }

    @ViewBuilder
    private func history(gutter: CGFloat) -> some View {
        ScrollViewReader { proxy in
                VStack(spacing: BodyFlowSpacing.xs) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Render received history intact. A single long AX
                            // bubble can exceed the viewport by many pages;
                            // lazy culling at its tail otherwise hides the text.
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                                preamble
                                if model.conversationItems.isEmpty {
                                    emptyConversation
                                }
                                ForEach(model.conversationItems) { item in
                                    switch item {
                                    case let .message(message):
                                        FlowMessageBubble(message: message).id(message.id)
                                    case let .outbox(pending):
                                        FlowOutboxBubble(message: pending, isSending: model.isSending) {
                                            Task { await model.retry(outboxID: pending.id) }
                                        }
                                    }
                                }
                                if model.isSending || model.isReconcilingHistory {
                                    HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                                        BodyFlowDelayedProgress()
                                        Text(model.isSending ? "flow.responding" : "flow.reconciling")
                                            .font(BodyFlowTypography.supporting)
                                            .foregroundStyle(BodyFlowColor.color(.textSecondary))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .accessibilityIdentifier(model.isSending ? "flow.responding" : "flow.reconciling")
                                }
                                if let errorMessage = model.errorMessage { errorCard(message: errorMessage) }
                            }
                            .padding(.horizontal, gutter)
                            .padding(.vertical, BodyFlowSpacing.md)
                            Color.clear.frame(height: BodyFlowSpacing.xxs)
                                .id("flow.history-end").accessibilityHidden(true)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(
                        model.conversationItems.isEmpty && model.errorMessage == nil ? .top : .bottom,
                        for: .initialOffset
                    )
                    .accessibilityIdentifier("flow.history")
                    .onScrollPhaseChange { _, phase in
                        userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    }
                    .onScrollGeometryChange(for: FlowScrollViewport.self) { geometry in
                        FlowScrollViewport(offset: geometry.contentOffset.y,
                                           height: geometry.containerSize.height,
                                           contentHeight: geometry.contentSize.height,
                                           bottomInset: geometry.contentInsets.bottom)
                    } action: { _, viewport in
                        let visible = viewport.atEnd
                        // Content growth alone is not a request to stop following.
                        if visible || userScrolling || UIAccessibility.isVoiceOverRunning { atEnd = visible }
                    }
                    .onChange(of: model.messages.last) {
                        if FlowChatScrollPolicy.shouldFollow(atEnd: atEnd, initiatedSend: initiatedSend) {
                            followEnd(proxy)
                        }
                        announceNewReplyIfFollowing()
                    }
                    .onChange(of: model.outbox.last?.id) {
                        if FlowChatScrollPolicy.shouldFollow(atEnd: atEnd, initiatedSend: initiatedSend) {
                            followEnd(proxy)
                        }
                    }
                    .onChange(of: initiatedSend) {
                        guard initiatedSend else { return }
                        followEnd(proxy)
                        initiatedSend = false
                    }
                    if !atEnd && !model.conversationItems.isEmpty {
                        Button("flow.latest-message") { followEnd(proxy) }
                            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                            .padding(.horizontal, gutter)
                            .accessibilityIdentifier("flow.latest-message")
                    }
                }
            }
    }

    /// Compact preamble: who is answering and the guidance note, one tight
    /// block above the conversation instead of two spaced paragraphs.
    private var preamble: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text("flow.role-line")
                .font(BodyFlowTypography.supporting)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.color(.textSecondary))
                .accessibilityIdentifier("flow.role-line")
            guidance
            Divider().overlay(BodyFlowColor.color(.borderSubtle))
                .padding(.top, BodyFlowSpacing.xs)
        }
    }

    private var guidance: some View {
        Label("flow.guidance", symbol: .info)
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("flow.guidance")
    }

    /// The conversation's own empty state: the Flow glyph in the brand color,
    /// the invitation as a screen title and the received guidance.
    private var emptyConversation: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            Image(symbol: .flow)
                .font(BodyFlowTypography.largeTitle)
                .foregroundStyle(BodyFlowColor.color(.brandPrimary))
                .accessibilityHidden(true)
            Text("flow.empty.title")
                .font(BodyFlowTypography.screenTitle)
                .foregroundStyle(BodyFlowColor.color(.textPrimary))
            Text("flow.empty.detail")
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.color(.textSecondary))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, BodyFlowSpacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flow.empty")
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            BodyFlowStatusLine(message, kind: .error, font: BodyFlowTypography.body)
                .accessibilityIdentifier("flow.error")
            Button("flow.retry") { Task { await model.retry() } }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("flow.retry")
        }
        .padding(BodyFlowSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BodyFlowColor.color(.backgroundSecondary),
                    in: RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous))
    }

    private func composer(text: Binding<String>, gutter: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            if dynamicType.isAccessibilitySize {
                composerField(text: text)
                composerAction(showLabel: true)
            } else {
                HStack(alignment: .bottom, spacing: BodyFlowSpacing.sm) {
                    composerField(text: text)
                    composerAction(showLabel: false)
                }
            }
            if FlowChatPresentation.isOverLimit(model.composer) {
                BodyFlowStatusLine(flowCopy("flow.limit.detail"), kind: .warning)
                    .accessibilityIdentifier("flow.limit.detail")
            }
        }
        .padding(.horizontal, gutter)
        .padding(.vertical, BodyFlowSpacing.sm)
        .background(BodyFlowColor.color(.backgroundSecondary))
    }

    private func composerField(text: Binding<String>) -> some View {
        TextField("flow.composer", text: text, axis: .vertical)
            .font(BodyFlowTypography.body)
            .lineLimit(1...(dynamicType.isAccessibilitySize ? 2 : 5))
            .bodyFlowField()
            .focused($composerFocused)
            .submitLabel(.send)
            .onSubmit(send)
            .accessibilityIdentifier("flow.composer")
            .guidedTourTarget(.flowComposer)
    }

    @ViewBuilder
    private func composerAction(showLabel: Bool) -> some View {
        if model.isSending {
            Button {
                initiatedSend = false
                model.cancel()
            } label: {
                if showLabel { Text("flow.cancel") }
                else { Image(symbol: .stop) }
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary, isCompact: !showLabel))
            .accessibilityLabel("flow.cancel")
            .accessibilityIdentifier("flow.cancel")
        } else {
            Button(action: send) {
                if showLabel { Text("flow.send") }
                else { Image(symbol: .send) }
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary, isCompact: !showLabel))
            .disabled(!FlowChatPresentation.canSubmit(model.composer, isSending: model.isSending))
            .accessibilityLabel("flow.send")
            .accessibilityIdentifier("flow.send")
        }
    }

    private func send() {
        guard FlowChatPresentation.canSubmit(model.composer, isSending: model.isSending) else { return }
        composerFocused = false
        initiatedSend = true
        Task { await model.send() }
    }

    private func followEnd(_ proxy: ScrollViewProxy) {
        atEnd = true
        // The scroll policy stays the single decider; a nil animation is an
        // immediate scroll.
        withAnimation(
            FlowChatScrollPolicy.shouldAnimate(reduceMotion: reduceMotion)
                ? BodyFlowMotion.animation(.content, reduceMotion: false)
                : nil
        ) {
            proxy.scrollTo("flow.history-end", anchor: .bottom)
        }
    }

    private func flowCopy(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(
            key,
            locale: BodyFlowPresentationLanguage.resolve(locale).formattingLocale
        ))
    }

    private func announceNewReplyIfFollowing() {
        guard hasLoadedHistory, let message = model.messages.last,
              message.role == .assistant, message.state == .completed,
              message.id != lastAnnouncedMessageID else { return }
        lastAnnouncedMessageID = message.id
        guard atEnd, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement,
                             argument: String(localized: LocalizedStringResource("flow.response.received",
                                locale: BodyFlowPresentationLanguage.resolve(locale).formattingLocale)))
    }
}

/// One persistent scroll container keeps the native field/focus identity while
/// two-line AX input and limit feedback can outgrow the keyboard-safe viewport.
private struct FlowComposerViewport<Content: View>: View {
    let viewportHeight: CGFloat
    let keyboardClearance: CGFloat
    private let content: Content
    @State private var naturalHeight: CGFloat?

    init(viewportHeight: CGFloat, keyboardClearance: CGFloat,
         @ViewBuilder content: () -> Content) {
        self.viewportHeight = viewportHeight
        self.keyboardClearance = keyboardClearance
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard height.isFinite, height > 0, naturalHeight != height else { return }
                    naturalHeight = height
                }
        }
        .frame(height: FlowComposerViewportPolicy.height(
            natural: naturalHeight, viewport: viewportHeight, clearance: keyboardClearance
        ), alignment: .top)
        .defaultScrollAnchor(.top, for: .initialOffset)
        .scrollDismissesKeyboard(.never)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("flow.composer-scroll")
    }
}

/// Local submission, never presented as an official persisted message.
private struct FlowOutboxBubble: View {
    let message: FlowOutboxMessage
    let isSending: Bool
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var statusKey: LocalizedStringKey {
        switch message.state {
        case .sending: "flow.outbox.sending"
        case .unconfirmed: "flow.outbox.unconfirmed"
        case .accepted: "flow.outbox.accepted"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: dynamicType.isAccessibilitySize ? 0 : BodyFlowSpacing.xl + BodyFlowSpacing.lg)
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("flow.role.user")
                    .font(BodyFlowTypography.caption)
                    .fontWeight(.semibold)
                Text(message.text)
                    .font(BodyFlowTypography.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Label(statusKey, symbol: message.state == .accepted ? .success : .clock)
                    .font(BodyFlowTypography.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                if message.state == .unconfirmed {
                    Button("flow.retry", action: retry)
                        .font(BodyFlowTypography.button)
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                        .disabled(isSending)
                        .accessibilityIdentifier("flow.outbox.retry.\(message.id.uuidString)")
                }
            }
            .foregroundStyle(BodyFlowColor.color(.onPrimary))
            .tint(BodyFlowColor.color(.onPrimary))
            .padding(BodyFlowSpacing.md)
            .background(BodyFlowColor.color(.brandPrimary),
                        in: RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("flow.outbox")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FlowScrollViewport: Equatable {
    let offset: CGFloat
    let height: CGFloat
    let contentHeight: CGFloat
    let bottomInset: CGFloat

    var atEnd: Bool {
        offset + height >= contentHeight + bottomInset - BodyFlowSpacing.xs
    }
}

private struct FlowMessageBubble: View {
    let message: FlowMessage
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: dynamicType.isAccessibilitySize ? 0 : BodyFlowSpacing.xl + BodyFlowSpacing.lg) }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(LocalizedStringResource(FlowChatPresentation.roleLabelKey(message.role),
                    locale: BodyFlowPresentationLanguage.resolve(locale).formattingLocale))
                    .font(BodyFlowTypography.caption)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("flow.role.\(message.id)")
                Text(message.content)
                    .font(BodyFlowTypography.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                // Bubble states keep the bubble's own foreground (white on the
                // brand bubble) and only take the vocabulary glyph.
                if message.state == .processing {
                    Label("flow.message.processing", symbol: .clock)
                        .font(BodyFlowTypography.supporting)
                        .accessibilityIdentifier("flow.message.processing")
                } else if message.state == .failed {
                    Label("flow.message.failed", symbol: .error)
                        .font(BodyFlowTypography.supporting)
                        .accessibilityIdentifier("flow.message.failed")
                }
            }
            .foregroundStyle(BodyFlowColor.color(message.role == .user ? .onPrimary : .textPrimary))
            .padding(BodyFlowSpacing.md)
            .background(BodyFlowColor.color(message.role == .user ? .brandPrimary : .backgroundSecondary),
                        in: RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("flow.message.\(message.id)")
            if message.role == .assistant { Spacer(minLength: dynamicType.isAccessibilitySize ? 0 : BodyFlowSpacing.xl + BodyFlowSpacing.lg) }
        }
        .frame(maxWidth: .infinity)
    }
}
