import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class FlowMealPushModel {
    enum Status: Equatable {
        case off, updating, active, permissionDenied, preferencesOff, unavailable
    }

    private(set) var status: Status = .off
    private(set) var enabled: Bool
    private(set) var daytime: Bool
    @ObservationIgnored private let ownerKey: String
    @ObservationIgnored private let environment: FlowMealPushEnvironment
    @ObservationIgnored private let provider: @Sendable () async throws -> MobileFlowMealPushRepository
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let system = SystemLocalNotificationCenter()
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var confirmedToken: Data?
    @ObservationIgnored private var confirmedDaytime: Bool?

    init(ownerKey: String, environment: FlowMealPushEnvironment,
         provider: @escaping @Sendable () async throws -> MobileFlowMealPushRepository) {
        self.ownerKey = ownerKey
        self.environment = environment
        self.provider = provider
        let prefix = Self.prefix(ownerKey)
        enabled = UserDefaults.standard.bool(forKey: prefix + ".enabled")
        daytime = UserDefaults.standard.bool(forKey: prefix + ".daytime")
        if enabled { status = .updating }
    }

    private static func prefix(_ ownerKey: String) -> String { "pai.flow-meal-push." + ownerKey }
    private var prefix: String { Self.prefix(ownerKey) }
    private var mayHaveRegistration: Bool {
        get { defaults.bool(forKey: prefix + ".registered") }
        set { defaults.set(newValue, forKey: prefix + ".registered") }
    }

    private var installation: UUID {
        let key = "pai.flow-meal-push.installation"
        if let value = defaults.string(forKey: key), let id = UUID(uuidString: value) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    func setEnabled(_ value: Bool) async {
        guard running == nil, !paused else { return }
        enabled = value
        defaults.set(value, forKey: prefix + ".enabled")
        await refresh(requestPermission: value)
    }

    func setDaytime(_ value: Bool) async {
        guard enabled, running == nil, !paused else { return }
        daytime = value
        defaults.set(value, forKey: prefix + ".daytime")
        await refresh(requestPermission: false)
    }

    func refresh(requestPermission: Bool = false) async {
        guard !paused else { return }
        if let running {
            await running.value
            return
        }
        guard enabled || mayHaveRegistration else { return }
        let task = Task { await sync(requestPermission: requestPermission) }
        running = task
        await task.value
        running = nil
    }

    /// This runs before the Auth session is revoked. Local deregistration
    /// protects the phone even if the server can't be reached at sign-out.
    func prepareSignOut() async {
        paused = true
        let pending = running
        pending?.cancel()
        await pending?.value
        await withdraw()
    }

    func resumeAfterSignOutAttempt() async {
        guard (try? await provider()) != nil else { return }
        paused = false
        await refresh()
    }

    func endSession() {
        paused = true
        running?.cancel()
        confirmedToken = nil
    }

    private func sync(requestPermission: Bool) async {
        if !enabled {
            await withdraw()
            return
        }
        do {
            if requestPermission, await system.authorization() == .notDetermined {
                status = .updating
                _ = try await system.requestAuthorization()
            }
            guard await system.authorization() == .authorized else {
                await withdraw()
                if status != .unavailable { status = .permissionDenied }
                return
            }
            if confirmedToken == nil || confirmedDaytime != daytime { status = .updating }
            let repository = try await provider()
            let preferences = try await MobileReminderRepository(transport: repository.transport)
                .notificationPreferences().data
            guard preferences.pushEnabled else {
                status = .preferencesOff
                return
            }
            let token = try await FlowMealPushRegistration.shared.token()
            try Task.checkCancellation()
            guard !paused else { return }
            if confirmedToken != token || confirmedDaytime != daytime {
                mayHaveRegistration = true
                try await repository.register(installation: installation, environment: environment,
                                              token: token, daytime: daytime)
                try Task.checkCancellation()
                confirmedToken = token
                confirmedDaytime = daytime
            }
            status = .active
        } catch is CancellationError {
            return
        } catch {
            if !paused { status = .unavailable }
        }
    }

    private func withdraw() async {
        if mayHaveRegistration || confirmedToken != nil {
            UIApplication.shared.unregisterForRemoteNotifications()
        }
        confirmedToken = nil
        confirmedDaytime = nil
        do {
            if mayHaveRegistration {
                status = .updating
                let repository = try await provider()
                try await repository.unregister(installation: installation)
                mayHaveRegistration = false
            }
            status = .off
        } catch {
            status = .unavailable
        }
    }
}
