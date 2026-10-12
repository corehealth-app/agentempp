#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Signup body-photo DEBUG state fixtures")
struct SignupBodyPhotoPreviewTests {
    @Test("Every flag resolves only the fresh DEBUG photo scenario",
          arguments: SignupBodyPhotoPreviewScenario.allCases)
    func resolvesFreshPhotoScenario(_ scenario: SignupBodyPhotoPreviewScenario) {
        for arguments in [[scenario.launchArgument], ["--ui-testing", scenario.launchArgument]] {
            let configuration = AppLaunchConfiguration.resolve(arguments: arguments, buildFlavor: .debug)
            #expect(configuration.mode == .demo)
            #expect(configuration.signupBodyPhotoScenario == scenario)
            #expect(configuration.shouldResetDemoState == true)
            #expect(configuration.startsWithCompletedFixture == false)
            #expect(configuration.preloadsSyntheticOnboardingValues == false)
            #expect(configuration.usesOnboardingDeviceDraftFixture == false)
        }
    }

    @Test("Existing generic launch behavior stays intact without photo flag")
    func oldLaunchBehaviorIsPreserved() {
        let generic = AppLaunchConfiguration.resolve(arguments: ["--ui-testing"], buildFlavor: .debug)
        #expect(generic.signupBodyPhotoScenario == nil)
        #expect(generic.startsWithCompletedFixture == true)
        let fresh = AppLaunchConfiguration.resolve(arguments: ["--ui-testing-fresh-auth"], buildFlavor: .debug)
        #expect(fresh.signupBodyPhotoScenario == nil)
        #expect(fresh.startsWithCompletedFixture == false)
    }

    @Test("A non-demo configuration cannot retain the photo scenario")
    func nonDemoStripsPhotoScenario() {
        let configuration = AppLaunchConfiguration(
            mode: .releaseUnavailable, shouldResetDemoState: false,
            startsWithCompletedFixture: false, preloadsSyntheticOnboardingValues: false,
            authBehavior: .fail(.serviceUnavailable, after: nil), signupBodyPhotoScenario: .read
        )
        #expect(configuration.signupBodyPhotoScenario == nil)
    }

    @Test("Known18/24/30 exposes aggregate24 with no individual/public-private fields")
    func aggregateWireMatchesCurrentV1() async throws {
        let state = try await provider(.read).state()
        #expect(state.poses.map(\.pose) == [.front, .side, .back])
        #expect(state.poses.allSatisfy { $0.photo?.status == "read" })
        #expect(state.estimate?.bySex.masculine.bodyFatPercent == Decimal(24))
        #expect(state.estimate?.bySex.feminine.bodyFatPercent == Decimal(24))
        #expect(state.estimate?.sourceIDs != nil)
        #expect(state.estimate?.fingerprint?.count == 64)
        let data = try JSONEncoder().encode(state)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let slots = try #require(object["poses"] as? [[String: Any]])
        for slot in slots {
            let photo = try #require(slot["photo"] as? [String: Any])
            #expect(Set(photo.keys) == Set(["id", "status", "created_at"]))
        }
        let wire = try #require(String(data: data, encoding: .utf8))
        for field in ["readings", "processing_result", "notes", "bf_confidence", "object_path",
                      "signup_origin", "signup_disposition_version", "signup_disposition_assigned"] {
            #expect(!wire.contains(field))
        }
    }

    @Test("Unreadable and out-of-range keep their actual v1 distinction")
    func failureStatesAreDistinct() async throws {
        let unreadable = try await provider(.unreadable).state()
        #expect(unreadable.poses.last?.photo?.status == "unreadable")
        #expect(unreadable.estimate == nil)
        let outside = try await provider(.outOfRange).state()
        #expect(outside.poses.allSatisfy { $0.photo?.status == "read" })
        #expect(outside.estimate?.bySex.masculine.usable == false)
        #expect(outside.estimate?.bySex.masculine.bodyFatPercent == nil)
        #expect(outside.estimate?.bySex.masculine.reason == "out_of_range")
        #expect(outside.estimate?.sourceIDs == nil)
        #expect(outside.estimate?.fingerprint == nil)
    }

    @Test("Offline/unavailable/limit/minor are explicit state fixtures")
    func remainingScenariosAreExplicit() async throws {
        await #expect(throws: SignupBodyPhotoFailure.offline) { try await provider(.offline).state() }
        let unavailable = try await provider(.unavailable).state()
        #expect(unavailable.available == false)
        #expect(unavailable.unavailableReason == "disabled")
        #expect(unavailable.poses.count == 3 && unavailable.poses.allSatisfy { $0.photo == nil })
        #expect(unavailable.consent == nil && unavailable.estimate == nil)
        let limited = try await provider(.limit).state()
        #expect(limited.available && limited.remainingUploads == 0)
        let minor = try await provider(.minor).state()
        #expect(minor.minimumAge == 18 && minor.consent?.acceptedAt == nil)
        #expect(minor.estimate == nil)
    }

    @Test("Release or non-demo cannot use the state provider")
    func providerRequiresDebugDemo() async {
        for value in [
            SignupBodyPhotoPreviewProvider(scenario: .read, mode: .demo, buildFlavor: .release),
            SignupBodyPhotoPreviewProvider(scenario: .read, mode: .releaseUnavailable, buildFlavor: .debug),
        ] {
            await #expect(throws: SignupBodyPhotoFailure.unavailable) { try await value.state() }
        }
    }

    @Test("Whole-scope delete stays unavailable until B7 capability exists")
    func partialProviderDoesNotClaimDeletion() async throws {
        let command = MutationAttempt(operation: .mediaDelete,
            key: try IdempotencyKey(validating: "synthetic-delete-key"),
            payload: SignupBodyPhotoDeleteCommand(), createdAt: Date(timeIntervalSince1970: 0))
        await #expect(throws: SignupBodyPhotoFailure.unavailable) {
            try await provider(.read).delete(command)
        }
    }

    private func provider(_ scenario: SignupBodyPhotoPreviewScenario) -> SignupBodyPhotoPreviewProvider {
        SignupBodyPhotoPreviewProvider(scenario: scenario, mode: .demo, buildFlavor: .debug)
    }
}
#endif
