import SwiftUI
import UIKit
import Foundation
import Observation
import Testing
@testable import BodyFlow

// Separate registry/protocol from MobileAPITransportTests. Only synthetic local fixtures.
@Suite("C11 actual Root/Shell consumer composition", .serialized)
@MainActor
struct MealRecordWiringTests {
    @Test("DI requires an explicit flag, non-demo mode and the real transport/lifecycle pair",
          arguments: C11WireSourceCase.allCases)
    func sourceAdmission(_ scenario: C11WireSourceCase) async throws {
        try await withWireFixture { fixture in
            let client: any APIClient = scenario == .wrongClient
                ? AppDependencies.scaffold().apiClient : fixture.transport
            let source = AppDependencies.makeMealRecordBindingSource(
                enabled: scenario != .disabled,
                mode: scenario == .demo ? .demo : .releaseUnavailable,
                client: client, lifecycle: scenario == .missingLifecycle ? nil : fixture.bindProbe)
            #expect((source != nil) == (scenario == .enabled))
            #expect(AppDependencies.scaffold().mealRecordBindingSource == nil)
            #expect(await fixture.bindProbe.bindLeaseCalls == 0)
            #expect(await fixture.server.requestCount == 0)
        }
    }

    @Test("Missing lifetime or missing source keeps the actual driver and owner OFF",
          arguments: C11WireOffCase.allCases)
    func defaultOff(_ scenario: C11WireOffCase) async throws {
        try await withWireFixture(sourceEnabled: scenario != .noSource,
                                  lifetimeEnabled: scenario != .noLifetime) { fixture in
            #expect(fixture.flow.state == .authenticated(userID: C11WireFixtures.userID))
            #expect(!fixture.driver.isEnabled)
            #expect(fixture.driver.taskID == nil)
            #expect(await fixture.driver.synchronize(expected: nil) == nil)
            #expect(fixture.driver.readyContext == nil)
            #expect(fixture.owner.mealRecordBinding == nil)
            #expect(fixture.owner.reserveNewMealRecordBinding() == nil)
            #expect(!fixture.owner.isInvalidated)
            #expect(await fixture.bindProbe.bindLeaseCalls == 0)
            #expect(await fixture.server.requestCount == 0)
        }
    }

    @Test("The actual View driver captures the original owner and publishes observable readiness without GET")
    func driverCapturesOwnerAndPublishesReady() async throws {
        try await withWireFixture { fixture in
            let original = try #require(fixture.driver.taskID)
            #expect(original.owner == ObjectIdentifier(fixture.owner))
            #expect(original.activation == fixture.flow.mealRecordActivation)
            #expect(fixture.driver.readyContext == nil)
            let change = C11WireObservationProbe()
            withObservationTracking {
                _ = fixture.driver.readyContext
            } onChange: { change.markChanged() }
            let context = try #require(await fixture.driver.synchronize(expected: original))
            #expect(context.isActive)
            #expect(context.activation == original.activation)
            #expect(fixture.driver.readyContext === context)
            #expect(change.didChange)
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            #expect(model.detail == nil)
            #expect(model.draft == nil)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("Dismiss/reentry with the same original context preserves the actual cached Model, draft and unknown command")
    func cachePreservesDismissedUnknownCommand() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            await model.load()
            try #require(model.canSave(language: .portugueseBrazil))
            model.draft?.items[0].quantityText = "25"
            await fixture.server.loseNextMutationResponse()
            await model.save(language: .portugueseBrazil)
            let originalAttempt = try #require(model.retainedAttempt)
            #expect(model.confirmedReceipt == nil)
            #expect(fixture.keys.count == 1)
            #expect(await fixture.server.requestCount == 2)
            model.discardPresentation()
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let reentered = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            #expect(reentered === model)
            #expect(reentered.retainedAttempt == originalAttempt)
            #expect(reentered.draft?.items[0].quantityText == "25")
            #expect(fixture.keys.count == 1)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 2)
            #expect(fixture.center.revision(for: .today) == 0)
            #expect(fixture.center.revision(for: .history) == 0)
        }
    }

