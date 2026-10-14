import SwiftUI

struct PerformeTabBar: View {
    @Binding var selection: AppTab
    let language: SupportedAppLanguage
    /// Only the visible bar of the selected root publishes tour targets.
    var attachesTourTargets = false
    /// Called for a tap on an item (not for a programmatic selection).
    var onUserSelect: () -> Void = {}
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20
    @State private var highlightedTab: AppTab?
    /// Ticks only for the tab that just became selected, so the leaving
    /// tab's glyph never bounces.
    @State private var bounceTicks: [AppTab: Int] = [:]
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            visualLabels
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(true)
                .accessibilityRepresentation { EmptyView() }
                .layoutPriority(1)
            PerformeNavigationBarControl(items: nativeItems)
        }
        // Like native tab bars, this constrained control uses the Large
        // Content Viewer at accessibility sizes. Screen content is uncapped.
        .padding(BodyFlowSpacing.xs)
        .bodyFlowSurface(.floating, cornerRadius: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation.tab-bar")
        .padding(.horizontal, BodyFlowSpacing.sm)
        .padding(.top, BodyFlowSpacing.xxs)
        .padding(.bottom, BodyFlowSpacing.xxs)
        .onChange(of: selection) { _, newValue in
            guard !reduceMotion else { return }
            bounceTicks[newValue, default: 0] += 1
        }
    }

    private var visualLabels: some View {
        HStack(alignment: .center, spacing: BodyFlowSpacing.xxs) {
            ForEach(AppTab.displayOrder) { tab in
                if tab == .register {
                    PerformeBrandAction(
                        state: highlightedTab == tab ? .press : (selection == tab ? .active : .idle),
                        label: tab.title(for: language),
                        selected: selection == tab,
                        isNavigationAction: true,
                        connectsLaunch: true
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .guidedTourTarget(.register, enabled: attachesTourTargets)
                } else {
                    tabLabel(tab)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .guidedTourTarget(Self.tourTarget(for: tab) ?? .flow, enabled: attachesTourTargets && Self.tourTarget(for: tab) != nil)
                        .scaleEffect(highlightedTab == tab && !reduceMotion ? BodyFlowMotion.pressedScale : 1)
                        .opacity(highlightedTab == tab ? BodyFlowOpacity.pressed : 1)
                        .animation(BodyFlowMotion.animation(.tap, reduceMotion: reduceMotion), value: highlightedTab)
                }
            }
        }
    }

    /// Today has no tab step (its shortcuts are the targets), so its label
    /// publishes nothing — never a second anchor for `.flow`.
    static func tourTarget(for tab: AppTab) -> GuidedTourTarget? {
        switch tab {
        case .today: nil
        case .register: .register
        case .plan: .planTab
        case .progress: .progressTab
        case .profile: .profileTab
        }
    }

    private var nativeItems: [PerformeNavigationBarItem] {
        AppTab.displayOrder.map { tab in
            PerformeNavigationBarItem(
                title: tab.title(for: language),
                image: tab == .register
                    ? UIImage(named: PerformeAIBrandAsset.symbolNegative.resourceName)?.withRenderingMode(.alwaysTemplate)
                    : UIImage(systemName: tab.systemImage),
                selected: selection == tab,
                identifier: tab.accessibilityIdentifier,
                action: {
                    onUserSelect()
                    selection = tab
                },
                highlightChanged: { isHighlighted in
                    if isHighlighted { highlightedTab = tab }
                    else if highlightedTab == tab { highlightedTab = nil }
                }
            )
        }
    }

    // The native overlay owns interaction; this label retains the appearance.
    private func tabLabel(_ tab: AppTab) -> some View {
        VStack(spacing: BodyFlowSpacing.xxs) {
            Image(systemName: tab.systemImage)
                .resizable()
                .scaledToFit()
                .fontWeight(selection == tab ? .semibold : .regular)
                .frame(width: min(iconSize, 28), height: min(iconSize, 28))
                .frame(width: 28, height: 28)
                // The arriving tab's glyph bounces once (finite symbol effect);
                // Reduce Motion keeps it still.
                .symbolEffect(.bounce, options: .nonRepeating, value: bounceTicks[tab, default: 0])
                .accessibilityHidden(true)
            tabCaption(tab)
        }
        .padding(.vertical, BodyFlowSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(BodyFlowColor.color(selection == tab ? .brandPrimary : .textSecondary))
        .background {
            if selection == tab {
                RoundedRectangle(cornerRadius: BodyFlowRadius.field)
                    .fill(BodyFlowColor.color(.surfaceInteractive))
                    .overlay {
                        RoundedRectangle(cornerRadius: BodyFlowRadius.field)
                            .strokeBorder(BodyFlowColor.color(.controlBoundary), lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
    }

    private func tabCaption(_ tab: AppTab) -> some View {
        Text(tab.title(for: language))
            .font(.caption2.weight(selection == tab ? .semibold : .regular))
            .foregroundStyle(BodyFlowColor.color(selection == tab ? .brandPrimary : .textSecondary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Measures the keyboard against this shell's own window using public APIs.
/// The TabView keeps native keyboard avoidance; only its custom bar disappears.
struct BodyFlowKeyboardObserver: UIViewRepresentable {
    let changed: (Bool) -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView(changed: changed) }
    func updateUIView(_ uiView: ObserverView, context: Context) { uiView.changed = changed }

    final class ObserverView: UIView {
        var changed: (Bool) -> Void

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            // Hiding software keys can leave the Done accessory on screen.
            // Both notifications describe the remaining occupied frame.
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidHideNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func keyboardChanged(_ notification: Notification) {
            guard let window, window.isKeyWindow,
                  let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            let keyboard = window.convert(value.cgRectValue, from: window.screen.coordinateSpace)
            let occupied = window.bounds.intersection(keyboard).height > 0
            // A completed hide can still report the old accessory frame after
            // Done has released our input owner. Keep an accessory whose own
            // view or controller remains first responder; will-change is not
            // a completed hide and keeps its reported occupied frame.
            let completedHide = notification.name == UIResponder.keyboardDidHideNotification
            changed(occupied && (!completedHide || Self.hasOwnFirstResponder(in: window)))
        }

        private static func hasOwnFirstResponder(in view: UIView) -> Bool {
            if view.isFirstResponder { return true }
            if let owner = view.next as? UIViewController, owner.isFirstResponder { return true }
            return view.subviews.contains { hasOwnFirstResponder(in: $0) }
        }
    }
}
