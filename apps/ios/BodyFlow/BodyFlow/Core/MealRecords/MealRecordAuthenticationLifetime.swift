import Foundation
import Observation

/// Local C11 admission authority; not an authentication generation or a bearer.
struct MealRecordAuthenticationTicket: Hashable, Sendable {
    let id: UUID
    init() { id = UUID() }
}

struct MealRecordAuthenticatedActivation: Hashable, Sendable {
    let ticket: MealRecordAuthenticationTicket
    let userID: String
}

/// Optional/default-off in AppFlowModel. No auth, lease or HTTP starts here.
@MainActor
@Observable
final class MealRecordAuthenticationLifetime {
    @ObservationIgnored private let ticketFactory: @MainActor @Sendable () -> MealRecordAuthenticationTicket
    @ObservationIgnored private var currentTicket: MealRecordAuthenticationTicket?
    @ObservationIgnored private var registeredBinding: MealRecordSessionBinding?
    @ObservationIgnored private var registeredWorkoutBinding: WorkoutRegistrationSessionBinding?
    @ObservationIgnored private var registeredBillingBinding: BillingSessionBinding?
    @ObservationIgnored private var retirementTail: Task<Void, Never>?
    @ObservationIgnored private var retirementSequence: UInt64 = 0
    private(set) var currentActivation: MealRecordAuthenticatedActivation?

    init(ticketFactory: @escaping @MainActor @Sendable () -> MealRecordAuthenticationTicket = {
        MealRecordAuthenticationTicket()
    }) {
        self.ticketFactory = ticketFactory
    }

    func beginAuthenticationBoundary() -> MealRecordAuthenticationTicket {
        retireRegisteredBinding()
        currentActivation = nil
        let ticket = ticketFactory()
        currentTicket = ticket
        return ticket
    }

    func isCurrent(_ ticket: MealRecordAuthenticationTicket?) -> Bool {
        guard let ticket else { return false }
        return currentTicket == ticket
    }

    @discardableResult
    func publishAuthenticated(userID: String, ticket: MealRecordAuthenticationTicket?)
        -> MealRecordAuthenticatedActivation? {
        guard let ticket, isCurrent(ticket), !userID.isEmpty else { return nil }
        if let currentActivation {
            return currentActivation.userID == userID ? currentActivation : nil
        }
        let activation = MealRecordAuthenticatedActivation(ticket: ticket, userID: userID)
        currentActivation = activation
        return activation
    }

    @discardableResult
    func register(binding: MealRecordSessionBinding, owner: Prompt14SessionOwner,
                  activation: MealRecordAuthenticatedActivation) -> Bool {
        guard currentActivation == activation, isCurrent(activation.ticket),
              owner.userID == activation.userID, owner.mealRecordBinding === binding,
              binding.isOpen else {
            retireUnregisteredBinding(binding)
            return false
        }
        if let registeredBinding {
            guard registeredBinding === binding else {
                retireUnregisteredBinding(binding)
                return false
            }
            return true
        }
        registeredBinding = binding
        return true
    }

    /// A distinct workout leaf borrows the same ticket without enabling C11.
    @discardableResult
    func registerWorkout(binding: WorkoutRegistrationSessionBinding, owner: Prompt14SessionOwner,
                         activation: MealRecordAuthenticatedActivation) -> Bool {
        guard currentActivation == activation, isCurrent(activation.ticket),
              owner.userID == activation.userID, owner.workoutRegistrationBinding === binding,
              binding.isOpen else {
            if registeredWorkoutBinding !== binding { scheduleWorkoutEnd(binding) }
            return false
        }
        if let registeredWorkoutBinding, registeredWorkoutBinding !== binding,
           registeredWorkoutBinding.isOpen {
            scheduleWorkoutEnd(binding)
            return false
        }
        registeredWorkoutBinding = binding
        return true
    }

    /// A distinct billing leaf borrows the same ticket without enabling C11.
    @discardableResult
    func registerBilling(binding: BillingSessionBinding, owner: Prompt14SessionOwner,
                         activation: MealRecordAuthenticatedActivation) -> Bool {
        guard currentActivation == activation, isCurrent(activation.ticket),
              owner.userID == activation.userID, owner.billingBinding === binding,
              binding.isOpen else {
            if registeredBillingBinding !== binding { scheduleBillingEnd(binding) }
            return false
        }
        if let predecessor = registeredBillingBinding, predecessor !== binding {
            guard !predecessor.isOpen else {
                scheduleBillingEnd(binding)
                return false
            }
            // A scene may have released its weak owner without joining end.
            // Preserve this last cleanup handle before replacing the slot.
            scheduleBillingEnd(predecessor)
        }
        registeredBillingBinding = binding
        return true
    }

    /// Synchronous accepted UI navigation may withdraw the current presentation.
    func withdrawVisibleActivation() {
        retireRegisteredBinding()
        currentActivation = nil
    }

    /// An async result is allowed to withdraw only its original admission.
    func withdrawVisibleActivation(ticket: MealRecordAuthenticationTicket?) {
        guard isCurrent(ticket) else { return }
        withdrawVisibleActivation()
    }

    func endSession() async {
        currentTicket = nil
        withdrawVisibleActivation()
        let pending = retirementTail
        let sequence = retirementSequence
        await pending?.value
        if retirementSequence == sequence { retirementTail = nil }
    }

    private func retireRegisteredBinding() {
        if let binding = registeredBinding {
            registeredBinding = nil
            scheduleEnd(binding)
        }
        if let binding = registeredWorkoutBinding {
            registeredWorkoutBinding = nil
            scheduleWorkoutEnd(binding)
        }
        if let binding = registeredBillingBinding {
            registeredBillingBinding = nil
            scheduleBillingEnd(binding)
        }
    }

    private func retireUnregisteredBinding(_ binding: MealRecordSessionBinding) {
        // A stale caller cannot close a currently registered grant that it borrowed.
        guard registeredBinding !== binding else { return }
        scheduleEnd(binding)
    }

    private func scheduleEnd(_ binding: MealRecordSessionBinding) {
        binding.invalidateSynchronously()
        let predecessor = retirementTail
        retirementSequence &+= 1
        retirementTail = Task {
            await predecessor?.value
            await binding.endSession()
        }
    }

    private func scheduleWorkoutEnd(_ binding: WorkoutRegistrationSessionBinding) {
        binding.invalidateSynchronously()
        let predecessor = retirementTail
        retirementSequence &+= 1
        retirementTail = Task {
            await predecessor?.value
            await binding.endSession()
        }
    }

    private func scheduleBillingEnd(_ binding: BillingSessionBinding) {
        binding.invalidateSynchronously()
        let predecessor = retirementTail
        retirementSequence &+= 1
        retirementTail = Task {
            await predecessor?.value
            await binding.endSession()
        }
    }
}