    @Test("Same-user real reauthentication changes the leaf/cache while keeping the actual parent owner and generation")
    func sameUserReauthenticationReplacesOnlyMealCache() async throws {
        try await withWireFixture { fixture in
            let originalTask = try #require(fixture.driver.taskID)
            let first = try #require(await fixture.driver.synchronize(expected: originalTask))
            let firstLease = try await fixture.coordinator.leaseForRequest()
            fixture.cache.synchronize(context: first, owner: fixture.owner)
            let old = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: first, owner: fixture.owner))
            await old.load()
            old.draft?.items[0].quantityText = "25"
            try #require(old.canSave(language: .portugueseBrazil))
            await fixture.remote.setSignInRecord(try C11WireFixtures.record(ordinal: 2))
            // The real service/coordinator and AppFlowModel hooks own this boundary.
            await fixture.flow.signIn(email: "wire@example.invalid", password: "synthetic-password-only")
            let nextTask = try #require(fixture.driver.taskID)
            let nextLease = try await fixture.coordinator.leaseForRequest()
            #expect(nextTask.activation != originalTask.activation)
            #expect(nextTask.owner == originalTask.owner)
            #expect(nextLease.userID == firstLease.userID)
            #expect(nextLease.generation == firstLease.generation)
            #expect(!fixture.owner.isInvalidated)
            #expect(fixture.owners.renderableOwner(for: C11WireFixtures.userID) === fixture.owner)
            #expect(!first.isActive)
            // No redraw/cache effect has happened yet: the old Model's predicate denies starts.
            #expect(!old.canSave(language: .portugueseBrazil))
            await old.save(language: .portugueseBrazil)
            #expect(fixture.keys.count == 0)
            #expect(await fixture.server.requestCount == 1)
            let second = try #require(await fixture.driver.synchronize(expected: nextTask))
            #expect(second.isActive)
            #expect(second.capability !== first.capability)
            fixture.cache.synchronize(context: second, owner: fixture.owner)
            let fresh = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: second, owner: fixture.owner))
            #expect(fresh !== old)
            #expect(old.detail == nil)
            #expect(old.draft == nil)
            #expect(old.retainedAttempt == nil)
            #expect(fresh.detail == nil)
            #expect(fresh.draft == nil)
            // Stale/nil View effects cannot revoke this live A2.
            #expect(await fixture.driver.synchronize(expected: originalTask) == nil)
            #expect(await fixture.driver.synchronize(expected: nil) == nil)
            fixture.cache.synchronize(context: first, owner: fixture.owner)
            fixture.cache.synchronize(context: nil, owner: fixture.owner)
            #expect(fixture.driver.readyContext === second)
            #expect(fixture.cache.isCurrent(context: second, owner: fixture.owner))
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: second, owner: fixture.owner) === fresh)
            #expect(await fixture.bindProbe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 1)
            #expect(fixture.center.revision(for: .today) == 0)
            #expect(fixture.center.revision(for: .history) == 0)
        }
    }

    @Test("A receipt from the real cached Model invalidates the Shell's SAME Today/History center once")
    func cachedModelUsesOriginalInvalidationCenter() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            await model.load()
            model.draft?.items[0].quantityText = "25"
            await model.save(language: .portugueseBrazil)
            let receipt = try #require(model.confirmedReceipt)
            #expect(receipt.data.operation == .updated)
            #expect(receipt.data.snapshot.caloriesConsumed == 321)
            #expect(receipt.data.nextRecordID == C11WireFixtures.replacementID)
            #expect(fixture.center.revision(for: .today) == 1)
            #expect(fixture.center.revision(for: .history) == 1)
            model.discardPresentation()
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner) === model)
            #expect(fixture.center.revision(for: .today) == 1)
            #expect(fixture.center.revision(for: .history) == 1)
            #expect(fixture.keys.count == 1)
            #expect(await fixture.server.requestCount == 2)
        }
    }

    @Test("Nil and foreign-owner Shell effects preserve a live original cached context")
    func foreignOrNilCacheEffectsCannotDiscardCurrent() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            let other = Prompt14SessionOwner(userID: C11WireFixtures.userID,
                dependencies: fixture.dependencies, enablesMealRecordBinding: true)
            // This constructor starts only the owner's existing /me task; join it explicitly.
            await other.awaitPatientTimeZoneResolution()
            fixture.cache.synchronize(context: context, owner: other)
            fixture.cache.synchronize(context: nil, owner: fixture.owner)
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: other) == nil)
            #expect(fixture.cache.isCurrent(context: context, owner: fixture.owner))
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner) === model)
            #expect(fixture.driver.readyContext === context)
            #expect(context.isActive)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            await other.endSession()
        }
    }
    // H05 consumer coverage: these are the same Driver/cache APIs used by Root/Shell.
    @Test("U1 recovery projection is passive and requires the actual original offer")
    func recoveryProjectionIsPassive() async throws {
        try await withRecoveryFixture { fixture in
            #expect(fixture.driver.recoveryAvailability(for: fixture.owner) == .unavailable)
            let offer = try await fixture.failLogout()
            let ticketCount = fixture.tickets.count
            let leases = await fixture.probe.bindLeaseCalls
            let remoteCounts = await fixture.remote.counts()
            let telemetry = await fixture.telemetry.snapshot()
            let state = C11RecoveryPublicSnapshot(fixture.flow)
            for _ in 0..<4 {
                #expect(fixture.driver.recoveryAvailability(for: fixture.owner) == .available(offer))
                #expect(fixture.driver.readyContext == nil)
            }
            #expect(fixture.tickets.count == ticketCount)
            #expect(await fixture.probe.bindLeaseCalls == leases)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            #expect(await fixture.remote.counts() == remoteCounts)
            #expect(await fixture.telemetry.snapshot() == telemetry)
            #expect(C11RecoveryPublicSnapshot(fixture.flow) == state)
        }
    }

    @Test("U2 rejected source/lifetime/owner admission never consumes the Model's real offer",
          arguments: C11RecoveryRejectedAdmission.allCases)
    func recoveryRejectsBeforeAuthority(_ scenario: C11RecoveryRejectedAdmission) async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            var driver = fixture.driver
            var owner = fixture.owner
            switch scenario {
            case .sourceOff:
                driver = MealRecordRootWiringDriver(model: fixture.flow, ownerCoordinator: fixture.owners,
                    lifetime: fixture.lifetime, source: nil)
            case .lifetimeNil:
                driver = MealRecordRootWiringDriver(model: fixture.flow, ownerCoordinator: fixture.owners,
                    lifetime: nil, source: fixture.source)
            case .lifetimeWithoutOriginalAnchor:
                let otherLifetime = MealRecordAuthenticationLifetime()
                fixture.addCleanup { await otherLifetime.endSession() }
                driver = MealRecordRootWiringDriver(model: fixture.flow, ownerCoordinator: fixture.owners,
                    lifetime: otherLifetime, source: fixture.source)
            case .ownerOff:
                let offOwners = Prompt14AuthenticatedShellCoordinator(dependencies: fixture.dependencies,
                    enablesMealRecordBinding: false)
                fixture.addCleanup { await offOwners.transition(to: nil) }
                await offOwners.transition(to: C11WireFixtures.userID)
                owner = try #require(offOwners.renderableOwner(for: C11WireFixtures.userID))
                await owner.awaitPatientTimeZoneResolution()
                driver = MealRecordRootWiringDriver(model: fixture.flow, ownerCoordinator: offOwners,
                    lifetime: fixture.lifetime, source: fixture.source)
            case .wrongUser, .foreignSameUser:
                let userID = scenario == .wrongUser ? C11RecoveryRecords.userB : C11WireFixtures.userID
                let other = Prompt14SessionOwner(userID: userID, dependencies: fixture.dependencies,
                    enablesMealRecordBinding: true)
                fixture.addCleanup { await other.endSession() }
                await other.awaitPatientTimeZoneResolution()
                owner = other
            case .closedOwner:
                fixture.owner.invalidateSynchronously()
            }
            let count = fixture.tickets.count
            let state = C11RecoveryPublicSnapshot(fixture.flow)
            let remote = await fixture.remote.counts()
            #expect(driver.recoveryAvailability(for: owner) == .unavailable)
            #expect(await driver.recover(offer: offer, owner: owner) == nil)
            #expect(fixture.tickets.count == count)
            #expect(fixture.lifetime.isCurrent(offer.anchorTicket))
            #expect(fixture.flow.availableMealRecordRecoveryOffer == offer)
            #expect(!fixture.flow.isMealRecordRecoveryInProgress)
            #expect(C11RecoveryPublicSnapshot(fixture.flow) == state)
            #expect(await fixture.probe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            #expect(await fixture.remote.counts() == remote)
        }
    }

    @Test("U2 each actual pending auth entry/PW blocks the retained callback without extra authority",
          arguments: C11RecoveryAuthEntry.allCases)
    func recoveryRejectsDuringRealAuthAwait(_ entry: C11RecoveryAuthEntry) async throws {
        try await withRecoveryFixture { fixture in
            let originalOffer = try await fixture.failLogout()
            let held = C11RecoveryCheckpoint()
            await fixture.authentication.hold(entry, using: held)
            let pending = Task {
                await C11RecoveryAuthEntry.perform(entry, on: fixture.flow)
                await held.noteCompletion()
            }
            fixture.retain(pending)
            try #require(await held.waitUntilEnteredOrCompleted())
            let count = fixture.tickets.count
            let state = C11RecoveryPublicSnapshot(fixture.flow)
            let telemetry = await fixture.telemetry.snapshot()
            let remote = await fixture.remote.counts()
            #expect(fixture.flow.isMealRecordAuthenticationBusy)
            #expect(fixture.driver.recoveryAvailability(for: fixture.owner) == .unavailable)
            #expect(await fixture.driver.recover(offer: originalOffer, owner: fixture.owner) == nil)
            #expect(fixture.tickets.count == count)
            #expect(C11RecoveryPublicSnapshot(fixture.flow) == state)
            #expect(await fixture.telemetry.snapshot() == telemetry)
            #expect(await fixture.remote.counts() == remote)
            #expect(await fixture.probe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            await held.release()
            await pending.value
        }
    }

    @Test("U3 original recovery reserves before await; double tap and generic Root task coalesce one lease")
    func recoveryReservesAndCoalescesOriginal() async throws {
        try await withRecoveryFixture { fixture in
            let original = fixture.originalContext
            let offer = try await fixture.failLogout()
            let ticketCount = fixture.tickets.count
            let held = C11RecoveryCheckpoint()
            await fixture.probe.holdNextLease(using: held)
            let first = fixture.recovering(offer: offer, checkpoint: held)
            try #require(await held.waitUntilEnteredOrCompleted())
            let taskID = try #require(fixture.driver.taskID)
            #expect(taskID.activation.ticket != offer.anchorTicket)
            #expect(taskID.owner == ObjectIdentifier(fixture.owner))
            #expect(fixture.tickets.count == ticketCount + 1)
            #expect(!original.isActive)
            #expect(!original.capability.hasRetainedCapability)
            #expect(fixture.driver.recoveryAvailability(for: fixture.owner) == .processing)
            #expect(fixture.flow.isMealRecordRecoveryInProgress)
            #expect(await fixture.driver.recover(offer: offer, owner: fixture.owner) == nil)
            #expect(await fixture.driver.synchronize(expected: nil) == nil)
            let generic = Task { await fixture.driver.synchronize(expected: taskID) }
            fixture.retain(generic)
            await held.release()
            let context = try #require(await first.value)
            let genericContext = try #require(await generic.value)
            #expect(context === genericContext)
            #expect(context.isActive)
            #expect(context.activation == taskID.activation)
            #expect(!fixture.flow.isMealRecordRecoveryInProgress)
            #expect(fixture.flow.availableMealRecordRecoveryOffer == nil)
            #expect(fixture.driver.recoveryAvailability(for: fixture.owner) == .unavailable)
            #expect(fixture.tickets.count == ticketCount + 1)
            #expect(await fixture.probe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("U4 retained original callback cannot spend a new offer or mismatched public snapshot",
          arguments: C11RecoveryRetainedCallback.allCases)
    func recoveryRetainedCallbackRejectsNewState(_ scenario: C11RecoveryRetainedCallback) async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let originalOwner = fixture.owner
            let originalDriver = fixture.driver
            let retained = { @MainActor in await originalDriver.recover(offer: offer, owner: originalOwner) }
            var oldRestore: Task<Void, Never>?
            var restoreHold: C11RecoveryCheckpoint?
            if scenario == .snapshotMismatch {
                let held = C11RecoveryCheckpoint()
                restoreHold = held
                await fixture.authentication.holdNextCapturedRestore(using: held)
                let work = Task { await fixture.flow.start(); await held.noteCompletion() }
                fixture.retain(work); oldRestore = work
                try #require(await held.waitUntilEnteredOrCompleted())
            }
            if scenario == .aba {
                await fixture.remote.setSignInRecord(try C11RecoveryRecords.record(userID: C11RecoveryRecords.userB, ordinal: 2))
                await fixture.flow.signIn(email: "wire@example.invalid", password: "synthetic-password-only")
            }
            await fixture.remote.setSignInRecord(try C11RecoveryRecords.record(ordinal: 3, email: "wire-new@example.invalid"))
            await fixture.flow.signIn(email: "wire-new@example.invalid", password: "synthetic-password-only")
            let newOffer: MealRecordRecoveryOffer
            if scenario == .snapshotMismatch {
                // The real earlier restore is still held: its activity keeps
                // the visible-offer getter intentionally nil. Observe the
                // real logout failure and issued ticket rather than asking
                // failLogout() to require a visible/eligible offer here.
                await fixture.secure.rejectMarker()
                let beforeLogout = fixture.tickets.count
                await fixture.flow.signOut()
                #expect(fixture.flow.presentationError == .storageUnavailable)
                #expect(fixture.flow.state == .authenticated(userID: C11WireFixtures.userID))
                let latest = try #require(fixture.flow.currentSession)
                let actualLogoutTicket = try #require(fixture.tickets.issued.last)
                #expect(fixture.tickets.count == beforeLogout + 1)
                #expect(fixture.lifetime.isCurrent(actualLogoutTicket))
                // Comparison/refusal value ONLY. It comes from actual
                // public session facts + the actual signOut ticket factory;
                // never installs an offer or grants admission/authority.
                newOffer = MealRecordRecoveryOffer(anchorTicket: actualLogoutTicket, session: latest)
                let issued = fixture.tickets.count
                #expect(fixture.flow.isMealRecordAuthenticationBusy)
                #expect(fixture.flow.availableMealRecordRecoveryOffer == nil)
                #expect(fixture.flow.beginMealRecordRecovery(offer: newOffer) == nil)
                #expect(fixture.tickets.count == issued)
                #expect(fixture.flow.mealRecordActivation == nil)
            } else {
                // The sameUser/ABA controls still require a REAL visible
                // offer from the unchanged successful test helper.
                newOffer = try await fixture.failLogout()
            }
            if let restoreHold, let oldRestore {
                await restoreHold.release(); await oldRestore.value
                #expect(fixture.flow.currentSession != newOffer.session)
                #expect(fixture.flow.availableMealRecordRecoveryOffer == nil)
                #expect(fixture.lifetime.isCurrent(newOffer.anchorTicket))
                #expect(!fixture.flow.isMealRecordAuthenticationBusy)
                #expect(fixture.flow.state == .authenticated(userID: newOffer.session.userID))
                #expect(fixture.flow.currentSession?.userID == newOffer.session.userID)
                #expect(fixture.flow.currentSession == offer.session)
                #expect(fixture.flow.currentSession?.isEmailConfirmed == true)
                #expect(fixture.flow.currentSession?.isOnboardingCompleted == true)
                let beforeRefusal = C11RecoveryPublicSnapshot(fixture.flow)
                let issued = fixture.tickets.count
                // Busy has ended, and user ID/confirmed/completed still
                // match. The FULL late public snapshot alone now prevents
                // this newer candidate from being spent.
                #expect(fixture.flow.beginMealRecordRecovery(offer: newOffer) == nil)
                #expect(await originalDriver.recover(offer: newOffer, owner: originalOwner) == nil)
                #expect(fixture.tickets.count == issued)
                #expect(C11RecoveryPublicSnapshot(fixture.flow) == beforeRefusal)
                #expect(fixture.lifetime.isCurrent(newOffer.anchorTicket))
                #expect(fixture.flow.mealRecordActivation == nil)
            }
            let count = fixture.tickets.count
            let state = C11RecoveryPublicSnapshot(fixture.flow)
            #expect(await retained() == nil)
            #expect(fixture.tickets.count == count)
            #expect(C11RecoveryPublicSnapshot(fixture.flow) == state)
            #expect(await fixture.probe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            if scenario != .snapshotMismatch {
                #expect(fixture.flow.availableMealRecordRecoveryOffer == newOffer)
                let context = try #require(await fixture.driver.recover(offer: newOffer, owner: fixture.owner))
                #expect(context.isActive)
                #expect(fixture.tickets.count == count + 1)
                #expect(await fixture.probe.bindLeaseCalls == 2)
            }
        }
    }

    @Test("U5 cancellation before admission or during the real bind has scoped cleanup and explicit retry only",
          arguments: C11RecoveryCancellation.allCases)
    func recoveryCancellationIsScoped(_ boundary: C11RecoveryCancellation) async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let count = fixture.tickets.count
            let held = C11RecoveryCheckpoint()
            let work: Task<MealRecordReadyContext?, Never>
            if boundary == .beforeAdmission {
                work = Task {
                    await held.enterAndWait()
                    let result = await fixture.driver.recover(offer: offer, owner: fixture.owner)
                    await held.noteCompletion()
                    return result
                }
                fixture.retain(work)
            } else {
                await fixture.probe.holdNextLease(using: held)
                work = fixture.recovering(offer: offer, checkpoint: held)
            }
            fixture.addCleanup { await held.release() }
            try #require(await held.waitUntilEnteredOrCompleted())
            work.cancel()
            await held.release()
            #expect(await work.value == nil)
            #expect(fixture.driver.readyContext == nil)
            #expect(!fixture.flow.isMealRecordRecoveryInProgress)
            #expect(fixture.tickets.count == count + (boundary == .beforeAdmission ? 0 : 1))
            #expect(await fixture.probe.bindLeaseCalls == (boundary == .beforeAdmission ? 1 : 2))
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            let nextOffer = try #require(fixture.flow.availableMealRecordRecoveryOffer)
            let beforeExplicit = fixture.tickets.count
            let context = try #require(await fixture.driver.recover(offer: nextOffer, owner: fixture.owner))
            #expect(context.isActive)
            #expect(fixture.tickets.count == beforeExplicit + 1)
            #expect(await fixture.probe.bindLeaseCalls == (boundary == .beforeAdmission ? 2 : 3))
        }
    }

    @Test("U6 password recovery remains pending across recovery success/failure and never rearms authority",
          arguments: C11RecoveryBindingOutcome.allCases)
    func recoveryPasswordActivitySurvivesBind(_ outcome: C11RecoveryBindingOutcome) async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let leaseHold = C11RecoveryCheckpoint()
            await fixture.probe.holdNextLease(using: leaseHold)
            let recovering = fixture.recovering(offer: offer, checkpoint: leaseHold)
            try #require(await leaseHold.waitUntilEnteredOrCompleted())
            let originalActivation = try #require(fixture.flow.mealRecordActivation)
            let passwordHold = C11RecoveryCheckpoint()
            await fixture.authentication.hold(.passwordRecovery, using: passwordHold)
            let password = Task {
                await fixture.flow.requestPasswordRecovery(email: "wire@example.invalid")
                await passwordHold.noteCompletion()
            }
            fixture.retain(password)
            try #require(await passwordHold.waitUntilEnteredOrCompleted())
            #expect(fixture.flow.mealRecordActivation == originalActivation)
            #expect(fixture.flow.isMealRecordAuthenticationBusy)
            let count = fixture.tickets.count
            if outcome == .realMissingSession {
                // Real store/coordinator invalidation, not an injected fake lease/error.
                await fixture.secure.rejectMarker(false)
                #expect(await fixture.coordinator.signOut() == .confirmed)
            }
            await leaseHold.release()
            let result = await recovering.value
            #expect((result != nil) == (outcome == .success))
            #expect(!fixture.flow.isMealRecordRecoveryInProgress)
            #expect(fixture.flow.isMealRecordAuthenticationBusy)
            #expect(fixture.flow.availableMealRecordRecoveryOffer == nil)
            #expect(fixture.tickets.count == count)
            #expect(await fixture.probe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            await passwordHold.release(); await password.value
            #expect(!fixture.flow.isMealRecordAuthenticationBusy)
            #expect(fixture.tickets.count == count)
            if outcome == .success {
                #expect(result?.isActive == true)
                #expect(fixture.flow.mealRecordActivation == originalActivation)
                #expect(fixture.flow.availableMealRecordRecoveryOffer == nil)
            } else {
                let newOffer = try #require(fixture.flow.availableMealRecordRecoveryOffer)
                #expect(newOffer.anchorTicket == originalActivation.ticket)
                #expect(fixture.driver.recoveryAvailability(for: fixture.owner) == .available(newOffer))
                #expect(fixture.driver.readyContext == nil)
            }
        }
    }

    @Test("U7 late recovery R1 cannot finish or revoke actual same-user A2 ready/cache")
    func lateRecoveryCannotRevokeNewAuthentication() async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let held = C11RecoveryCheckpoint()
            await fixture.probe.holdNextLease(using: held)
            let old = fixture.recovering(offer: offer, checkpoint: held)
            try #require(await held.waitUntilEnteredOrCompleted())
            await fixture.remote.setSignInRecord(try C11RecoveryRecords.record(ordinal: 2))
            await fixture.flow.signIn(email: "wire@example.invalid", password: "synthetic-password-only")
            let taskID = try #require(fixture.driver.taskID)
            let context = try #require(await fixture.driver.synchronize(expected: taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            let state = C11RecoveryPublicSnapshot(fixture.flow)
            let count = fixture.tickets.count
            await held.release()
            #expect(await old.value == nil)
            #expect(context.isActive)
            #expect(fixture.driver.readyContext === context)
            #expect(fixture.cache.isCurrent(context: context, owner: fixture.owner))
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner) === model)
            #expect(C11RecoveryPublicSnapshot(fixture.flow) == state)
            #expect(fixture.tickets.count == count)
            #expect(!fixture.flow.isMealRecordRecoveryInProgress)
            #expect(fixture.flow.availableMealRecordRecoveryOffer == nil)
            #expect(await fixture.probe.bindLeaseCalls == 3)
            #expect(await fixture.server.requestCount == 0)
        }
    }

    @Test("U8 old unknown K1 cannot replay after reconnect; only a new reviewed edit creates K2")
    func recoveryDoesNotReplayUnknownCommand() async throws {
        try await withRecoveryFixture { fixture in
            let first = fixture.originalContext
            fixture.cache.synchronize(context: first, owner: fixture.owner)
            let old = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: first, owner: fixture.owner))
            await old.load()
            old.draft?.items[0].quantityText = "25"
            await fixture.server.loseNextMutationResponse()
            await old.save(language: .portugueseBrazil)
            let original = try #require(old.retainedAttempt)
            guard case let .patch(oldAttempt) = original else {
                Issue.record("U8 requires the original real PATCH attempt"); return
            }
            let offer = try await fixture.failLogout()
            #expect(old.retainedAttempt == original)
            #expect(!old.canSave(language: .portugueseBrazil))
            await old.retry()
            #expect(await fixture.server.requestCount == 2)
            #expect(fixture.keys.count == 1)
            let second = try #require(await fixture.driver.recover(offer: offer, owner: fixture.owner))
            #expect(second.isActive)
            #expect(await fixture.server.requestCount == 2)
            #expect(fixture.keys.count == 1)
            fixture.cache.synchronize(context: second, owner: fixture.owner)
            let fresh = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: second, owner: fixture.owner))
            #expect(fresh !== old)
            #expect(old.draft == nil && old.retainedAttempt == nil)
            #expect(fresh.draft == nil && fresh.retainedAttempt == nil)
            await fresh.load()
            fresh.draft?.items[0].quantityText = "30"
            await fresh.save(language: .portugueseBrazil)
            try #require(fresh.confirmedReceipt)
            #expect(fixture.keys.count == 2)
            #expect(fresh.attemptHistory.count == 1)
            guard case let .patch(newAttempt)? = fresh.attemptHistory.first else {
                Issue.record("U8 requires the new reviewed PATCH attempt"); return
            }
            #expect(newAttempt.key != oldAttempt.key)
            #expect(await fixture.server.commandKeys == [oldAttempt.key.value, newAttempt.key.value])
            #expect(await fixture.server.requestCount == 4)
            #expect(fixture.center.revision(for: .today) == 1)
            #expect(fixture.center.revision(for: .history) == 1)
            #expect(!fixture.owner.isInvalidated)
        }
    }

    @Test("U9 old PATCH/DELETE HTTP receipt held after real finish cannot publish after reconnect",
          arguments: C11RecoveryReceiptOperation.allCases)
    func recoverySuppressesOldHTTPReceipt(_ operation: C11RecoveryReceiptOperation) async throws {
        try await withRecoveryFixture { fixture in
            fixture.cache.synchronize(context: fixture.originalContext, owner: fixture.owner)
            let old = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: fixture.originalContext, owner: fixture.owner))
            await old.load()
            if operation == .delete {
                let deleted = MealRecordMutationResponse(data: MealRecordMutationSnapshot(
                    recordID: C11WireFixtures.recordID, operation: .deleted, newItemIDs: [],
                    removedItemIDs: [C11WireFixtures.recordID], nextRecordID: nil,
                    snapshot: MealRecordPersistedSnapshot(id: "synthetic-held-delete", date: "2026-10-13",
                        caloriesConsumed: 0, proteinG: 0, carbsG: 0, fatG: 0, dailyBalance: 77)),
                    meta: C11WireFixtures.meta)
                await fixture.server.stageBody(try JSONEncoder().encode(deleted), for: "DELETE")
            }
            let held = C11RecoveryCheckpoint()
            await fixture.boundaries.holdNextFinishedPatientWork(using: held)
            let mutation = Task {
                if operation == .patch { await old.save(language: .portugueseBrazil) }
                else { await old.delete() }
                await held.noteCompletion()
            }
            fixture.retain(mutation)
            try #require(await held.waitUntilEnteredOrCompleted())
            // HTTP completed, real registry finish delegated; validation/decode/
            // Model publication are still pending. No receipt was installed.
            #expect(await fixture.server.requestCount == 2)
            #expect(old.confirmedReceipt == nil)
            #expect(fixture.center.revision(for: .today) == 0)
            #expect(fixture.center.revision(for: .history) == 0)
            let offer = try await fixture.failLogout()
            let context = try #require(await fixture.driver.recover(offer: offer, owner: fixture.owner))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let fresh = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            await held.release(); await mutation.value
            #expect(context.isActive)
            #expect(fresh !== old)
            #expect(old.confirmedReceipt == nil)
            #expect(fresh.confirmedReceipt == nil)
            #expect(fresh.draft == nil)
            #expect(fixture.center.revision(for: .today) == 0)
            #expect(fixture.center.revision(for: .history) == 0)
            #expect(await fixture.server.requestCount == 2)
            #expect(fixture.keys.count == 1)
        }
    }

    @Test("Reported candidate UI bug: PW early rejection clears the request and rearms the SAME offer task key")
    func rejectedRecoveryPresentationCanRetrySameOffer() async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let held = C11RecoveryCheckpoint()
            await fixture.authentication.hold(.passwordRecovery, using: held)
            let password = Task {
                await fixture.flow.requestPasswordRecovery(email: "wire@example.invalid")
                await held.noteCompletion()
            }
            fixture.retain(password)
            try #require(await held.waitUntilEnteredOrCompleted())
            let requests = MealRecordRecoveryPresentationCoordinator()
            var callbacks = 0
            var lastContext: MealRecordReadyContext?
            let originalDriver = fixture.driver
            let originalOwner = fixture.owner
            let action: @MainActor () async -> Void = {
                callbacks += 1
                lastContext = await originalDriver.recover(offer: offer, owner: originalOwner)
            }
            let beforeRejected = fixture.tickets.count
            let first = requests.enqueue(offer: offer, perform: action)
            let firstKey = requests.taskID
            #expect(firstKey == offer.anchorTicket)
            await requests.run(first)
            let completedKey = requests.taskID
            #expect(callbacks == 1)
            #expect(lastContext == nil)
            #expect(requests.current == nil)
            #expect(completedKey == nil)
            #expect(fixture.tickets.count == beforeRejected)
            #expect(fixture.flow.availableMealRecordRecoveryOffer == nil) // PW still pending
            #expect(await fixture.probe.bindLeaseCalls == 1)
            await held.release(); await password.value
            #expect(fixture.flow.availableMealRecordRecoveryOffer == offer)
            let second = requests.enqueue(offer: offer, perform: action)
            let secondKey = requests.taskID
            #expect(second !== first)
            #expect(secondKey == offer.anchorTicket)
            #expect(secondKey != completedKey)
            #expect([firstKey, completedKey, secondKey] == [offer.anchorTicket, nil, offer.anchorTicket])
            // The same real API the View's task calls, without inventing a scheduler.
            // UIKit tap/task scheduling itself belongs to the separate XCUI gate.
            await requests.run(second)
            let recovered = try #require(lastContext)
            #expect(recovered.isActive)
            #expect(callbacks == 2)
            #expect(requests.current == nil)
            #expect(requests.taskID == nil)
            #expect(fixture.tickets.count == beforeRejected + 1)
            #expect(await fixture.probe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("Original presentation completion/cancellation cannot clear A2, and duplicate same-offer requests coalesce",
          arguments: C11RecoveryOldPresentationCompletion.allCases)
    func oldRecoveryPresentationCannotClearNewRequest(_ completion: C11RecoveryOldPresentationCompletion) async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let passwordHold = C11RecoveryCheckpoint()
            await fixture.authentication.hold(.passwordRecovery, using: passwordHold)
            let password = Task {
                await fixture.flow.requestPasswordRecovery(email: "wire@example.invalid")
                await passwordHold.noteCompletion()
            }
            fixture.retain(password)
            try #require(await passwordHold.waitUntilEnteredOrCompleted())
            let requests = MealRecordRecoveryPresentationCoordinator()
            let oldCompletion = C11RecoveryCheckpoint()
            fixture.addCleanup { await oldCompletion.release() }
            let originalDriver = fixture.driver
            let originalOwner = fixture.owner
            let first = requests.enqueue(offer: offer) {
                #expect(await originalDriver.recover(offer: offer, owner: originalOwner) == nil)
                // Hold only the UI consumer's return, after the real early refusal.
                await oldCompletion.enterAndWait()
            }
            let oldTask = Task { await requests.run(first); await oldCompletion.noteCompletion() }
            fixture.retain(oldTask)
            try #require(await oldCompletion.waitUntilEnteredOrCompleted())
            await passwordHold.release(); await password.value
            await fixture.remote.setSignInRecord(try C11RecoveryRecords.record(ordinal: 2))
            await fixture.flow.signIn(email: "wire@example.invalid", password: "synthetic-password-only")
            let newOffer = try await fixture.failLogout()
            #expect(newOffer.anchorTicket != offer.anchorTicket)
            let leaseHold = C11RecoveryCheckpoint()
            await fixture.probe.holdNextLease(using: leaseHold)
            var newest: MealRecordReadyContext?
            let second = requests.enqueue(offer: newOffer) {
                newest = await originalDriver.recover(offer: newOffer, owner: originalOwner)
            }
            let duplicate = requests.enqueue(offer: newOffer) {
                Issue.record("Duplicate pending presentation must not replace its captured action")
            }
            #expect(duplicate === second)
            #expect(requests.current === second)
            #expect(requests.taskID == newOffer.anchorTicket)
            let newerTask = Task { await requests.run(second); await leaseHold.noteCompletion() }
            fixture.retain(newerTask)
            try #require(await leaseHold.waitUntilEnteredOrCompleted())
            if completion == .cancelled { oldTask.cancel() }
            await oldCompletion.release(); await oldTask.value
            #expect(requests.current === second)
            #expect(requests.taskID == newOffer.anchorTicket)
            #expect(fixture.flow.isMealRecordRecoveryInProgress)
            await leaseHold.release(); await newerTask.value
            let context = try #require(newest)
            #expect(context.isActive)
            #expect(fixture.driver.readyContext === context)
            #expect(requests.current == nil)
            #expect(requests.taskID == nil)
            #expect(!fixture.flow.isMealRecordRecoveryInProgress)
            #expect(await fixture.probe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("A presentation task already cancelled before run still clears its original slot and preserves the real offer")
    func cancelledPresentationBeforeRunCanRetryOriginalOffer() async throws {
        try await withRecoveryFixture { fixture in
            let offer = try await fixture.failLogout()
            let requests = MealRecordRecoveryPresentationCoordinator()
            let pause = C11RecoveryCheckpoint()
            fixture.addCleanup { await pause.release() }
            let originalDriver = fixture.driver
            let originalOwner = fixture.owner
            var callbacks = 0
            var result: MealRecordReadyContext?
            let action: @MainActor () async -> Void = {
                callbacks += 1
                result = await originalDriver.recover(offer: offer, owner: originalOwner)
            }
            let original = requests.enqueue(offer: offer, perform: action)
            let count = fixture.tickets.count
            let work = Task {
                await pause.enterAndWait()
                // The actual View now always calls this terminal owner for a
                // captured non-nil request, even when its task is cancelled.
                await requests.run(original)
                await pause.noteCompletion()
            }
            fixture.retain(work)
            try #require(await pause.waitUntilEnteredOrCompleted())
            work.cancel()
            await pause.release(); await work.value
            #expect(callbacks == 0)
            #expect(requests.current == nil)
            #expect(requests.taskID == nil)
            #expect(fixture.flow.availableMealRecordRecoveryOffer == offer)
            #expect(fixture.tickets.count == count)
            #expect(await fixture.probe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            let next = requests.enqueue(offer: offer, perform: action)
            #expect(next !== original)
            #expect(requests.taskID == offer.anchorTicket)
            await requests.run(next)
            let context = try #require(result)
            #expect(context.isActive)
            #expect(callbacks == 1)
            #expect(requests.current == nil)
            #expect(requests.taskID == nil)
            #expect(fixture.tickets.count == count + 1)
            #expect(await fixture.probe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("Actual recovery footer fits compact/landscape viewport at AXXXL, with full PT/EN message and reachable 44pt action",
          arguments: C11RecoveryFooterViewportLanguage.allCases, C11RecoveryFooterRenderingState.allCases)
    func recoveryFooterRendersWithinAccessibleViewport(_ matrix: C11RecoveryFooterViewportLanguage,
        _ state: C11RecoveryFooterRenderingState) async throws {
        try await withRecoveryFixture { fixture in
            let originalOffer = try await fixture.failLogout()
            let availability: MealRecordRecoveryAvailability
            let action: (@MainActor () async -> Void)?
            if state == .available {
                #expect(fixture.flow.availableMealRecordRecoveryOffer == originalOffer)
                availability = .available(originalOffer)
                let originalDriver = fixture.driver
                let originalOwner = fixture.owner
                action = { _ = await originalDriver.recover(offer: originalOffer, owner: originalOwner) }
            } else {
                let activation = try #require(fixture.flow.beginMealRecordRecovery(offer: originalOffer))
                fixture.addCleanup { fixture.flow.finishMealRecordRecovery(activation, succeeded: false) }
                #expect(fixture.flow.isMealRecordRecoveryInProgress)
                availability = .processing // actual Model state; no simulated server phase
                action = nil
            }
            let count = fixture.tickets.count
            let remote = await fixture.remote.counts()
            let row = C11RecoveryFooterViewportLanguage.row()
            let destination = NavigationStack {
                MealRecordHistoryDestination(recordID: C11WireFixtures.recordID, localRow: row,
                    context: nil, owner: fixture.owner, sessions: fixture.cache,
                    recoveryAvailability: availability, recover: action)
            }
            .environment(\.locale, matrix.language.formattingLocale)
            .environment(\.bodyFlowReduceMotion, true)
            try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).contains { $0.isKeyWindow },
                "SETUP: the actual native hosting window is required for the recovery renderer")
            let host = SignUpRenderingProbe.host(destination, width: matrix.width, height: matrix.height,
                size: .accessibility5)
            defer { host.detach() }
            let geometry = try recoveryFooterGeometry(host, matrix, phase: "\(state)")
            let nodes = host.nodes()
            try #require(!nodes.isEmpty,
                "SETUP: native accessibility walk returned no nodes; do not skip or weaken the footer oracle")
            let notice = try #require(nodes.first { $0.identifier == "meal-record.recovery.notice" && $0.isElement },
                "SETUP_OR_MISSING_FOOTER: native walk has no notice node: \(nodes)")
            let button = try #require(nodes.first { $0.identifier == "meal-record.recovery.action" && $0.isElement && $0.isButton },
                "SETUP_OR_MISSING_FOOTER: native walk has no action node: \(nodes)")
            print("C11_FOOTER_CONTROLS matrix=\(matrix) state=\(state) hostScreen=\(geometry.frameOnScreen) notice=\(notice.frame) action=\(button.frame)")
            #expect(notice.label == MealRecordCopy.string("meal-record.recovery.notice", language: matrix.language))
            #expect(button.label == MealRecordCopy.string("meal-record.recovery.action", language: matrix.language))
            #expect(button.isEnabled == (state == .available))
            #expect(button.frame.width >= BodyFlowSpacing.minimumTapTarget)
            #expect(button.frame.height >= BodyFlowSpacing.minimumTapTarget)
            // The inset is outside the scrolling column. Preserve all four
            // complete-frame limits, now in the SAME measured coordinate
            // space as accessibilityFrame; no larger viewport or allowance.
            for node in [notice, button] {
                #expect(node.frame.width > 0 && node.frame.height > 0)
                #expect(node.frame.minX >= geometry.frameOnScreen.minX - 0.5)
                #expect(node.frame.maxX <= geometry.frameOnScreen.maxX + 0.5)
                #expect(node.frame.minY >= geometry.frameOnScreen.minY - 0.5)
                #expect(node.frame.maxY <= geometry.frameOnScreen.maxY + 0.5)
            }
            #expect(fixture.tickets.count == count)
            #expect(await fixture.remote.counts() == remote)
            #expect(await fixture.probe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("Actual default-OFF history fallback has no recovery footer, with mounted legacy scroll and positive AX control on the same native harness",
          arguments: C11RecoveryFooterViewportLanguage.allCases)
    func recoveryFooterIsAbsentForOffConsumer(_ matrix: C11RecoveryFooterViewportLanguage) async throws {
        try await withRecoveryFixture { fixture in
            let originalOffer = try await fixture.failLogout()
            let offDriver = MealRecordRootWiringDriver(model: fixture.flow, ownerCoordinator: fixture.owners,
                lifetime: fixture.lifetime, source: nil)
            let availability = offDriver.recoveryAvailability(for: fixture.owner)
            #expect(availability == .unavailable)
            let count = fixture.tickets.count
            let remote = await fixture.remote.counts()
            try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).contains { $0.isKeyWindow },
                "SETUP: the actual native hosting window is required")
            // The probe explicitly cannot walk SwiftUI ScrollView content.
            // First prove that this same factory/window/walker can read the
            // actual outside-scroll footer, with a real offer and callback.
            // Its layout remains covered by the separate full-frame test.
            do {
                let originalDriver = fixture.driver
                let originalOwner = fixture.owner
                let positive = NavigationStack {
                    MealRecordHistoryDestination(recordID: C11WireFixtures.recordID,
                        localRow: C11RecoveryFooterViewportLanguage.row(), context: nil,
                        owner: originalOwner, sessions: fixture.cache,
                        recoveryAvailability: .available(originalOffer), recover: {
                            _ = await originalDriver.recover(offer: originalOffer, owner: originalOwner)
                        })
                }
                .environment(\.locale, matrix.language.formattingLocale)
                .environment(\.bodyFlowReduceMotion, true)
                let control = SignUpRenderingProbe.host(positive, width: matrix.width, height: matrix.height,
                    size: .accessibility5)
                defer { control.detach() }
                _ = try recoveryFooterGeometry(control, matrix, phase: "OFF-positive-control")
                let controlNodes = control.nodes()
                let notice = try #require(controlNodes.first { $0.identifier == "meal-record.recovery.notice" && $0.isElement },
                    "SETUP: positive control could not read the real outside-scroll notice: \(controlNodes)")
                let button = try #require(controlNodes.first { $0.identifier == "meal-record.recovery.action" && $0.isElement && $0.isButton },
                    "SETUP: positive control could not read the real outside-scroll action: \(controlNodes)")
                try #require(notice.frame.width > 0 && notice.frame.height > 0 && button.frame.width > 0 && button.frame.height > 0,
                    "SETUP: positive AX control frames must be nonempty")
                #expect(notice.label == MealRecordCopy.string("meal-record.recovery.notice", language: matrix.language))
                #expect(button.label == MealRecordCopy.string("meal-record.recovery.action", language: matrix.language))
                #expect(button.isEnabled)
                #expect(button.frame.width >= BodyFlowSpacing.minimumTapTarget)
                #expect(button.frame.height >= BodyFlowSpacing.minimumTapTarget)
                control.detach()
                #expect(!control.geometry().isMounted)
            }
            let destination = NavigationStack {
                MealRecordHistoryDestination(recordID: C11WireFixtures.recordID,
                    localRow: C11RecoveryFooterViewportLanguage.row(), context: nil,
                    owner: fixture.owner, sessions: fixture.cache,
                    recoveryAvailability: availability, recover: nil)
            }
            .environment(\.locale, matrix.language.formattingLocale)
            .environment(\.bodyFlowReduceMotion, true)
            let host = SignUpRenderingProbe.host(destination, width: matrix.width, height: matrix.height,
                size: .accessibility5)
            defer { host.detach() }
            let geometry = try recoveryFooterGeometry(host, matrix, phase: "OFF")
            let scroll = try #require(host.scrollViews().max { $0.contentSize.height < $1.contentSize.height },
                "SETUP: actual legacy History scroll must be mounted; an empty replacement cannot prove absence")
            try #require(scroll.window != nil && !scroll.isHidden && scroll.alpha > 0,
                "SETUP: legacy History scroll must be attached and visible")
            try #require(scroll.bounds.width > 0 && scroll.bounds.height > 0 && scroll.contentSize.height > BodyFlowSpacing.minimumTapTarget,
                "SETUP: legacy History scroll geometry/content must be nonempty")
            let scrollFrame = UIAccessibility.convertToScreenCoordinates(scroll.bounds, in: scroll)
            let visibleIntersection = scrollFrame.intersection(geometry.frameOnScreen)
            try #require(!visibleIntersection.isNull && visibleIntersection.width > 0 && visibleIntersection.height > 0,
                "SETUP: legacy History scroll must intersect the actual host viewport")
            print("C11_FOOTER_OFF matrix=\(matrix) hostScreen=\(geometry.frameOnScreen) legacyScrollScreen=\(scrollFrame) contentSize=\(scroll.contentSize)")
            let nodes = host.nodes()
            // Absence is considered only AFTER the capable positive control
            // and the real legacy scroll mount/content have both succeeded.
            // Empty AX output by itself never establishes this result.
            #expect(!nodes.contains { $0.identifier == "meal-record.recovery.notice" })
            #expect(!nodes.contains { $0.identifier == "meal-record.recovery.action" })
            #expect(fixture.tickets.count == count)
            #expect(await fixture.remote.counts() == remote)
            #expect(await fixture.probe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    /// Fail setup rather than comparing AX frames to an assumed origin or
    /// to a root that silently grew beyond the requested logical viewport.
    private func recoveryFooterGeometry(_ host: SignUpRenderingProbe.Host,
        _ matrix: C11RecoveryFooterViewportLanguage, phase: String) throws -> SignUpRenderingProbe.Geometry {
        let geometry = host.geometry()
        print("C11_FOOTER_HOST matrix=\(matrix) phase=\(phase) requested=\(matrix.width)x\(matrix.height) \(geometry)")
        try #require(geometry.isMounted && geometry.windowBounds != nil && geometry.windowFrameOnScreen != nil,
            "SETUP: the measured host must be mounted in the real native window")
        try #require(abs(geometry.bounds.width - matrix.width) <= 0.5 && abs(geometry.bounds.height - matrix.height) <= 0.5,
            "SETUP: measured host bounds changed the requested logical viewport: \(geometry)")
        try #require(abs(geometry.frameInSuperview.width - matrix.width) <= 0.5 && abs(geometry.frameInSuperview.height - matrix.height) <= 0.5,
            "SETUP: measured host UIView frame changed the requested logical viewport: \(geometry)")
        try #require(!geometry.frameOnScreen.isNull && !geometry.frameOnScreen.isInfinite &&
            geometry.frameOnScreen.minX.isFinite && geometry.frameOnScreen.minY.isFinite &&
            abs(geometry.frameOnScreen.width - matrix.width) <= 0.5 && abs(geometry.frameOnScreen.height - matrix.height) <= 0.5,
            "SETUP: screen conversion must preserve the measured viewport size: \(geometry)")
        return geometry
    }
    @Test("C11 tutorial promise requires an admitted source and the exact active original owner, without extra work")
    func confirmedMealTutorialRequiresCurrentSourceAndOriginalOwner() async throws {
        try await withWireFixture { fixture in
            #expect(!GuidedTutorialFacts.confirmedMealEditingIsAvailable(source: fixture.dependencies.mealRecordBindingSource,
                context: nil, owner: fixture.owner))
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            #expect(GuidedTutorialFacts.confirmedMealEditingIsAvailable(source: fixture.dependencies.mealRecordBindingSource,
                context: context, owner: fixture.owner))
            #expect(!GuidedTutorialFacts.confirmedMealEditingIsAvailable(source: nil, context: context, owner: fixture.owner))
            #expect(!GuidedTutorialFacts.confirmedMealEditingIsAvailable(source: fixture.dependencies.mealRecordBindingSource,
                context: context, owner: nil))
            let other = Prompt14SessionOwner(userID: C11WireFixtures.userID,
                dependencies: fixture.dependencies, enablesMealRecordBinding: true)
            await other.awaitPatientTimeZoneResolution()
            #expect(!GuidedTutorialFacts.confirmedMealEditingIsAvailable(source: fixture.dependencies.mealRecordBindingSource,
                context: context, owner: other))
            await other.endSession()
            fixture.driver.invalidateSynchronously()
            #expect(!GuidedTutorialFacts.confirmedMealEditingIsAvailable(source: fixture.dependencies.mealRecordBindingSource,
                context: context, owner: fixture.owner))
            #expect(!fixture.owner.isInvalidated)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("Closing only the original meal scope removes the explanation from an open tour without resetting its step")
    func confirmedMealTutorialRemovesClosedScopeFromOpenTour() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            @MainActor func currentFacts() -> GuidedTutorialFacts {
                GuidedTutorialFacts(mealMedia: false, planDrafts: false, planImport: false,
                    reminders: false, realAccount: true,
                    confirmedMealEditing: GuidedTutorialFacts.confirmedMealEditingIsAvailable(
                        source: fixture.dependencies.mealRecordBindingSource, context: context, owner: fixture.owner))
            }
            let ownerKey = LocalReminderPlanner.ownerKey(for: C11WireFixtures.userID)
            let tour = GuidedTourModel(steps: GuidedTourContent.steps(facts: currentFacts()), origin: .profile,
                ownerKey: ownerKey, returnTab: .profile, isSessionActive: { !fixture.owner.isInvalidated })
            for _ in 0..<7 { tour.next() }
            #expect(tour.current.id == "trail")
            #expect(tour.current.additionalLineKey == "tutorial.history.confirmed-meal-editing")
            let originalIndex = tour.index
            let originalIDs = tour.steps.map(\.id)
            var textProgress = GuidedTutorialProgress(stepCount: GuidedTutorialContent.steps(facts: currentFacts()).count)
            textProgress.jump(to: 1)
            #expect(GuidedTutorialContent.steps(facts: currentFacts())[textProgress.index].lineKeys.contains("tutorial.history.confirmed-meal-editing"))
            fixture.driver.invalidateSynchronously()
            #expect(!context.isActive)
            #expect(!fixture.owner.isInvalidated)
            tour.updateFacts(currentFacts(), ownerKey: ownerKey)
            #expect(tour.index == originalIndex)
            #expect(tour.steps.map(\.id) == originalIDs)
            #expect(tour.steps.count == 8)
            #expect(tour.current.additionalLineKey == nil)
            let updatedText = GuidedTutorialContent.steps(facts: currentFacts())
            #expect(updatedText.count == textProgress.stepCount)
            #expect(updatedText[textProgress.index].area == .today)
            #expect(!updatedText[textProgress.index].lineKeys.contains("tutorial.history.confirmed-meal-editing"))
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

}

