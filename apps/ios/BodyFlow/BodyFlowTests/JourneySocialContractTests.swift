import Foundation
import Testing

@testable import BodyFlow

@Suite("Journey social participation is closed to the original account and session")
struct JourneySocialContractTests {
  // A generic authenticated read must not acquire the new social capability.
  @Test(arguments: [
    "/api/mobile/v1/profile/journey-social",
    "/api/mobile/v1/profile/journey-social/blocks",
    "/api/mobile/v1/profile/journey-social/reports",
    "/api/mobile/v1/journey/ranking",
  ])
  func unscopedSocialRequestsAreRefusedBeforeNetwork(_ path: String) {
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<MeSnapshot>(method: .get, path: path, unauthorizedReplay: .never)
    }
  }
}

extension JourneySocialContractTests {
  @Test func absentParticipationDoesNotInventConsentOrPublicIdentity() throws {
    let value = try socialDecode(
      JourneySocialProfile.self,
      [
        "revision": 0, "opted_in": false, "nickname": NSNull(), "member_id": NSNull(),
        "moderation": "active",
      ])
    #expect(value.revision == 0 && !value.optedIn && value.memberID == nil && value.nickname == nil)
    let profile = try socialDecode(JourneySocialProfile.self, socialProfile())
    #expect(
      profile.nickname == "Caminhante" && profile.memberID?.uuidString.lowercased() == socialMember)
    try profile.validate(binding: socialBinding())
  }
  @Test(arguments: [
    "extra", "missing", "fraction", "negative", "unsafe", "boolean", "nicknameMissing",
    "nicknameWithoutConsent", "memberMissing", "zeroWithMember", "moderation", "nicknameContact",
    "nicknameControl", "nicknameLong",
  ])
  func profileRejectsInconsistentConsentAndPrivateFields(_ attack: String) throws {
    var o = socialProfile()
    switch attack {
    case "extra": o["email"] = "private@example.invalid"
    case "missing": o.removeValue(forKey: "nickname")
    case "fraction": o["revision"] = 1.5
    case "negative": o["revision"] = -1
    case "unsafe": o["revision"] = 9_007_199_254_740_992 as Int64
    case "boolean": o["revision"] = true
    case "nicknameMissing": o["nickname"] = NSNull()
    case "nicknameWithoutConsent": o["opted_in"] = false
    case "memberMissing": o["member_id"] = NSNull()
    case "zeroWithMember": o["revision"] = 0
    case "moderation": o["moderation"] = "pending"
    case "nicknameContact": o["nickname"] = "name@example.invalid"
    case "nicknameControl": o["nickname"] = "Name\nOther"
    default: o["nickname"] = String(repeating: "a", count: 33)
    }
    #expect(throws: (any Error).self) { try socialDecode(JourneySocialProfile.self, o) }
  }
  @Test func publicIdentityNeverBecomesAuthOrDomainOwner() throws {
    for id in [socialOwner, socialAuth, socialLogin] {
      var p = socialProfile()
      p["member_id"] = id
      let profile = try socialDecode(JourneySocialProfile.self, p)
      #expect(throws: (any Error).self) { try profile.validate(binding: socialBinding()) }
    }
  }
  @Test func nicknameUsesServerUnicodeScalarsRatherThanGraphemeCount() throws {
    var p = socialProfile()
    p["nickname"] = String(repeating: "🙂", count: 32)
    #expect(try socialDecode(JourneySocialProfile.self, p).nickname?.unicodeScalars.count == 32)
    p["nickname"] = String(repeating: "🙂", count: 33)
    #expect(throws: (any Error).self) { try socialDecode(JourneySocialProfile.self, p) }
    p["nickname"] = " a"
    #expect(throws: (any Error).self) { try socialDecode(JourneySocialProfile.self, p) }
  }
  @Test func officialWeeklyRankingPreservesSharedTiesAndNextPageContext() throws {
    let first = try socialStage("first decode") {
      try socialDecode(JourneySocialRankingPage.self, socialRanking(firstPage: true))
    }
    try socialStage("first page validation") {
      try first.validate(binding: socialBinding(), cursor: nil, limit: 2)
    }
    #expect(first.entries.map(\.rank) == [1, 1])
    #expect(first.entries.map(\.weeklyXP) == [100, 100])
    let cursor = try #require(first.nextCursor)
    #expect(cursor.offset == 2 && cursor.weekStart == "2026-11-16")
    let second = try socialStage("second decode") {
      try socialDecode(JourneySocialRankingPage.self, socialRanking(firstPage: false))
    }
    try socialStage("second page validation") {
      try second.validate(binding: socialBinding(), cursor: cursor, limit: 2)
    }
    #expect(second.entries.map(\.rank) == [3] && second.entries[0].weeklyXP == 90)
  }
  @Test(arguments: [
    "extraRoot", "health", "basis", "invalidDate", "notMonday", "badEnd", "futureThrough",
    "duplicate", "tieOrder", "wrongTie", "xpOrder", "twoViewers", "unsafeXP", "badCursor",
    "foreignCursor", "cursorContext",
  ])
  func rankingRefusesLeakedOrInconsistentAudienceAndScores(_ attack: String) throws {
    var o = socialRanking(firstPage: true)
    var rows = o["entries"] as! [[String: Any]]
    switch attack {
    case "extraRoot": o["user_id"] = socialOwner
    case "health": rows[0]["protein_g"] = 100
    case "basis": o["basis"] = "user_progress_total"
    case "invalidDate": o["week_start"] = "2026-02-30"
    case "notMonday": o["week_start"] = "2026-11-17"
    case "badEnd": o["week_end"] = "2026-11-23"
    case "futureThrough": o["through_date"] = "2026-11-23"
    case "duplicate": rows[1]["member_id"] = socialMember
    case "tieOrder": rows.reverse()
    case "wrongTie": rows[1]["rank"] = 2
    case "xpOrder": rows[1]["weekly_xp"] = 101
    case "twoViewers": rows[1]["is_you"] = true
    case "unsafeXP": rows[0]["weekly_xp"] = 9_007_199_254_740_992 as Int64
    case "badCursor":
      var c = o["next_cursor"] as! [String: Any]
      c["offset"] = 1
      o["next_cursor"] = c
    case "foreignCursor":
      var c = o["next_cursor"] as! [String: Any]
      c["viewer_member_id"] = socialAuth
      o["next_cursor"] = c
    default:
      var c = o["next_cursor"] as! [String: Any]
      c["week_start"] = "2026-11-09"
      o["next_cursor"] = c
    }
    o["entries"] = rows
    #expect(throws: (any Error).self) {
      try socialDecode(JourneySocialRankingPage.self, o).validate(
        binding: socialBinding(), cursor: nil, limit: 2)
    }
  }
  @Test func replayKeepsCurrentWithdrawalRatherThanRestoringHistoricalConsent() throws {
    let binding = try socialBinding()
    let operation = try JourneySocialOperation(
      binding: binding, id: UUID(uuidString: socialOperation)!, expectedRevision: 0,
      action: .participation(nickname: "Caminhante", consentVersion: "journey-social.v1"))
    var current = socialProfile()
    current["revision"] = 2
    current["opted_in"] = false
    current["nickname"] = NSNull()
    let reply = try socialDecode(
      JourneySocialMutationSnapshot.self,
      [
        "status": "replayed",
        "receipt": ["operation_id": socialOperation, "revision": 1, "opted_in": true],
        "profile": current,
      ])
    try reply.validate(for: operation)
    #expect(!reply.profile.optedIn && reply.profile.revision == 2)
    let body = try JSONSerialization.jsonObject(with: operation.wireBody) as! [String: Any]
    #expect(body["consent_version"] as? String == "journey-social.v1")
    #expect(body["expected_revision"] as? Int == 0)
    #expect(operation.idempotencyKey == "jsocial1:19500000-0000-4000-8000-000000000100")
    #expect(body["owner_id"] == nil && body["auth_user_id"] == nil)
  }
  @Test(arguments: [
    "wrongOperation", "wrongRevision", "wrongAction", "staleProfile", "appliedOldProfile",
    "changedNickname", "privateReceipt",
  ])
  func mutationReceiptOnlyAcknowledgesItsExactOperation(_ attack: String) throws {
    let operation = try JourneySocialOperation(
      binding: socialBinding(), id: UUID(uuidString: socialOperation)!, expectedRevision: 0,
      action: .participation(nickname: "Caminhante", consentVersion: "journey-social.v1"))
    var receipt: [String: Any] = ["operation_id": socialOperation, "revision": 1, "opted_in": true]
    var profile = socialProfile()
    switch attack {
    case "wrongOperation": receipt["operation_id"] = socialPeer
    case "wrongRevision": receipt["revision"] = 2
    case "wrongAction":
      receipt = [
        "operation_id": socialOperation, "revision": 1, "member_id": socialPeer, "blocked": true,
      ]
    case "staleProfile":
      profile = [
        "revision": 0, "opted_in": false, "nickname": NSNull(), "member_id": NSNull(),
        "moderation": "active",
      ]
    case "appliedOldProfile": profile["revision"] = 2
    case "changedNickname": profile["nickname"] = "Different"
    default: receipt["email"] = "private@example.invalid"
    }
    #expect(throws: (any Error).self) {
      try socialDecode(
        JourneySocialMutationSnapshot.self,
        ["status": "applied", "receipt": receipt, "profile": profile]
      ).validate(for: operation)
    }
  }
  @Test func optingOutDoesNotCreateOrImplicitlyAcceptAConsent() throws {
    let o = try JourneySocialOperation(
      binding: socialBinding(), id: UUID(), expectedRevision: 1,
      action: .participation(nickname: nil, consentVersion: nil))
    let body = try JSONSerialization.jsonObject(with: o.wireBody) as! [String: Any]
    #expect(
      body["opted_in"] as? Bool == false && body["nickname"] is NSNull
        && body["consent_version"] is NSNull)
    #expect(throws: (any Error).self) {
      try JourneySocialOperation(
        binding: socialBinding(), id: UUID(), expectedRevision: 0,
        action: .participation(nickname: "Caminhante", consentVersion: nil))
    }
    #expect(throws: (any Error).self) {
      try JourneySocialOperation(
        binding: socialBinding(), id: UUID(), expectedRevision: 0,
        action: .block(memberID: UUID(uuidString: socialPeer)!, blocked: true))
    }
    #expect(throws: (any Error).self) {
      try JourneySocialOperation(
        binding: socialBinding(), id: UUID(), expectedRevision: 1,
        action: .report(memberID: UUID(uuidString: socialAuth)!, reason: .spam))
    }
  }
}

