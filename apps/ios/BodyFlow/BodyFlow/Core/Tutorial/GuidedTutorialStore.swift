import Foundation

/// Where an account stands with the guided tour on this iPhone. Only the
/// presentation preference is kept: no health data, no account id.
enum GuidedTutorialStatus: String, Sendable, Equatable {
    /// Never offered (or offered and the app closed before an answer): the
    /// first eligible entry offers it.
    case notOffered
    /// "Agora não" or closed before the end: never offered again on its own;
    /// still available from Profile.
    case deferred
    /// Finished at least once.
    case completed
}

/// Keyed by the reminders' owner hash, never by the account id, so one
/// account's answer never reaches another account on the same iPhone.
protocol GuidedTutorialStoring: Sendable {
    func status(ownerKey: String) -> GuidedTutorialStatus
    func setStatus(_ status: GuidedTutorialStatus, ownerKey: String)
    /// A contextual tip (one per control) is shown once per account.
    func hasShownTip(_ tip: GuidedTourTarget, ownerKey: String) -> Bool
    func markTipShown(_ tip: GuidedTourTarget, ownerKey: String)
}

struct UserDefaultsGuidedTutorialStore: GuidedTutorialStoring {
    func status(ownerKey: String) -> GuidedTutorialStatus {
        UserDefaults.standard.string(forKey: Self.key(ownerKey))
            .flatMap(GuidedTutorialStatus.init(rawValue:)) ?? .notOffered
    }

    func setStatus(_ status: GuidedTutorialStatus, ownerKey: String) {
        UserDefaults.standard.set(status.rawValue, forKey: Self.key(ownerKey))
    }

    func hasShownTip(_ tip: GuidedTourTarget, ownerKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.tipKey(tip, ownerKey))
    }

    func markTipShown(_ tip: GuidedTourTarget, ownerKey: String) {
        UserDefaults.standard.set(true, forKey: Self.tipKey(tip, ownerKey))
    }

    static func key(_ ownerKey: String) -> String {
        "\(LocalReminderPlanner.identifierPrefix)tutorial.v1.\(ownerKey)"
    }

    static func tipKey(_ tip: GuidedTourTarget, _ ownerKey: String) -> String {
        "\(LocalReminderPlanner.identifierPrefix)tutorial.v1.tip.\(tip.rawValue).\(ownerKey)"
    }
}

final class InMemoryGuidedTutorialStore: GuidedTutorialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: GuidedTutorialStatus]
    private var tips: Set<String> = []

    init(statuses: [String: GuidedTutorialStatus] = [:]) {
        self.statuses = statuses
    }

    func hasShownTip(_ tip: GuidedTourTarget, ownerKey: String) -> Bool {
        lock.withLock { tips.contains("\(tip.rawValue).\(ownerKey)") }
    }

    func markTipShown(_ tip: GuidedTourTarget, ownerKey: String) {
        lock.withLock { _ = tips.insert("\(tip.rawValue).\(ownerKey)") }
    }

    func status(ownerKey: String) -> GuidedTutorialStatus {
        lock.withLock { statuses[ownerKey] ?? .notOffered }
    }

    func setStatus(_ status: GuidedTutorialStatus, ownerKey: String) {
        lock.withLock { statuses[ownerKey] = status }
    }
}

/// What the tour may say and whether it offers itself. The text follows the
/// capabilities of this build and session, never a feature it does not have.
struct GuidedTutorialCapability: Sendable {
    let store: any GuidedTutorialStoring
    /// The first eligible entry offers the tour. Off in the local
    /// demonstration and UI tests unless a test asks for it.
    let offersOnFirstEntry: Bool

    #if DEBUG
    /// UI tests only: offer the tour on the demonstration's first entry.
    static let firstEntryTestArgument = "--ui-testing-tutorial-eligible"
    /// UI tests only: use the text tour (the VoiceOver path) instead of
    /// the spotlight overlay.
    static let textTourTestArgument = "--ui-testing-tutorial-text"
    #endif
}

/// The facts the tour's text depends on, read from the session's real
/// dependencies.
struct GuidedTutorialFacts: Equatable, Sendable {
    /// Photo and audio meal capture really work in this session: a media
    /// reader and an uploader exist (otherwise the meal is described in text).
    var mealMedia: Bool
    /// Flow suggestions and the "Para revisar" drafts exist.
    var planDrafts: Bool
    /// A plan can be imported from a photo or a PDF.
    var planImport: Bool
    /// Local reminders exist on this iPhone.
    var reminders: Bool
    /// A real account whose Profile shows "Sair da conta".
    var realAccount: Bool
}

enum GuidedTutorialOffer {
    /// Offers the tour on its own only on the first eligible entry, never
    /// over a sheet or a reminder that is being opened.
    static func shouldOffer(
        status: GuidedTutorialStatus,
        offersOnFirstEntry: Bool,
        isPresentingSheet: Bool,
        hasPendingRoute: Bool
    ) -> Bool {
        offersOnFirstEntry && status == .notOffered && !isPresentingSheet && !hasPendingRoute
    }

    /// The status an answer leaves behind. Closing never counts as finishing,
    /// and a replay closed early never undoes an earlier completion.
    static func status(after outcome: GuidedTutorialOutcome, from current: GuidedTutorialStatus) -> GuidedTutorialStatus {
        switch outcome {
        case .finished: .completed
        case .closedEarly: current == .completed ? .completed : .deferred
        // A reminder opening its screen is not the user's answer.
        case .interrupted: current
        }
    }
}

enum GuidedTutorialOutcome: Equatable, Sendable {
    case finished
    case closedEarly
    /// Closed by the app (a reminder's screen) without the user answering.
    case interrupted
}