enum C11WireSourceCase: CaseIterable, Sendable { case disabled, demo, wrongClient, missingLifecycle, enabled }
enum C11WireOffCase: CaseIterable, Sendable { case noSource, noLifetime }

@MainActor
private func withWireFixture(sourceEnabled: Bool = true, lifetimeEnabled: Bool = true,
    _ operation: @MainActor (C11WireFixture) async throws -> Void) async throws {
    let fixture = try await C11WireFixture.make(sourceEnabled: sourceEnabled, lifetimeEnabled: lifetimeEnabled)
    do {
        try await operation(fixture)
        await fixture.end()
    } catch {
        await fixture.end()
        throw error
    }
}

@MainActor
private struct C11WireFixture {
    let transport: MobileAPITransport
    let coordinator: SessionLifecycleCoordinator
    let bindProbe: C11WireLifecycleProbe
    let remote: C11WireRemote
    let server: C11WireServer
    let dependencies: AppDependencies
    let lifetime: MealRecordAuthenticationLifetime?
    let flow: AppFlowModel
    let owners: Prompt14AuthenticatedShellCoordinator
    let owner: Prompt14SessionOwner
    let driver: MealRecordRootWiringDriver
    let cache: MealRecordShellSessionCoordinator
    let keys: C11WireKeys
    let center: FeatureInvalidationCenter

