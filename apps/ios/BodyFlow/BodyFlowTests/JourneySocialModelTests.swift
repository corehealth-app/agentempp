import Foundation
import Security
import Testing

@testable import BodyFlow

@MainActor @Suite("Journey privacy UI uses the protected original-session commands")
struct JourneySocialModelTests {
  @Test func openingAnAbsentProfileNeverCreatesParticipation() async throws {
    let h = try JourneySocialUIHarness(participating: false)
    await h.model.load()
    #expect(h.model.phase == .ready && h.model.profile?.revision == 0)
    #expect(h.model.rankings.isEmpty && h.model.blocked.isEmpty && h.model.pending == nil)
    #expect(await h.provider.submitted().isEmpty)
    #expect(await h.provider.rankingReads == 0)
    #expect(await h.provider.recoveryReads == 0)
  }

  @Test func participationRequiresExplicitConsentAndWithdrawalClearsAudience() async throws {
    let h = try JourneySocialUIHarness(participating: false)
    await h.model.load()
    await h.model.saveParticipation(nickname: "Caminhante", accepted: false)
    #expect(await h.provider.submitted().isEmpty)
    #expect(h.model.issue == .invalidInput)
    await h.model.saveParticipation(nickname: "Caminhante", accepted: true)
    #expect(h.model.profile?.optedIn == true && h.model.profile?.revision == 1)
    #expect(h.model.rankings.map(\.rank) == [1, 1])
    let first = try #require(await h.provider.submitted().first)
    #expect(first.expectedRevision == 0)
    #expect(
      first.action == .participation(nickname: "Caminhante", consentVersion: "journey-social.v1"))
    await h.model.withdraw()
    #expect(h.model.profile?.optedIn == false && h.model.profile?.revision == 2)
    #expect(h.model.rankings.isEmpty && h.model.rankingPage == nil)
    let commands = await h.provider.submitted()
    #expect(commands.count == 2 && commands[0].id != commands[1].id)
    #expect(commands[1].expectedRevision == 1)
    #expect(commands[1].action == .participation(nickname: nil, consentVersion: nil))
  }

  @Test func lostReplyRequiresExplicitResolutionAndPreservesCurrentWithdrawal() async throws {
    let h = try JourneySocialUIHarness(participating: false)
    await h.model.load()
    await h.provider.loseNextReply()
    await h.model.saveParticipation(nickname: "Caminhante", accepted: true)
    #expect(h.model.phase == .failed && h.model.pending != nil)
    #expect(h.model.rankings.isEmpty)
    #expect(await h.provider.submitted().count == 1)
    #expect(await h.provider.recoveryReads == 0)
    await h.model.saveParticipation(nickname: "Outra intenção", accepted: true)
    #expect(await h.provider.submitted().count == 1)
    try await h.provider.replaceProfile(participating: false, revision: 2)
    await h.model.resolvePending()
    #expect(h.model.pending == nil && h.model.profile?.optedIn == false)
    #expect(h.model.profile?.revision == 2 && h.model.outcome == .recovered)
    #expect(h.model.rankings.isEmpty && h.model.phase == .ready)
    #expect(await h.provider.submitted().count == 1)
    #expect(await h.provider.recoveryReads == 1)
  }

  @Test func newLoginCanResolveAFenceButCannotSilentlyResubmitOldConsent() async throws {
    let h = try JourneySocialUIHarness(participating: false)
    let old = try pendingSocial()
    try await h.store.claim(old)
    await h.provider.useFence()
    await h.model.load()
    #expect(h.model.pending == old && h.model.phase == .ready)
    #expect(await h.provider.submitted().isEmpty)
    #expect(await h.provider.recoveryReads == 0)
    await h.model.resolvePending()
    #expect(h.model.pending == nil && h.model.outcome == .cancelledBeforeApply)
    #expect(h.model.profile?.optedIn == false)
    #expect(await h.provider.submitted().isEmpty)
  }

  @Test func paginationPreservesOfficialSharedRanksWithoutAnotherWrite() async throws {
    let h = try JourneySocialUIHarness()
    await h.model.load()
    await h.model.loadMoreRanking()
    #expect(h.model.rankings.map(\.rank) == [1, 1, 3])
    #expect(h.model.rankings.map(\.weeklyXP) == [100, 100, 90])
    #expect(h.model.rankingPage?.weekStart == "2026-11-16")
    #expect(h.model.rankingPage?.nextCursor == nil)
    #expect(await h.provider.submitted().isEmpty)
    #expect(await h.provider.rankingReads == 2)
  }

  @Test func failedPageDiscardsPreviouslyVisibleAudience() async throws {
    let h = try JourneySocialUIHarness()
    await h.model.load()
    #expect(h.model.rankings.count == 2)
    await h.provider.failRanking()
    await h.model.loadMoreRanking()
    #expect(h.model.phase == .failed && h.model.rankings.isEmpty)
    #expect(h.model.rankingPage == nil)
    #expect(await h.provider.submitted().isEmpty)
  }

  @Test func peerActionsRejectSelfAndUnknownIDsAndUseOfficialRevision() async throws {
    let h = try JourneySocialUIHarness()
    await h.model.load()
    await h.model.report(memberID: UUID(uuidString: socialMember)!, reason: .spam)
    await h.model.block(memberID: UUID())
    #expect(await h.provider.submitted().isEmpty)
    await h.model.report(memberID: UUID(uuidString: socialPeer)!, reason: .spam)
    #expect(h.model.outcome == .saved)
    let operation = try #require(await h.provider.submitted().first)
    #expect(operation.expectedRevision == 1)
    #expect(operation.action == .report(memberID: UUID(uuidString: socialPeer)!, reason: .spam))
  }

  @Test func invalidReportCannotReuseThePreviousSavedOutcome() async throws {
    let h = try JourneySocialUIHarness()
    await h.model.load()
    await h.model.report(memberID: UUID(uuidString: socialPeer)!, reason: .spam)
    #expect(h.model.outcome == .saved)
    let reported = await h.model.report(memberID: UUID(uuidString: socialMember)!, reason: .spam)
    #expect(!reported && h.model.outcome == nil)
    #expect(await h.provider.submitted().count == 1)
  }

  @Test func savedCommandWithFailedRefreshIsNotPresentedAsANewUnsentIntent() async throws {
    let h = try JourneySocialUIHarness(participating: false)
    await h.model.load()
    await h.provider.failRanking()
    await h.model.saveParticipation(nickname: "Caminhante", accepted: true)
    #expect(h.model.outcome == .saved && h.model.pending == nil)
    #expect(h.model.profile?.optedIn == true && h.model.phase == .failed)
    #expect(await h.provider.submitted().count == 1)
    await h.model.load()
    #expect(await h.provider.submitted().count == 1)
  }

  @Test func deniedStoragePreventsReadSurfaceAndEveryWriter() async throws {
    let h = try JourneySocialUIHarness()
    await h.security.deny()
    await h.model.load()
    #expect(h.model.phase == .failed && h.model.profile == nil)
    #expect(h.model.rankings.isEmpty)
    await h.model.withdraw()
    #expect(await h.provider.submitted().isEmpty)
    #expect(await h.provider.profileReads == 0)
  }

  @Test func synchronousCloseClearsAudienceAndRejectsLateReadPublication() async throws {
    let h = try JourneySocialUIHarness()
    let barrier = ConversationControllerBarrier()
    await h.provider.holdProfile(barrier)
    let task = Task {
      await h.model.load()
      await barrier.finish()
    }
    let entered = await barrier.waitEnteredOrFinished()
    if !entered {
      await task.value
      Issue.record("Profile request did not start")
      return
    }
    h.model.invalidateSynchronously()
    #expect(h.model.phase == .closed && h.model.profile == nil && h.model.rankings.isEmpty)
    await barrier.release()
    await task.value
    await h.model.load()
    #expect(h.model.phase == .closed && h.model.profile == nil && h.model.rankings.isEmpty)
    #expect(await h.provider.profileReads == 1)
    #expect(await h.provider.submitted().isEmpty)
  }

  @Test func lifecyclePublicationFencePreventsVisiblePrivateState() async throws {
    let h = try JourneySocialUIHarness()
    await h.provider.denyPublication()
    await h.model.load()
    #expect(h.model.phase == .closed && h.model.profile == nil && h.model.pending == nil)
    #expect(h.model.rankings.isEmpty)
  }
}

