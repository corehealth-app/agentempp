import SwiftUI

@MainActor
struct FlowChatView: View {
    let model: FlowChatModel
    @FocusState private var composerFocused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            conversation
            Divider()
            composer(text: $model.composer)
        }
        .background(BodyFlowColor.background)
        .navigationTitle("flow.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.flow-chat")
        .task {
            await model.load()
        }
        .onDisappear {
            model.cancel()
        }
    }

    @ViewBuilder
    private var conversation: some View {
        if model.isLoading && model.messages.isEmpty {
            ProgressView("flow.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("flow.loading")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: BodyFlowSpacing.sm) {
                        guidance

                        if model.messages.isEmpty {
                            ContentUnavailableView(
                                "flow.empty.title",
                                systemImage: "bubble.left.and.text.bubble.right",
                                description: Text(
                                    "flow.empty.detail"
                                )
                            )
                            .accessibilityIdentifier("flow.empty")
                        }

                        ForEach(model.messages) { message in
                            FlowMessageBubble(message: message)
                                .id(message.id)
                        }

                        if model.isSending {
                            HStack(spacing: BodyFlowSpacing.sm) {
                                ProgressView()
                                Text("flow.responding")
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                                Spacer()
                            }
                            .accessibilityIdentifier("flow.responding")
                        }

                        if let errorMessage = model.errorMessage {
                            errorCard(message: errorMessage)
                        }
                    }
                    .padding(BodyFlowSpacing.md)
                }
                .onChange(of: model.messages.count) {
                    guard let lastID = model.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
    }

    private var guidance: some View {
        Label(
            "flow.guidance",
            systemImage: "cross.case"
        )
        .font(BodyFlowTypography.caption)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("flow.guidance")
    }

    private func errorCard(message: String) -> some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(message)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityIdentifier("flow.error")
                Button("flow.retry") {
                    Task { await model.retry() }
                }
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .accessibilityIdentifier("flow.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func composer(text: Binding<String>) -> some View {
        HStack(alignment: .bottom, spacing: BodyFlowSpacing.sm) {
            TextField("flow.composer", text: text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityIdentifier("flow.composer")

            if model.isSending {
                Button(action: model.cancel) {
                    Image(systemName: "stop.fill")
                        .frame(
                            width: BodyFlowSpacing.minimumTapTarget,
                            height: BodyFlowSpacing.minimumTapTarget
                        )
                }
                .accessibilityLabel("flow.cancel")
                .accessibilityIdentifier("flow.cancel")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(
                            width: BodyFlowSpacing.minimumTapTarget,
                            height: BodyFlowSpacing.minimumTapTarget
                        )
                }
                .disabled(model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("flow.send")
                .accessibilityIdentifier("flow.send")
            }
        }
        .padding(BodyFlowSpacing.md)
        .background(BodyFlowColor.surface)
    }

    private func send() {
        guard !model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        composerFocused = false
        Task { await model.send() }
    }
}

private struct FlowMessageBubble: View {
    let message: FlowMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(message.content)
                    .font(BodyFlowTypography.body)

                if message.state == .processing {
                    Label("flow.message.processing", systemImage: "clock")
                        .font(BodyFlowTypography.caption)
                        .accessibilityIdentifier("flow.message.processing")
                } else if message.state == .failed {
                    Label("flow.message.failed", systemImage: "exclamationmark.circle")
                        .font(BodyFlowTypography.caption)
                        .accessibilityIdentifier("flow.message.failed")
                }
            }
                .foregroundStyle(
                    message.role == .user ? BodyFlowColor.background : BodyFlowColor.primaryText
                )
                .padding(BodyFlowSpacing.sm)
                .background(
                    message.role == .user ? BodyFlowColor.accent : BodyFlowColor.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .accessibilityLabel(
                    "\(message.role == .user ? "Você" : "Flow"): \(message.content)"
                )
                .accessibilityIdentifier("flow.message.\(message.id)")
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
    }
}