    static func make(sourceEnabled: Bool, lifetimeEnabled: Bool) async throws -> Self {
        let store = AuthenticationSessionStore(secureStore: InMemorySecureStore(), now: {
            Date(timeIntervalSince1970: 1000)
        })
        let record = try C11WireFixtures.record(ordinal: 1)
        try await store.replace(with: record)
        let remote = C11WireRemote(record: record)
        let coordinator = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let bindProbe = C11WireLifecycleProbe(base: coordinator)
        let server = C11WireServer()
        C11WireURLProtocol.install(server)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [C11WireURLProtocol.self]
        let transport = MobileAPITransport(configuration: try MobileAPIConfiguration(originString: "https://wire.example.test"),
            sessionLifecycle: coordinator, session: URLSession(configuration: config),
            clock: ContinuousClock(), timeout: .seconds(2))
        let source = AppDependencies.makeMealRecordBindingSource(enabled: sourceEnabled,
            mode: .releaseUnavailable, client: transport, lifecycle: bindProbe)
        let lifetime = lifetimeEnabled ? MealRecordAuthenticationLifetime() : nil
        let scaffold = AppDependencies.scaffold()
        let authentication = SupabaseAuthenticationService(remote: remote, lifecycle: coordinator)
        let onboarding = C11WireOnboarding()
        let keys = C11WireKeys()
        let dependencies = AppDependencies(apiClient: transport, authentication: authentication,
            onboarding: onboarding, coachPersona: scaffold.coachPersona, secureStore: scaffold.secureStore,
            telemetry: scaffold.telemetry, today: scaffold.today, history: scaffold.history, plan: scaffold.plan,
            progress: scaffold.progress, mealDetection: scaffold.mealDetection, registration: scaffold.registration,
            hydration: scaffold.hydration, weight: scaffold.weight, routine: scaffold.routine, me: scaffold.me,
            publishedContentSessions: scaffold.publishedContentSessions, coachExperienceSessions: scaffold.coachExperienceSessions,
            contentCoverSessions: scaffold.contentCoverSessions, timeProvider: C11WireTime(), idempotencyKeyProvider: keys,
            patientTimeZoneStore: scaffold.patientTimeZoneStore, flowChat: scaffold.flowChat,
            mealRecordBindingSource: source)
        let flow = AppFlowModel(authentication: authentication, onboarding: onboarding,
            persona: scaffold.coachPersona, telemetry: scaffold.telemetry,
            mealRecordAuthenticationLifetime: lifetime, now: { C11WireFixtures.date })
        let owners = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies,
            enablesMealRecordBinding: lifetime != nil && source != nil)
        let driver = MealRecordRootWiringDriver(model: flow, ownerCoordinator: owners,
            lifetime: lifetime, source: source)
        let center = FeatureInvalidationCenter()
        let cache = MealRecordShellSessionCoordinator(time: C11WireTime(), keys: keys, invalidation: center)
        do {
            await flow.start()
            try #require(flow.state == .authenticated(userID: C11WireFixtures.userID))
            await owners.transition(to: C11WireFixtures.userID)
            let owner = try #require(owners.renderableOwner(for: C11WireFixtures.userID))
            await owner.awaitPatientTimeZoneResolution()
            return Self(transport: transport, coordinator: coordinator, bindProbe: bindProbe,
                remote: remote, server: server, dependencies: dependencies, lifetime: lifetime, flow: flow,
                owners: owners, owner: owner, driver: driver, cache: cache, keys: keys, center: center)
        } catch {
            cache.endSession()
            await driver.endSession()
            await lifetime?.endSession()
            await owners.transition(to: nil)
            throw error
        }
    }

    func end() async {
        cache.endSession()
        await driver.endSession()
        await lifetime?.endSession()
        await owners.transition(to: nil)
    }
}

