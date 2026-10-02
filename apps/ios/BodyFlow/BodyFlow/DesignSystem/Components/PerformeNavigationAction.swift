import SwiftUI
import UIKit

/// SwiftUI owns the approved appearance; one native control owns every
/// activation path and the system Large Content Viewer interaction.
struct PerformeNavigationAction<Content: View>: View {
    let title: String
    let largeContentImage: UIImage?
    let isSelected: Bool
    let identifier: String?
    var status: String? = nil
    let action: @MainActor () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHighlighted = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content()
                .frame(minWidth: 44, minHeight: 44)
                .scaleEffect(isHighlighted && !reduceMotion ? BodyFlowMotion.pressedScale : 1)
                .opacity(isHighlighted ? BodyFlowOpacity.pressed : 1)
                .animation(BodyFlowMotion.animation(.press, reduceMotion: reduceMotion), value: isHighlighted)
                .allowsHitTesting(false)
                .accessibilityRepresentation { EmptyView() }
                .accessibilityHidden(true)
                .layoutPriority(1)
            PerformeNavigationControl(
                title: title, image: largeContentImage, selected: isSelected,
                identifier: identifier, status: status, enabled: isEnabled,
                highlighted: $isHighlighted, action: action
            )
        }
        // Keep the decorative branch separate. An overlay can merge the
        // button traits back into its hidden SwiftUI image and caption.
        .accessibilityElement(children: .contain)
    }
}

private struct PerformeNavigationControl: UIViewRepresentable {
    let title: String
    let image: UIImage?
    let selected: Bool
    let identifier: String?
    let status: String?
    let enabled: Bool
    @Binding var highlighted: Bool
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> PerformeNavigationButton {
        let button = PerformeNavigationButton(frame: .zero)
        configure(button)
        return button
    }

    func updateUIView(_ button: PerformeNavigationButton, context: Context) {
        configure(button)
    }

    private func configure(_ button: PerformeNavigationButton) {
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.accessibilityValue = status
        button.accessibilityTraits = selected ? [.button, .selected] : .button
        button.isEnabled = enabled
        button.isSelected = selected
        button.largeContentTitle = title
        button.largeContentImage = image
        button.activate = action
        button.highlightChanged = { highlighted = $0 }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PerformeNavigationButton, context: Context) -> CGSize? {
        CGSize(width: max(44, proposal.width ?? 44), height: max(44, proposal.height ?? 44))
    }

    static func dismantleUIView(_ button: PerformeNavigationButton, coordinator: ()) {
        button.activate = nil
        button.highlightChanged = nil
    }
}

/// One UIKit interaction spans all five native buttons. The SwiftUI labels
/// remain visual only; UIKit owns hit testing, accessibility and LCV routing.
struct PerformeNavigationBarItem {
    let title: String
    let image: UIImage?
    let selected: Bool
    let identifier: String
    let action: @MainActor () -> Void
    let highlightChanged: @MainActor (Bool) -> Void
}

struct PerformeNavigationBarControl: UIViewRepresentable {
    let items: [PerformeNavigationBarItem]

    func makeUIView(context: Context) -> PerformeNavigationBarView {
        let bar = PerformeNavigationBarView(frame: .zero)
        bar.configure(items)
        return bar
    }

    func updateUIView(_ bar: PerformeNavigationBarView, context: Context) {
        bar.configure(items)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PerformeNavigationBarView, context: Context) -> CGSize? {
        let minimumWidth = CGFloat(items.count) * 44 + CGFloat(max(0, items.count - 1)) * BodyFlowSpacing.xxs
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimumWidth
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 44
        return CGSize(width: max(minimumWidth, width), height: max(44, height))
    }

    static func dismantleUIView(_ bar: PerformeNavigationBarView, coordinator: ()) {
        bar.clearActions()
    }
}

