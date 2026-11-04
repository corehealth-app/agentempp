import Foundation

/// Presentation only. Persisted AppTab/raw route identities remain unchanged.
enum AppNavigationLayout: Equatable, Sendable {
    case legacy
    case conversationalPreview

    static let previewArgument = "--ui-testing-conversational-navigation"

    static func resolve(arguments: [String], buildFlavor: AppBuildFlavor,
                        runtimeMode: AppRuntimeMode, presentsRealAccountIdentity: Bool,
                        realConversationCandidate: Bool = false) -> Self {
        if realConversationCandidate, runtimeMode != .demo, presentsRealAccountIdentity {
            return .conversationalPreview
        }
        return buildFlavor == .debug && runtimeMode == .demo && !presentsRealAccountIdentity
            && arguments.contains(previewArgument) ? .conversationalPreview : .legacy
    }

    static func current(runtimeMode: AppRuntimeMode, presentsRealAccountIdentity: Bool,
                        realConversationCandidate: Bool = false) -> Self {
        #if DEBUG
        resolve(arguments: ProcessInfo.processInfo.arguments, buildFlavor: .debug,
                runtimeMode: runtimeMode, presentsRealAccountIdentity: presentsRealAccountIdentity,
                realConversationCandidate: realConversationCandidate)
        #else
        resolve(arguments: [], buildFlavor: .release, runtimeMode: runtimeMode,
                presentsRealAccountIdentity: presentsRealAccountIdentity,
                realConversationCandidate: realConversationCandidate)
        #endif
    }

    var visibleTabs: [AppTab] {
        self == .legacy ? AppTab.displayOrder : [.today, .plan, .register, .progress]
    }

    func visibleTab(for tab: AppTab) -> AppTab {
        self == .conversationalPreview && tab == .profile ? .progress : tab
    }

    /// A push preserves its active stack. Without an origin, known domains
    /// select their visible home; an old mixed Register entry belongs to Flow.
    func presentationHost(for route: AppRoute, from origin: AppTab? = nil) -> AppTab {
        guard self == .conversationalPreview else { return route.tab }
        if let origin { return visibleTab(for: origin) }
        switch route {
        case .historyWorkout: return .register
        case .historyMealLog: return .plan
        case .legacyRoot(.register): return .today
        default: return visibleTab(for: route.tab)
        }
    }

    func title(for tab: AppTab, language: SupportedAppLanguage) -> String {
        guard self == .conversationalPreview else { return tab.title(for: language) }
        let en = language == .englishUnitedStates
        switch tab {
        case .today: return "Flow"
        case .plan: return en ? "Nutrition" : "Alimentação"
        case .register: return en ? "Training" : "Treino"
        case .progress: return en ? "Journey" : "Jornada"
        case .profile: return tab.title(for: language)
        }
    }

    func systemImage(for tab: AppTab) -> String {
        guard self == .conversationalPreview else { return tab.systemImage }
        switch tab {
        case .today: return "bubble.left"
        case .plan: return "fork.knife"
        case .register: return "dumbbell"
        case .progress: return "chart.bar"
        case .profile: return tab.systemImage
        }
    }
}