let socialOwner = "19500000-0000-4000-8000-000000000001"
let socialAuth = "19500000-0000-4000-8000-000000000002"
let socialLogin = "19500000-0000-4000-8000-000000000003"
let socialMember = "19500000-0000-4000-8000-000000000010"
let socialPeer = "19500000-0000-4000-8000-000000000011"
let socialOperation = "19500000-0000-4000-8000-000000000100"
func socialBinding() throws -> JourneySocialBinding {
  .init(
    ownerID: UUID(uuidString: socialOwner)!, authUserID: UUID(uuidString: socialAuth)!,
    loginID: UUID(uuidString: socialLogin)!)
}
func socialDecode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
  try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
}
func socialProfile() -> [String: Any] {
  [
    "revision": 1, "opted_in": true, "nickname": "Caminhante", "member_id": socialMember,
    "moderation": "active",
  ]
}
func socialRanking(firstPage: Bool) -> [String: Any] {
  let cursor: [String: Any] = [
    "context_hash": String(repeating: "a", count: 64), "offset": 2,
    "viewer_member_id": socialMember, "week_start": "2026-11-16", "through_date": "2026-11-18",
  ]
  let entries: [[String: Any]] =
    firstPage
    ? [
      [
        "member_id": socialMember, "nickname": "Caminhante", "rank": 1, "weekly_xp": 100,
        "is_you": true,
      ],
      ["member_id": socialPeer, "nickname": "Outro", "rank": 1, "weekly_xp": 100, "is_you": false],
    ]
    : [
      [
        "member_id": "19500000-0000-4000-8000-000000000012", "nickname": "Terceiro", "rank": 3,
        "weekly_xp": 90, "is_you": false,
      ]
    ]
  return [
    "week_start": "2026-11-16", "week_end": "2026-11-22", "through_date": "2026-11-18",
    "basis": "closed_daily_xp", "entries": entries, "next_cursor": firstPage ? cursor : NSNull(),
  ]
}