final class PerformeNavigationBarView: UIView, UILargeContentViewerInteractionDelegate {
    private let stack = UIStackView()
    private(set) var buttons: [PerformeNavigationButton] = []
    private(set) lazy var largeContentInteraction = UILargeContentViewerInteraction(delegate: self)
    private var pressHasEnded = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = BodyFlowSpacing.xxs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addInteraction(largeContentInteraction)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ items: [PerformeNavigationBarItem]) {
        if buttons.map({ $0.accessibilityIdentifier ?? "" }) != items.map(\.identifier) {
            clearActions()
            for button in buttons {
                stack.removeArrangedSubview(button)
                button.removeFromSuperview()
            }
            buttons = items.map { _ in
                let button = PerformeNavigationButton(frame: .zero)
                // The bar owns one gesture across all destinations; each
                // button still owns its tap and VoiceOver activation.
                button.removeInteraction(button.largeContentInteraction)
                stack.addArrangedSubview(button)
                return button
            }
        }
        for (button, item) in zip(buttons, items) {
            button.accessibilityLabel = item.title
            button.accessibilityIdentifier = item.identifier
            button.accessibilityTraits = item.selected ? [.button, .selected] : .button
            button.isEnabled = true
            button.isSelected = item.selected
            button.largeContentTitle = item.title
            button.largeContentImage = item.image
            button.activate = item.action
            button.highlightChanged = item.highlightChanged
            button.touchDownObserved = { [weak self] in self?.pressHasEnded = false }
            button.touchUpActivated = { [weak self] in
                self?.pressHasEnded = true
                self?.buttons.forEach { $0.suppressPendingTouchUp() }
            }
        }
    }

    func clearActions() {
        pressHasEnded = true
        for button in buttons {
            button.activate = nil
            button.highlightChanged = nil
            button.touchDownObserved = nil
            button.touchUpActivated = nil
        }
    }

    func largeContentViewerInteraction(
        _ interaction: UILargeContentViewerInteraction,
        itemAt point: CGPoint
    ) -> (any UILargeContentViewerItem)? {
        guard interaction === largeContentInteraction else { return nil }
        return buttons.first { button in
            button.isEnabled && !button.isHidden
                && button.bounds.contains(button.convert(point, from: self))
        }
    }

    func largeContentViewerInteraction(
        _ interaction: UILargeContentViewerInteraction,
        didEndOn item: (any UILargeContentViewerItem)?,
        at point: CGPoint
    ) {
        guard interaction === largeContentInteraction, !pressHasEnded else { return }
        pressHasEnded = true
        // The LCV may finish before UIKit delivers a pending touchUpInside on
        // the origin button. Suppress that touch before selecting the target.
        buttons.forEach { $0.suppressPendingTouchUp() }
        guard let target = item as? PerformeNavigationButton,
              buttons.contains(where: { $0 === target }),
              target.bounds.contains(target.convert(point, from: self)) else { return }
        target.activateFromLargeContentViewer()
    }
}

/// This control paints nothing: its sibling SwiftUI label supplies the visual
/// content. Unlike a synthetic accessibility representation, its hit frame,
/// default action and large-content gesture all belong to the same UIButton.
final class PerformeNavigationButton: UIButton, UILargeContentViewerInteractionDelegate {
    var activate: (@MainActor () -> Void)?
    var highlightChanged: (@MainActor (Bool) -> Void)?
    var touchDownObserved: (@MainActor () -> Void)?
    var touchUpActivated: (@MainActor () -> Void)?
    private var pressHasEnded = false
    private(set) lazy var largeContentInteraction = UILargeContentViewerInteraction(delegate: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        tintColor = .label
        isAccessibilityElement = true
        accessibilityTraits = .button
        showsLargeContentViewer = true
        scalesLargeContentImage = true
        addInteraction(largeContentInteraction)
        addTarget(self, action: #selector(beginPress), for: .touchDown)
        addTarget(self, action: #selector(finishTouch), for: .touchUpInside)
        addTarget(self, action: #selector(finishOutside), for: .touchUpOutside)
        // LCV recognition can cancel UIButton tracking before didEndOn arrives.
        // Do not treat touchCancel as completion of the large-content gesture.
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue { highlightChanged?(isHighlighted) }
        }
    }

    @objc private func beginPress() {
        pressHasEnded = false
        touchDownObserved?()
    }

    @objc private func finishTouch() {
        guard !pressHasEnded else { return }
        pressHasEnded = true
        touchUpActivated?()
        performActivation()
    }

    @objc private func finishOutside() { pressHasEnded = true }

    func suppressPendingTouchUp() {
        pressHasEnded = true
        isHighlighted = false
    }

    func activateFromLargeContentViewer() { performActivation() }

    func largeContentViewerInteraction(
        _ interaction: UILargeContentViewerInteraction,
        didEndOn item: (any UILargeContentViewerItem)?,
        at point: CGPoint
    ) {
        guard interaction === largeContentInteraction, !pressHasEnded else { return }
        pressHasEnded = true
        guard let item = item as? UIView, item === self, bounds.contains(point) else { return }
        performActivation()
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled, !isHidden, let activate else { return false }
        activate()
        return true
    }

    private func performActivation() {
        guard isEnabled, !isHidden else { return }
        activate?()
    }
}