private enum C11WireFixtures {
    static let userID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let recordID = "11111111-1111-4111-8111-111111111111"
    static let replacementID = "33333333-3333-4333-8333-333333333333"
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "c11-wire-synthetic")
    static func record(ordinal: Int) throws -> AuthenticationSessionRecord {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "marker": ordinal])
        func part(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let syntheticToken = "\(part(header)).\(part(payload)).synthetic-signature"
        return AuthenticationSessionRecord(userID: userID, email: "wire@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: syntheticToken, refreshToken: "wire-synthetic-refresh-\(ordinal)",
            expiresAt: Date(timeIntervalSince1970: 2000))
    }
    static func detail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(id: recordID, foodName: "Synthetic wire item", quantityG: 50,
            kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: nil)
        return MealRecordResponse(data: MealRecordSnapshot(recordID: recordID, scope: .group,
            expectedVersion: "opaque-wire-version", itemIDs: [recordID], items: [item], editable: true,
            dayClosed: false, localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil), meta: meta)
    }
    static func receipt() -> MealRecordMutationResponse {
        MealRecordMutationResponse(data: MealRecordMutationSnapshot(recordID: recordID, operation: .updated,
            newItemIDs: [replacementID], removedItemIDs: [recordID], nextRecordID: replacementID,
            snapshot: MealRecordPersistedSnapshot(id: "synthetic-wire-snapshot", date: "2026-10-13",
                caloriesConsumed: 321, proteinG: 3, carbsG: 4, fatG: 5, dailyBalance: 77)), meta: meta)
    }
}