extension JourneySocialContractTests {
  @Test func socialCapabilityBindsExactPathBodyOwnerAndOriginalLogin() throws {
    let binding = try socialBinding()
    let operation = try JourneySocialOperation(
      binding: binding, id: UUID(uuidString: socialOperation)!, expectedRevision: 1,
      action: .block(memberID: UUID(uuidString: socialPeer)!, blocked: true))
    let request = try MobileAPIRequest<JourneySocialMutationSnapshot>(
      method: .post, path: "/api/mobile/v1/profile/journey-social/blocks", body: operation.wireBody,
      idempotencyKey: IdempotencyKey(validating: operation.idempotencyKey),
      unauthorizedReplay: .never, journeySocial: .mutation(operation))
    var wire = URLRequest(
      url: URL(string: "https://unit.invalid/api/mobile/v1/profile/journey-social/blocks")!)
    request.journeySocial?.apply(to: &wire)
    #expect(
      wire.value(forHTTPHeaderField: "X-Journey-Owner") == "19500000-0000-4000-8000-000000000001")
    #expect(
      wire.value(forHTTPHeaderField: "X-Journey-Session") == "19500000-0000-4000-8000-000000000003")
    #expect(wire.value(forHTTPHeaderField: "X-Conversation-Owner") == nil)
    try request.journeySocial?.validate(lease: socialLease())
    #expect(throws: (any Error).self) {
      try request.journeySocial?.validate(lease: socialLease(login: socialPeer))
    }
    #expect(throws: (any Error).self) {
      try request.journeySocial?.validate(lease: socialLease(auth: socialOwner))
    }
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<MeSnapshot>(
        method: .get, path: "/api/mobile/v1/me", unauthorizedReplay: .never,
        journeySocial: .profile(binding))
    }
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<MeSnapshot>(
        method: .get, path: "/api/mobile/v1/profile/journey-social",
        journeySocial: .profile(binding))
    }
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<MeSnapshot>(
        method: .post, path: operation.path, body: Data("{}".utf8),
        idempotencyKey: IdempotencyKey(validating: operation.idempotencyKey),
        unauthorizedReplay: .never, journeySocial: .mutation(operation))
    }
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<MeSnapshot>(
        method: .post, path: operation.path, body: operation.wireBody,
        idempotencyKey: IdempotencyKey(validating: "jsocial1:" + socialPeer),
        unauthorizedReplay: .never, journeySocial: .mutation(operation))
    }
  }
  @Test func socialSuccessRequiresExplicitUncachedProtocolRatherThanLegacyFallback() throws {
    let h = MobileJourneySocialRequestHeaders.profile(try socialBinding())
    let url = URL(string: "https://unit.invalid/api/mobile/v1/profile/journey-social")!
    try h.validateResponseProtocol(
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["X-Journey-Social": "1", "Cache-Control": "no-store"])!)
    for headers in [
      ["Cache-Control": "no-store"], ["X-Journey-Social": "2", "Cache-Control": "no-store"],
      ["X-Journey-Social": "1", "Cache-Control": "public"],
    ] {
      #expect(throws: (any Error).self) {
        try h.validateResponseProtocol(
          HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
      }
    }
    #expect(throws: (any Error).self) {
      try h.validateResponseProtocol(
        HTTPURLResponse(
          url: url, statusCode: 202, httpVersion: nil,
          headerFields: ["X-Journey-Social": "1", "Cache-Control": "no-store"])!)
    }
    try h.validateResponseProtocol(
      HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: [:])!)
  }
  @Test func blockedPeersArePaginatedWithoutLeakingHiddenNamesOrChangingRevision() throws {
    let raw: [String: Any] = [
      "revision": 3,
      "entries": [
        ["member_id": socialMember, "nickname": NSNull()],
        ["member_id": socialPeer, "nickname": "Outro"],
      ], "next_cursor": ["revision": 3, "after_member_id": socialPeer],
    ]
    let page = try socialDecode(JourneySocialBlocksPage.self, raw)
    try page.validate(binding: socialBinding(), cursor: nil, limit: 2)
    #expect(page.entries[0].nickname == nil && page.entries.count == 2)
    for attack in ["wrongRevision", "wrongLast", "privateIdentity", "order", "extraHealth"] {
      var o = raw
      var rows = o["entries"] as! [[String: Any]]
      switch attack {
      case "wrongRevision": o["next_cursor"] = ["revision": 4, "after_member_id": socialPeer]
      case "wrongLast": o["next_cursor"] = ["revision": 3, "after_member_id": socialMember]
      case "privateIdentity": rows[0]["member_id"] = socialAuth
      case "order": rows.reverse()
      default: rows[0]["weight_kg"] = 80
      }
      o["entries"] = rows
      #expect(throws: (any Error).self) {
        try socialDecode(JourneySocialBlocksPage.self, o).validate(
          binding: socialBinding(), cursor: nil, limit: 2)
      }
    }
  }
}
func socialLease(auth: String = socialAuth, login: String = socialLogin, generation: UInt64 = 1)
  -> SessionLease
{
  let payload = Data("{\"sub\":\"\(auth)\",\"session_id\":\"\(login)\"}".utf8).base64EncodedString()
    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
  return SessionLease(
    userID: auth, generation: generation, bearer: "e30." + payload + ".unit-signature")
}

private struct SocialDiagnosticFailure: Error, CustomStringConvertible { let description: String }
private func socialStage<T>(_ label: String, _ body: () throws -> T) throws -> T {
  do { return try body() } catch {
    throw SocialDiagnosticFailure(description: label + ": " + String(reflecting: error))
  }
}
