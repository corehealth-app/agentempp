import CryptoKit
import Foundation

/// The unfinished sign-up of a real account, kept on this iPhone so that
/// leaving the app in the middle does not lose what was typed.
///
/// Decision of the orchestrator (D6), announced to the owner on
/// 2026-10-10/11, who can strike it.
///
/// One file, `Library/Application Support/performe-sign-up-draft/draft.json`,
/// inside the app's own container: it goes away with the app, which the
/// Keychain would not. It is written with complete file protection (it can
/// only be read while the phone is unlocked), in a folder left out of the
/// backups. Nothing in it leaves the phone.
///
/// What it never holds: the acceptance of the documents, the objective (it
/// is only valid with the server's decision of that moment) and a step
/// beyond the documents. It names its account only by a SHA-256 of the
/// account's id, so another account never reads it.
struct OnboardingDeviceDraftStore: Sendable {
    static let folderName = "performe-sign-up-draft"
    static let fileName = "draft.json"
    private static let formatVersion = 1

    let root: URL

    init(directory: URL) {
        root = directory.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    /// The store of the app on this iPhone.
    static var device: OnboardingDeviceDraftStore {
        OnboardingDeviceDraftStore(directory: URL.applicationSupportDirectory)
    }

    var fileURL: URL {
        root.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// What of a draft is kept: everything the person typed up to the
    /// documents. The acceptances are marked again, and the objective is
    /// chosen again under a fresh decision.
    static func kept(_ draft: OnboardingDraft) -> OnboardingDraft {
        var kept = draft
        kept.consent = nil
        kept.documentActions = nil
        kept.objective = nil
        let steps = OnboardingStep.allCases
        if let current = steps.firstIndex(of: draft.currentStep),
           let documents = steps.firstIndex(of: .consent),
           current > documents {
            kept.currentStep = .consent
        }
        return kept
    }

    /// Where a kept draft reopens: on its own step, or on the first earlier
    /// step that still misses something (a file is never trusted to place
    /// the person past an incomplete step).
    static func resumable(_ kept: OnboardingDraft, now: Date = Date()) -> OnboardingDraft {
        var draft = kept
        for step in OnboardingStep.allCases.prefix(while: { $0 != kept.currentStep }) {
            let issues = OnboardingStepValidator.issues(
                for: step, draft: kept,
                developmentConsentAvailability: .unavailable, now: now
            )
            if !issues.isEmpty {
                draft.currentStep = step
                break
            }
        }
        return draft
    }

    /// Keeps the draft for this account, replacing whatever was kept. A
    /// failed write leaves the previous file as it was. Returns whether the
    /// draft was written.
    @discardableResult
    func save(_ draft: OnboardingDraft, for userID: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = root
            try folder.setResourceValues(values)
            let data = try JSONEncoder().encode(Envelope(
                version: Self.formatVersion,
                owner: Self.owner(userID),
                draft: Self.kept(draft)
            ))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// Another account never reads or removes the owner's draft. A broken
    /// file is removed; a locked file that cannot be read is left alone.
    /// Production calls this only inside the lifecycle's synchronous gate.
    func load(for userID: String) -> OnboardingDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            clear()
            return nil
        }
        guard envelope.owner == Self.owner(userID) else { return nil }
        guard envelope.version == Self.formatVersion else {
            clear(for: userID)
            return nil
        }
        return Self.resumable(Self.kept(envelope.draft))
    }

    /// A normal operation can remove only its own account's file.
    func clear(for userID: String) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.owner != Self.owner(userID) { return }
        clear()
    }

    /// The lifecycle clearer/reset alone removes any account's file.
    func clear() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func owner(_ userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let draft: OnboardingDraft
    }
}

/// Sign-out, a session that ended and an account switch: the unfinished
/// sign-up of that account does not stay on the phone.
struct OnboardingDeviceDraftSessionClearer: SensitiveStateClearing {
    let store: OnboardingDeviceDraftStore

    func clearSensitiveState() async {
        store.clear()
    }
}