private struct C11WireTime: TimeProviding { var now: Date { C11WireFixtures.date } }
private final class C11WireKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    var count: Int { lock.withLock { issued } }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock {
            issued += 1
            return try IdempotencyKey(validating: "c11-wire-synthetic-key-\(issued)")
        }
    }
}
private final class C11WireObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var didChange: Bool { lock.withLock { changed } }
    func markChanged() { lock.withLock { changed = true } }
}

private actor C11WireRemote: SupabaseAuthRemoteOperating {
    private var signInRecord: AuthenticationSessionRecord
    init(record: AuthenticationSessionRecord) { signInRecord = record }
    func setSignInRecord(_ value: AuthenticationSessionRecord) { signInRecord = value }
    func signIn(email: String, password: String) -> AuthenticationSessionRecord { signInRecord }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult { throw SupabaseAuthRemoteError.requestFailed }
    func requestPasswordRecovery(email: String) {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord { try C11WireFixtures.record(ordinal: 10) }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}
private actor C11WireOnboarding: OnboardingRepository {
    func loadDraft(for userID: String) -> OnboardingDraft? { nil }
    func loadState(for userID: String) -> OnboardingServerState {
        OnboardingServerState(locale: "pt-BR", completion: OnboardingCompletionState(completed: true,
            completedAt: "2026-10-13T00:00:00.000Z"), requirements: .unavailable, acceptedActions: [], draft: nil)
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) {}
    func complete(_ draft: OnboardingDraft, for userID: String) {}
    func clear(for userID: String) {}
}

/// Counts only Source.bind lease capture. Transport uses the SAME real base directly.
/// All validation/registry/visible-state operations delegate without changing authority.
private actor C11WireLifecycleProbe: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    private(set) var bindLeaseCalls = 0
    init(base: SessionLifecycleCoordinator) { self.base = base }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        bindLeaseCalls += 1
        return try await base.leaseForRequest()
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

private actor C11WireServer {
    private(set) var requestCount = 0
    private var loseMutation = false
    private var scriptedBodies: [String: [Data]] = [:]
    private(set) var commandKeys: [String] = []
    func stageBody(_ data: Data, for method: String) { scriptedBodies[method, default: []].append(data) }
    func loseNextMutationResponse() { loseMutation = true }
    func respond(to request: URLRequest) throws -> Data {
        requestCount += 1
        if let key = request.value(forHTTPHeaderField: "Idempotency-Key") { commandKeys.append(key) }
        let method = request.httpMethod ?? ""
        if var queued = scriptedBodies[method], !queued.isEmpty {
            let data = queued.removeFirst()
            scriptedBodies[method] = queued
            return data
        }
        switch request.httpMethod {
        case "GET": return try JSONEncoder().encode(C11WireFixtures.detail())
        case "PATCH":
            if loseMutation {
                loseMutation = false
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            }
            return try JSONEncoder().encode(C11WireFixtures.receipt())
        default: throw MobileAPITransportError.invalidResponse
        }
    }
}

// URLProtocol itself is not transferred into an async closure. Only the narrow
// immutable-handle loading context below crosses that boundary.
private final class C11WireURLProtocol: URLProtocol {
    private static let registry = C11WireProtocolRegistry()
    private let lock = NSLock()
    private var loadingContext: C11WireLoadingContext?
    private var stopped = false

    static func install(_ server: C11WireServer) { registry.install(server) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "wire.example.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let context = C11WireLoadingContext(protocolInstance: self, request: request,
            server: Self.registry.current, client: client)
        let admission: (accepted: Bool, cancelImmediately: Bool) = lock.withLock {
            guard loadingContext == nil else { return (false, false) }
            loadingContext = context
            return (true, stopped)
        }
        guard admission.accepted else { return }
        if admission.cancelImmediately { context.cancel() }
        context.start()
    }

    override func stopLoading() {
        let current = lock.withLock {
            stopped = true
            return loadingContext
        }
        current?.cancel()
    }

    fileprivate func release(_ context: C11WireLoadingContext) {
        lock.withLock {
            if loadingContext === context { loadingContext = nil }
        }
    }
}

