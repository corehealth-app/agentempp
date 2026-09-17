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
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            VStack(spacing: 0) {
                conversation(gutter: BodyFlowSpacing.screenGutter(usableWidth: geometry.size.width))
                Divider().overlay(BodyFlowColor.color(.borderSubtle))
                composer(text: $model.composer,
                         gutter: BodyFlowSpacing.screenGutter(usableWidth: geometry.size.width))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
        }
        .background(BodyFlowColor.color(.backgroundPrimary))
        .navigationTitle("flow.title")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func conversation(gutter: CGFloat) -> some View {
        if model.isLoading && model.messages.isEmpty {
            ProgressView("flow.loading")
                .font(BodyFlowTypography.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("flow.loading")
        } else {
            ScrollViewReader { proxy in
                VStack(spacing: BodyFlowSpacing.xs) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Render received history intact. A single long AX
                            // bubble can exceed the viewport by many pages;
                            // lazy culling at its tail otherwise hides the text.
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                                Text("flow.role-line")
                                    .font(BodyFlowTypography.supporting)
                                    .foregroundStyle(BodyFlowColor.color(.textSecondary))
                                    .accessibilityIdentifier("flow.role-line")
                                guidance
                                if model.messages.isEmpty {
                                    ContentUnavailableView(
                                        "flow.empty.title", systemImage: "bubble.left.and.text.bubble.right",
                                        description: Text("flow.empty.detail")
                                    )
                                    .accessibilityIdentifier("flow.empty")
                                }
                                ForEach(model.messages) { message in
                                    FlowMessageBubble(message: message).id(message.id)
                                }
                                if model.isSending {
                                    HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                                        ProgressView()
                                        Text("flow.responding")
                                            .font(BodyFlowTypography.supporting)
                                            .foregroundStyle(BodyFlowColor.color(.textSecondary))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .accessibilityIdentifier("flow.responding")
                                }
                                if let errorMessage = model.errorMessage { errorCard(message: errorMessage) }
                            }
                            .padding(.horizontal, gutter)
                            .padding(.vertical, BodyFlowSpacing.md)
                            Color.clear.frame(height: BodyFlowSpacing.xxs)
                                .id("flow.history-end").accessibilityHidden(true)
                        }
                    }
                    .defaultScrollAnchor(
                        model.messages.isEmpty && model.errorMessage == nil ? .top : .bottom,
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
                    .onChange(of: initiatedSend) {
                        guard initiatedSend else { return }
                        followEnd(proxy)
                        initiatedSend = false
                    }
                    if !atEnd && !model.messages.isEmpty {
                        Button("flow.latest-message") { followEnd(proxy) }
                            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                            .padding(.horizontal, gutter)
                            .accessibilityIdentifier("flow.latest-message")
                    }
                }
            }
        }
    }

    private var guidance: some View {
        Label("flow.guidance", systemImage: "info.circle")
            .font(BodyFlowTypography.supporting)
            .foregroundStyle(BodyFlowColor.color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("flow.guidance")
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: { Image(systemName: "exclamationmark.circle") }
            .font(BodyFlowTypography.body)
            .foregroundStyle(BodyFlowColor.color(.feedbackDestructive))
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
                    composerAction(showLabel: false).frame(width: BodyFlowSpacing.minimumTapTarget)
                }
            }
            if FlowChatPresentation.isOverLimit(model.composer) {
                Label("flow.limit.detail", systemImage: "exclamationmark.circle")
                    .font(BodyFlowTypography.supporting)
                    .foregroundStyle(BodyFlowColor.color(.feedbackWarning))
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    @ViewBuilder
    private func composerAction(showLabel: Bool) -> some View {
        if model.isSending {
            Button {
                initiatedSend = false
                model.cancel()
            } label: {
                if showLabel { Text("flow.cancel") }
                else { Image(systemName: "stop.fill") }
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .accessibilityLabel("flow.cancel")
            .accessibilityIdentifier("flow.cancel")
        } else {
            Button(action: send) {
                if showLabel { Text("flow.send") }
                else { Image(systemName: "arrow.up") }
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary))
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
        if FlowChatScrollPolicy.shouldAnimate(reduceMotion: reduceMotion) {
            withAnimation(.easeOut(duration: BodyFlowMotion.duration(reduceMotion: false, disclosure: false))) {
                proxy.scrollTo("flow.history-end", anchor: .bottom)
            }
        } else { proxy.scrollTo("flow.history-end", anchor: .bottom) }
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
            if message.role == .user { Spacer(minLength: dynamicType.isAccessibilitySize ? 0 : BodyFlowSpacing.lg) }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(LocalizedStringResource(FlowChatPresentation.roleLabelKey(message.role),
                    locale: BodyFlowPresentationLanguage.resolve(locale).formattingLocale))
                    .font(BodyFlowTypography.cardTitle)
                    .accessibilityIdentifier("flow.role.\(message.id)")
                Text(message.content)
                    .font(BodyFlowTypography.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if message.state == .processing {
                    Label("flow.message.processing", systemImage: "clock")
                        .font(BodyFlowTypography.supporting)
                        .accessibilityIdentifier("flow.message.processing")
                } else if message.state == .failed {
                    Label("flow.message.failed", systemImage: "exclamationmark.circle")
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
            if message.role == .assistant { Spacer(minLength: dynamicType.isAccessibilitySize ? 0 : BodyFlowSpacing.lg) }
        }
        .frame(maxWidth: .infinity)
    }
}