@MainActor struct JourneySocialUIHarness {
  let provider: JourneySocialUIProvider
  let security: JourneySocialUISecurity
  let store: JourneySocialPendingStore
  let model: JourneySocialModel
  init(participating: Bool = true) throws {
    provider = try JourneySocialUIProvider(participating: participating)
    security = JourneySocialUISecurity()
    store = try JourneySocialPendingStore(origin: provider.origin, security: security)
    model = try JourneySocialModel(provider: provider, store: store, pageSize: 2)
  }
}

actor JourneySocialUIProvider: JourneySocialProviding {
  nonisolated let binding: JourneySocialBinding
  nonisolated let origin = URL(string: "https://social.example.test/")!
  private var currentProfile: JourneySocialProfile
  private var commands: [JourneySocialOperation] = []
  private var lostReply = false
  private var fenced = false
  private var rankFailure = false
  private var publicationDenied = false
  private var profileBarrier: ConversationControllerBarrier?
  private(set) var profileReads = 0
  private(set) var rankingReads = 0
  private(set) var recoveryReads = 0
  init(participating: Bool) throws {
    binding = .init(
      ownerID: UUID(uuidString: socialOwner)!, authUserID: UUID(uuidString: socialAuth)!,
      loginID: UUID(uuidString: "19800000-0000-4000-8000-000000000003")!)
    currentProfile = try Self.profile(participating, revision: participating ? 1 : 0)
  }
  func validate() throws { try Task.checkCancellation() }
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws {
    try validate()
    guard !publicationDenied else { throw SessionLifecycleError.sessionSuperseded }
    try await action()
  }
  func submitted() -> [JourneySocialOperation] { commands }
  func loseNextReply() { lostReply = true }
  func useFence() { fenced = true }
  func failRanking() { rankFailure = true }
  func denyPublication() { publicationDenied = true }
  func holdProfile(_ barrier: ConversationControllerBarrier) { profileBarrier = barrier }
  func replaceProfile(participating: Bool, revision: Int) throws {
    currentProfile = try Self.profile(participating, revision: revision)
  }
  func profile() async throws -> JourneySocialProfile {
    profileReads += 1
    if let b = profileBarrier {
      profileBarrier = nil
      await b.enter()
    }
    return currentProfile
  }
  func ranking(cursor: JourneySocialRankingCursor?, limit: Int) throws -> JourneySocialRankingPage {
    rankingReads += 1
    if rankFailure { throw URLError(.networkConnectionLost) }
    return try socialDecode(JourneySocialRankingPage.self, socialRanking(firstPage: cursor == nil))
  }
  func blocks(cursor: JourneySocialBlocksCursor?, limit: Int) throws -> JourneySocialBlocksPage {
    try socialDecode(
      JourneySocialBlocksPage.self,
      ["revision": currentProfile.revision, "entries": [], "next_cursor": NSNull()])
  }
  func submit(_ operation: JourneySocialOperation) throws -> JourneySocialMutationSnapshot {
    commands.append(operation)
    let revision = operation.expectedRevision + 1
    var receipt: [String: Any] = [
      "operation_id": operation.id.uuidString.lowercased(), "revision": revision,
    ]
    switch operation.action {
    case .participation(let nickname, _):
      currentProfile = try Self.profile(nickname != nil, revision: revision, nickname: nickname)
      receipt["opted_in"] = nickname != nil
    case .block(let member, let blocked):
      currentProfile = try Self.profile(currentProfile.optedIn, revision: revision)
      receipt["member_id"] = member.uuidString.lowercased()
      receipt["blocked"] = blocked
    case .report:
      currentProfile = try Self.profile(currentProfile.optedIn, revision: revision)
      receipt["report_id"] = "19800000-0000-4000-8000-000000000004"
      receipt["report_status"] = "pending"
    }
    if lostReply {
      lostReply = false
      throw URLError(.networkConnectionLost)
    }
    return try socialDecode(
      JourneySocialMutationSnapshot.self,
      ["status": "applied", "receipt": receipt, "profile": Self.raw(currentProfile)])
  }
  func recover(_ pending: JourneySocialPendingOperation) throws -> JourneySocialResolutionSnapshot {
    recoveryReads += 1
    let op = pending.operation
    return try socialDecode(
      JourneySocialResolutionSnapshot.self,
      [
        "status": fenced ? "fenced" : "applied", "operation_id": op.id.uuidString.lowercased(),
        "kind": op.kind, "expected_revision": op.expectedRevision,
        "receipt": fenced
          ? NSNull()
          : [
            "operation_id": op.id.uuidString.lowercased(), "revision": op.expectedRevision + 1,
            "opted_in": true,
          ], "profile": Self.raw(currentProfile),
      ])
  }
  private static func profile(
    _ participating: Bool, revision: Int, nickname: String? = "Caminhante"
  ) throws -> JourneySocialProfile {
    try socialDecode(
      JourneySocialProfile.self,
      [
        "revision": revision, "opted_in": participating,
        "nickname": participating ? (nickname ?? "Caminhante") as Any : NSNull(),
        "member_id": revision == 0 ? NSNull() : socialMember as Any, "moderation": "active",
      ])
  }
  private static func raw(_ p: JourneySocialProfile) -> [String: Any] {
    [
      "revision": p.revision, "opted_in": p.optedIn, "nickname": p.nickname as Any? ?? NSNull(),
      "member_id": p.memberID?.uuidString.lowercased() as Any? ?? NSNull(),
      "moderation": p.moderation.rawValue,
    ]
  }
}

actor JourneySocialUISecurity: KeychainSecurityClient {
  private var values: [String: Data] = [:]
  private var denied = false
  func deny() { denied = true }
  private func key(_ d: KeychainItemDescriptor) -> String { d.service + d.account }
  func read(_ d: KeychainItemDescriptor) -> KeychainReadResult {
    if denied { return .failure(errSecInteractionNotAllowed) }
    return values[key(d)].map(KeychainReadResult.data) ?? .notFound
  }
  func add(_ d: KeychainItemDescriptor, data: Data) -> OSStatus {
    guard values[key(d)] == nil else { return errSecDuplicateItem }
    values[key(d)] = data
    return errSecSuccess
  }
  func update(_ d: KeychainItemDescriptor, data: Data) -> OSStatus { errSecUnimplemented }
  func delete(_ d: KeychainItemDescriptor) -> OSStatus {
    values.removeValue(forKey: key(d))
    return errSecSuccess
  }
}