/// The known loading-context pattern, with one immutable request/server/client
/// and serialized terminal delivery. No mutable URLProtocol properties are read
/// by the task. Its own start/cancel/finish state is protected by this lock.
private final class C11WireLoadingContext: @unchecked Sendable {
    private let protocolInstance: C11WireURLProtocol
    private let request: URLRequest
    private let server: C11WireServer?
    private let client: (any URLProtocolClient)?
    // Client delivery may synchronously call stopLoading: allow that reentry.
    private let lock = NSRecursiveLock()
    private var started = false
    private var cancelled = false
    private var terminalDelivered = false
    private var finished = false
    private var task: Task<Void, Never>?

    init(protocolInstance: C11WireURLProtocol, request: URLRequest,
         server: C11WireServer?, client: (any URLProtocolClient)?) {
        self.protocolInstance = protocolInstance
        self.request = request
        self.server = server
        self.client = client
    }

    func start() {
        let admitted = lock.withLock {
            guard !started, !cancelled, !finished else { return false }
            started = true
            return true
        }
        guard admitted else {
            finish()
            return
        }
        // The sendable context is the sole async capture; not the URLProtocol.
        let work = Task { await run() }
        let cancelNow = lock.withLock {
            guard !cancelled, !finished else { return true }
            task = work
            return false
        }
        if cancelNow { work.cancel() }
    }

    func cancel() {
        let pending = lock.withLock {
            cancelled = true
            return task
        }
        pending?.cancel()
    }

    private func run() async {
        defer { finish() }
        do {
            try Task.checkCancellation()
            guard !isCancelled, let server else {
                if isCancelled { return }
                throw MobileAPITransportError.invalidResponse
            }
            let data = try await server.respond(to: request)
            try Task.checkCancellation()
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]) else {
                throw MobileAPITransportError.invalidResponse
            }
            deliver(response: response, data: data)
        } catch is CancellationError {
            // URLSession already owns cancellation; no callback after stopLoading.
        } catch {
            deliver(error: error)
        }
    }

    private func deliver(response: HTTPURLResponse, data: Data) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
            guard !cancelled else { return }
            client.urlProtocol(protocolInstance, didLoad: data)
            guard !cancelled else { return }
            terminalDelivered = true
            client.urlProtocolDidFinishLoading(protocolInstance)
        }
    }

    private func deliver(error: any Error) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            terminalDelivered = true
            client.urlProtocol(protocolInstance, didFailWithError: error)
        }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private func finish() {
        lock.withLock {
            finished = true
            task = nil
        }
        // Break URLProtocol -> context -> URLProtocol after the task returns.
        protocolInstance.release(self)
    }
}

private final class C11WireProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var server: C11WireServer?
    var current: C11WireServer? { lock.withLock { server } }
    func install(_ value: C11WireServer) { lock.withLock { server = value } }
}

// H05 test parameters remain internal for Swift Testing's argument access.
enum C11RecoveryRejectedAdmission: CaseIterable, Sendable {
    case sourceOff, lifetimeNil, lifetimeWithoutOriginalAnchor, ownerOff, wrongUser, foreignSameUser, closedOwner
}
enum C11RecoveryAuthEntry: CaseIterable, Sendable {
    case start, signIn, signUp, confirmDevelopment, signOut, passwordRecovery
    @MainActor static func perform(_ entry: Self, on flow: AppFlowModel) async {
        switch entry {
        case .start: await flow.start()
        case .signIn: await flow.signIn(email: "wire@example.invalid", password: "synthetic-password-only")
        case .signUp: await flow.signUp(email: "wire@example.invalid", password: "synthetic-password-only")
        case .confirmDevelopment: await flow.confirmEmailForDevelopment()
        case .signOut: await flow.signOut()
        case .passwordRecovery: await flow.requestPasswordRecovery(email: "wire@example.invalid")
        }
    }
}
enum C11RecoveryRetainedCallback: CaseIterable, Sendable { case sameUser, aba, snapshotMismatch }
enum C11RecoveryCancellation: CaseIterable, Sendable { case beforeAdmission, duringLease }
enum C11RecoveryBindingOutcome: CaseIterable, Sendable { case success, realMissingSession }
enum C11RecoveryReceiptOperation: CaseIterable, Sendable { case patch, delete }

/// A checkpoint races "entered" with completion of the tested action so an
/// intentionally inert API baseline cannot leave a test waiting forever.
private actor C11RecoveryCheckpoint {
    private var entered = false
    private var completed = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Bool, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    func enterAndWait() async {
        entered = true
        let waiters = entryWaiters; entryWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: true) }
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }
    func noteCompletion() {
        completed = true
        guard !entered else { return }
        let waiters = entryWaiters; entryWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: false) }
    }
    func waitUntilEnteredOrCompleted() async -> Bool {
        if entered { return true }
        if completed || released { return false }
        return await withCheckedContinuation { entryWaiters.append($0) }
    }
    func release() {
        released = true
        let exits = releaseWaiters; releaseWaiters.removeAll()
        for exit in exits { exit.resume() }
        if !entered {
            let starts = entryWaiters; entryWaiters.removeAll()
            for start in starts { start.resume(returning: false) }
        }
    }
}

private actor C11RecoveryMarkerStore: SecureStoring {
    private var values: [String: Data] = [:]
    private var rejectsMarker = false
    func data(forKey key: String) -> Data? { values[key] }
    func store(_ data: Data, forKey key: String) throws {
        if key == AuthenticationSessionStore.invalidationMarkerKey, rejectsMarker {
            throw AuthenticationSessionStoreError.localInvalidationFailed
        }
        values[key] = data
    }
    func removeData(forKey key: String) { values[key] = nil }
    func rejectMarker(_ value: Bool = true) { rejectsMarker = value }
}

@MainActor
private final class C11RecoveryTicketSpy {
    private(set) var count = 0
    private(set) var issued: [MealRecordAuthenticationTicket] = []
    func next() -> MealRecordAuthenticationTicket {
        count += 1
        let ticket = MealRecordAuthenticationTicket()
        issued.append(ticket)
        return ticket
    }
}

private enum C11RecoveryRecords {
    static let userB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static func record(userID: String = C11WireFixtures.userID, ordinal: Int,
                       email: String = "wire@example.invalid") throws -> AuthenticationSessionRecord {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "marker": ordinal])
        func encoded(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let synthetic = "\(encoded(header)).\(encoded(payload)).synthetic"
        return AuthenticationSessionRecord(userID: userID, email: email, isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: synthetic, refreshToken: "wire-recovery-synthetic-\(ordinal)",
            expiresAt: Date(timeIntervalSince1970: 2000))
    }
}

private actor C11RecoveryRemote: SupabaseAuthRemoteOperating {
    private var signInRecord: AuthenticationSessionRecord
    private var counters = [0, 0, 0, 0, 0]
    init(record: AuthenticationSessionRecord) { signInRecord = record }
    func setSignInRecord(_ record: AuthenticationSessionRecord) { signInRecord = record }
    func counts() -> [Int] { counters }
    func signIn(email: String, password: String) -> AuthenticationSessionRecord { counters[0] += 1; return signInRecord }
    func signUp(email: String, password: String) -> SupabaseRemoteSignUpResult { counters[1] += 1; return .authenticated(signInRecord) }
    func requestPasswordRecovery(email: String) { counters[2] += 1 }
    func refresh(record: AuthenticationSessionRecord) -> AuthenticationSessionRecord { counters[3] += 1; return record }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { counters[4] += 1; return .confirmed }
}

/// Holds only around calls to the real SupabaseAuthenticationService. There is
/// no fake public session, state setter or authority implemented by this peer.
private actor C11RecoveryAuthentication: AuthenticationService {
    private let base: SupabaseAuthenticationService
    private var entryHolds: [(C11RecoveryAuthEntry, C11RecoveryCheckpoint)] = []
    private var capturedRestoreHold: C11RecoveryCheckpoint?
    private var allHolds: [C11RecoveryCheckpoint] = []
    init(base: SupabaseAuthenticationService) { self.base = base }
    func hold(_ entry: C11RecoveryAuthEntry, using checkpoint: C11RecoveryCheckpoint) {
        entryHolds.append((entry, checkpoint)); allHolds.append(checkpoint)
    }
    func holdNextCapturedRestore(using checkpoint: C11RecoveryCheckpoint) {
        capturedRestoreHold = checkpoint; allHolds.append(checkpoint)
    }
    func releaseAll() async { for checkpoint in allHolds { await checkpoint.release() } }
    private func enter(_ entry: C11RecoveryAuthEntry) async {
        guard let index = entryHolds.firstIndex(where: { $0.0 == entry }) else { return }
        let held = entryHolds.remove(at: index).1
        await held.enterAndWait()
    }
    func restoreSession() async throws -> AuthSession? {
        await enter(.start)
        let session = try await base.restoreSession()
        if let held = capturedRestoreHold {
            capturedRestoreHold = nil
            await held.enterAndWait()
        }
        return session
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        await enter(.signIn); return try await base.signIn(email: email, password: password)
    }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        await enter(.signUp); return try await base.signUp(email: email, password: password)
    }
    func confirmEmailForDevelopment() async throws -> AuthSession {
        await enter(.confirmDevelopment); return try await base.confirmEmailForDevelopment()
    }
    func requestPasswordRecovery(email: String) async throws {
        await enter(.passwordRecovery); try await base.requestPasswordRecovery(email: email)
    }
    func signOut() async throws { await enter(.signOut); try await base.signOut() }
}

/// The transport uses this actual delegate. Its U9 hold is AFTER the real
/// PatientWorkRegistry finish and BEFORE transport validation/decode/publication.
private actor C11RecoveryTransportBoundary: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    private var nextFinishedHold: C11RecoveryCheckpoint?
    private var allHolds: [C11RecoveryCheckpoint] = []
    init(base: SessionLifecycleCoordinator) { self.base = base }
    func holdNextFinishedPatientWork(using checkpoint: C11RecoveryCheckpoint) {
        nextFinishedHold = checkpoint; allHolds.append(checkpoint)
    }
    func releaseAll() async { for checkpoint in allHolds { await checkpoint.release() } }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease { try await base.leaseForRequest() }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await base.refreshAfterUnauthorized(lease: lease) }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async {
        let held = nextFinishedHold; nextFinishedHold = nil
        await base.finishPatientWork(id)
        await held?.enterAndWait()
    }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

/// Only Source.bind lease captures are counted/held. Every authority operation
/// delegates to the same transport boundary and real coordinator/store.
private actor C11RecoverySourceProbe: SessionLifecycleProviding {
    private let base: C11RecoveryTransportBoundary
    private var nextLeaseHold: C11RecoveryCheckpoint?
    private var allHolds: [C11RecoveryCheckpoint] = []
    private(set) var bindLeaseCalls = 0
    init(base: C11RecoveryTransportBoundary) { self.base = base }
    func holdNextLease(using checkpoint: C11RecoveryCheckpoint) {
        nextLeaseHold = checkpoint; allHolds.append(checkpoint)
    }
    func releaseAll() async { for checkpoint in allHolds { await checkpoint.release() } }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        bindLeaseCalls += 1
        let held = nextLeaseHold; nextLeaseHold = nil
        await held?.enterAndWait()
        return try await base.leaseForRequest()
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await base.refreshAfterUnauthorized(lease: lease) }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

@MainActor
private struct C11RecoveryPublicSnapshot: Equatable {
    let state: AppFlowState
    let session: AuthSession?
    let error: AppPresentationError?
    let auth: AuthOperationState
    let onboardingDraft: OnboardingDraft?
    let onboardingGeneration: Int
    init(_ flow: AppFlowModel) {
        state = flow.state; session = flow.currentSession; error = flow.presentationError
        auth = flow.authOperationState; onboardingDraft = flow.restoredOnboardingDraft
        onboardingGeneration = flow.onboardingRestoreGeneration
    }
}

@MainActor
private func withRecoveryFixture(_ operation: @MainActor (C11RecoveryFixture) async throws -> Void) async throws {
    let fixture = try await C11RecoveryFixture.make()
    do { try await operation(fixture); await fixture.end() }
    catch { await fixture.end(); throw error }
}

@MainActor
private final class C11RecoveryFixture {
    let secure: C11RecoveryMarkerStore
    let remote: C11RecoveryRemote
    let coordinator: SessionLifecycleCoordinator
    let boundaries: C11RecoveryTransportBoundary
    let probe: C11RecoverySourceProbe
    let authentication: C11RecoveryAuthentication
    let source: MealRecordSessionBindingSource
    let server: C11WireServer
    let dependencies: AppDependencies
    let lifetime: MealRecordAuthenticationLifetime
    let tickets: C11RecoveryTicketSpy
    let flow: AppFlowModel
    let telemetry: InMemoryTelemetryClient
    let owners: Prompt14AuthenticatedShellCoordinator
    let owner: Prompt14SessionOwner
    let driver: MealRecordRootWiringDriver
    let cache: MealRecordShellSessionCoordinator
    let keys: C11WireKeys
    let center: FeatureInvalidationCenter
    let originalContext: MealRecordReadyContext
    private var releases: [@MainActor () async -> Void] = []
    private var joins: [@MainActor () async -> Void] = []
    private var ended = false

    init(secure: C11RecoveryMarkerStore, remote: C11RecoveryRemote, coordinator: SessionLifecycleCoordinator,
         boundaries: C11RecoveryTransportBoundary, probe: C11RecoverySourceProbe,
         authentication: C11RecoveryAuthentication, source: MealRecordSessionBindingSource, server: C11WireServer,
         dependencies: AppDependencies, lifetime: MealRecordAuthenticationLifetime, tickets: C11RecoveryTicketSpy,
         flow: AppFlowModel, telemetry: InMemoryTelemetryClient, owners: Prompt14AuthenticatedShellCoordinator,
         owner: Prompt14SessionOwner, driver: MealRecordRootWiringDriver, cache: MealRecordShellSessionCoordinator,
         keys: C11WireKeys, center: FeatureInvalidationCenter, originalContext: MealRecordReadyContext) {
        self.secure = secure; self.remote = remote; self.coordinator = coordinator; self.boundaries = boundaries
        self.probe = probe; self.authentication = authentication; self.source = source; self.server = server
        self.dependencies = dependencies; self.lifetime = lifetime; self.tickets = tickets; self.flow = flow
        self.telemetry = telemetry; self.owners = owners; self.owner = owner; self.driver = driver
        self.cache = cache; self.keys = keys; self.center = center; self.originalContext = originalContext
    }

    static func make() async throws -> C11RecoveryFixture {
        let secure = C11RecoveryMarkerStore()
        let store = AuthenticationSessionStore(secureStore: secure, now: { Date(timeIntervalSince1970: 1000) })
        let record = try C11RecoveryRecords.record(ordinal: 1)
        try await store.replace(with: record)
        let remote = C11RecoveryRemote(record: record)
        let coordinator = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let boundaries = C11RecoveryTransportBoundary(base: coordinator)
        let probe = C11RecoverySourceProbe(base: boundaries)
        let server = C11WireServer()
        C11WireURLProtocol.install(server)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [C11WireURLProtocol.self]
        let transport = MobileAPITransport(configuration: try MobileAPIConfiguration(originString: "https://wire.example.test"),
            sessionLifecycle: boundaries, session: URLSession(configuration: config),
            clock: ContinuousClock(), timeout: .seconds(2))
        let source = MealRecordSessionBindingSource(transport: transport, lifecycle: probe)
        let authentication = C11RecoveryAuthentication(base: SupabaseAuthenticationService(remote: remote, lifecycle: coordinator))
        let scaffold = AppDependencies.scaffold()
        let keys = C11WireKeys()
        let telemetry = InMemoryTelemetryClient()
        let dependencies = AppDependencies(apiClient: transport, authentication: authentication,
            onboarding: C11WireOnboarding(), coachPersona: scaffold.coachPersona, secureStore: secure,
            telemetry: telemetry, today: scaffold.today, history: scaffold.history, plan: scaffold.plan,
            progress: scaffold.progress, mealDetection: scaffold.mealDetection, registration: scaffold.registration,
            hydration: scaffold.hydration, weight: scaffold.weight, routine: scaffold.routine, me: scaffold.me,
            publishedContentSessions: scaffold.publishedContentSessions, coachExperienceSessions: scaffold.coachExperienceSessions,
            contentCoverSessions: scaffold.contentCoverSessions, timeProvider: C11WireTime(), idempotencyKeyProvider: keys,
            patientTimeZoneStore: scaffold.patientTimeZoneStore, flowChat: scaffold.flowChat, mealRecordBindingSource: source)
        let tickets = C11RecoveryTicketSpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let flow = AppFlowModel(authentication: authentication, onboarding: dependencies.onboarding,
            persona: scaffold.coachPersona, telemetry: telemetry, mealRecordAuthenticationLifetime: lifetime,
            developmentConsentAvailability: .syntheticDevelopment, now: { C11WireFixtures.date })
        let owners = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies, enablesMealRecordBinding: true)
        let driver = MealRecordRootWiringDriver(model: flow, ownerCoordinator: owners, lifetime: lifetime, source: source)
        let center = FeatureInvalidationCenter()
        let cache = MealRecordShellSessionCoordinator(time: C11WireTime(), keys: keys, invalidation: center)
        do {
            await flow.start()
            try #require(flow.state == .authenticated(userID: C11WireFixtures.userID))
            await owners.transition(to: C11WireFixtures.userID)
            let owner = try #require(owners.renderableOwner(for: C11WireFixtures.userID))
            await owner.awaitPatientTimeZoneResolution()
            let context = try #require(await driver.synchronize(expected: driver.taskID))
            return C11RecoveryFixture(secure: secure, remote: remote, coordinator: coordinator,
                boundaries: boundaries, probe: probe, authentication: authentication, source: source,
                server: server, dependencies: dependencies, lifetime: lifetime, tickets: tickets, flow: flow,
                telemetry: telemetry, owners: owners, owner: owner, driver: driver, cache: cache,
                keys: keys, center: center, originalContext: context)
        } catch {
            await probe.releaseAll(); await boundaries.releaseAll(); await authentication.releaseAll()
            cache.endSession(); await driver.endSession(); await lifetime.endSession(); await owners.transition(to: nil)
            throw error
        }
    }

    func failLogout() async throws -> MealRecordRecoveryOffer {
        await secure.rejectMarker()
        await flow.signOut()
        #expect(flow.presentationError == .storageUnavailable)
        #expect(flow.state == .authenticated(userID: C11WireFixtures.userID))
        return try #require(flow.availableMealRecordRecoveryOffer)
    }
    func addCleanup(_ release: @escaping @MainActor () async -> Void) { releases.append(release) }
    func retain<Value: Sendable>(_ task: Task<Value, Never>) {
        joins.append { task.cancel(); _ = await task.value }
    }
    func recovering(offer: MealRecordRecoveryOffer, checkpoint: C11RecoveryCheckpoint) -> Task<MealRecordReadyContext?, Never> {
        let originalDriver = driver
        let originalOwner = owner
        let work = Task {
            let context = await originalDriver.recover(offer: offer, owner: originalOwner)
            await checkpoint.noteCompletion()
            return context
        }
        retain(work)
        return work
    }
    func end() async {
        guard !ended else { return }
        ended = true
        // Always release ALL boundaries before joining even when #require throws.
        await probe.releaseAll(); await boundaries.releaseAll(); await authentication.releaseAll()
        for release in releases { await release() }; releases.removeAll()
        for join in joins { await join() }; joins.removeAll()
        cache.endSession()
        await driver.endSession(); await lifetime.endSession(); await owners.transition(to: nil)
    }
}

// Internal parameter visibility is required by Swift Testing.
enum C11RecoveryOldPresentationCompletion: CaseIterable, Sendable { case normal, cancelled }

// Internal visibility is needed for Swift Testing parameter arguments.
enum C11RecoveryFooterRenderingState: CaseIterable, Sendable { case available, processing }
enum C11RecoveryFooterViewportLanguage: CaseIterable, Sendable {
    case compactPortuguese, compactEnglish, landscapePortuguese, landscapeEnglish
    var language: SupportedAppLanguage {
        switch self {
        case .compactPortuguese, .landscapePortuguese: .portugueseBrazil
        case .compactEnglish, .landscapeEnglish: .englishUnitedStates
        }
    }
    var width: CGFloat {
        switch self {
        case .compactPortuguese, .compactEnglish: 320
        case .landscapePortuguese, .landscapeEnglish: 667
        }
    }
    var height: CGFloat {
        switch self {
        case .compactPortuguese, .compactEnglish: 568
        case .landscapePortuguese, .landscapeEnglish: 375
        }
    }
    static func row() -> HistoryMealLogRow {
        HistoryMealLogRow(id: C11WireFixtures.recordID, mealType: nil, foodName: "Synthetic footer meal",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3,
            consumedAt: APITimestamp(value: C11WireFixtures.date))
    }
}
