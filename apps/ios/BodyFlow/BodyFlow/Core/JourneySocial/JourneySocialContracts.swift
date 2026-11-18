import Foundation

struct JourneySocialBinding: Equatable, Sendable {
  let ownerID: UUID
  let authUserID: UUID
  let loginID: UUID
  func publicID(_ id: UUID) throws {
    try socialRequire(id != ownerID && id != authUserID && id != loginID)
  }
  /// These claims identify only the lifecycle-verified original login. They
  /// never replace server Auth verification or grant patient/staff authority.
  func validate(lease: SessionLease) throws {
    guard UUID(uuidString: lease.userID) == authUserID,
      try Self.originalLogin(lease) == loginID
    else { throw SessionLifecycleError.sessionSuperseded }
  }
  static func originalLogin(_ lease: SessionLease) throws -> UUID {
    struct Claims: Decodable {
      let sub: UUID
      let sessionID: UUID
      enum CodingKeys: String, CodingKey {
        case sub
        case sessionID = "session_id"
      }
    }
    let pieces = lease.bearer.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count == 3, lease.bearer.utf8.count <= 16_384,
      pieces[1].utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
          || $0 == 95
      })
    else { throw SessionLifecycleError.sessionSuperseded }
    var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded),
      let value = try? JSONDecoder().decode(Claims.self, from: data),
      value.sub == UUID(uuidString: lease.userID)
    else { throw SessionLifecycleError.sessionSuperseded }
    return value.sessionID
  }
}

enum JourneySocialInvalid: Error { case value }
func socialRequire(_ condition: Bool) throws {
  guard condition else { throw JourneySocialInvalid.value }
}
private func socialNickname(_ raw: ConversationMealEditJSON) throws -> String {
  let s = try raw.string()
  let scalars = s.unicodeScalars
  try socialRequire(
    (2...32).contains(scalars.count) && !s.hasPrefix(" ") && !s.hasSuffix(" ")
      && !scalars.contains { $0.value < 32 || (127...159).contains($0.value) || $0.value == 64 })
  return s
}
private func socialInteger(
  _ raw: ConversationMealEditJSON, min: Int = 0, max: Int = 9_007_199_254_740_991
) throws -> Int {
  let n = try raw.amount(min: Double(min), max: Double(max))
  try socialRequire(n.rounded() == n)
  return Int(n)
}
private func socialDate(_ raw: ConversationMealEditJSON) throws -> String {
  let s = try raw.string()
  try socialRequire(NutritionCivilDate.date(s) != nil)
  return s
}
private func socialDecode(_ decoder: any Decoder) throws -> ConversationMealEditJSON {
  let value = try ConversationMealEditJSON(from: decoder)
  try value.boundPublicPacket()
  return value
}

struct JourneySocialProfile: Decodable, Sendable {
  enum Moderation: String, Sendable { case active, suspended }
  let revision: Int
  let optedIn: Bool
  let nickname: String?
  let memberID: UUID?
  let moderation: Moderation
  init(from decoder: any Decoder) throws { try self.init(raw: socialDecode(decoder)) }
  fileprivate init(raw: ConversationMealEditJSON) throws {
    let o = try raw.object(["revision", "opted_in", "nickname", "member_id", "moderation"])
    revision = try socialInteger(o.required("revision"))
    optedIn = try o.required("opted_in").bool()
    nickname = try o.required("nickname").optional(socialNickname)
    memberID = try o.required("member_id").optional { try $0.uuid() }
    guard let state = try Moderation(rawValue: o.required("moderation").string()) else {
      throw JourneySocialInvalid.value
    }
    moderation = state
    try socialRequire(optedIn == (nickname != nil))
    if revision == 0 {
      try socialRequire(!optedIn && nickname == nil && memberID == nil && moderation == .active)
    } else {
      try socialRequire(memberID != nil)
    }
  }
  func validate(binding: JourneySocialBinding) throws {
    if let memberID { try binding.publicID(memberID) }
  }
}

struct JourneySocialRankingCursor: Equatable, Sendable {
  let contextHash: String
  let offset: Int
  let viewerMemberID: UUID
  let weekStart: String
  let throughDate: String
  fileprivate init(_ raw: ConversationMealEditJSON) throws {
    let o = try raw.object([
      "context_hash", "offset", "viewer_member_id", "week_start", "through_date",
    ])
    contextHash = try o.required("context_hash").hash()
    offset = try socialInteger(o.required("offset"), min: 1, max: 2_147_483_647)
    viewerMemberID = try o.required("viewer_member_id").uuid()
    weekStart = try socialDate(o.required("week_start"))
    throughDate = try socialDate(o.required("through_date"))
  }
  var json: ConversationMealEditJSON {
    .object([
      "context_hash": .string(contextHash), "offset": .number(Double(offset)),
      "viewer_member_id": .string(viewerMemberID.uuidString.lowercased()),
      "week_start": .string(weekStart), "through_date": .string(throughDate),
    ])
  }
}
struct JourneySocialRankingPage: Decodable, Sendable {
  struct Entry: Sendable, Identifiable {
    let memberID: UUID
    let nickname: String
    let rank: Int
    let weeklyXP: Int
    let isYou: Bool
    var id: UUID { memberID }
  }
  let weekStart: String
  let weekEnd: String
  let throughDate: String
  let entries: [Entry]
  let nextCursor: JourneySocialRankingCursor?
  init(from decoder: any Decoder) throws {
    let o = try socialDecode(decoder).object([
      "week_start", "week_end", "through_date", "basis", "entries", "next_cursor",
    ])
    weekStart = try socialDate(o.required("week_start"))
    weekEnd = try socialDate(o.required("week_end"))
    throughDate = try socialDate(o.required("through_date"))
    try socialRequire(o.required("basis").string() == "closed_daily_xp")
    let rows = try o.required("entries").array()
    try socialRequire(rows.count <= 100)
    entries = try rows.map { raw in
      let r = try raw.object(["member_id", "nickname", "rank", "weekly_xp", "is_you"])
      return try Entry(
        memberID: r.required("member_id").uuid(), nickname: socialNickname(r.required("nickname")),
        rank: socialInteger(r.required("rank"), min: 1),
        weeklyXP: socialInteger(r.required("weekly_xp"), min: -9_007_199_254_740_991),
        isYou: r.required("is_you").bool())
    }
    nextCursor = try o.required("next_cursor").optional(JourneySocialRankingCursor.init)
  }
  func validate(binding: JourneySocialBinding, cursor: JourneySocialRankingCursor?, limit: Int)
    throws
  {
    try socialRequire((1...100).contains(limit) && entries.count <= limit)
    guard let start = NutritionCivilDate.date(weekStart),
      let end = NutritionCivilDate.date(weekEnd), let through = NutritionCivilDate.date(throughDate)
    else { throw JourneySocialInvalid.value }
    try socialRequire(
      NutritionCivilDate.calendar.component(.weekday, from: start) == 2
        && end.timeIntervalSince(start) == 6 * 86_400 && through >= start && through <= end)
    let offset = cursor?.offset ?? 0
    if let cursor {
      try binding.publicID(cursor.viewerMemberID)
      try socialRequire(cursor.weekStart == weekStart && cursor.throughDate == throughDate)
    }
    let viewer = cursor?.viewerMemberID ?? nextCursor?.viewerMemberID
    var ids = Set<UUID>()
    var yours = 0
    for (index, row) in entries.enumerated() {
      try binding.publicID(row.memberID)
      try socialRequire(ids.insert(row.memberID).inserted && row.rank <= offset + index + 1)
      if row.isYou { yours += 1 }
      if let viewer { try socialRequire(row.isYou == (row.memberID == viewer)) }
      if index > 0 {
        let prior = entries[index - 1]
        try socialRequire(row.weeklyXP <= prior.weeklyXP)
        if row.weeklyXP == prior.weeklyXP {
          try socialRequire(
            row.rank == prior.rank && row.memberID.uuidString > prior.memberID.uuidString)
        } else {
          try socialRequire(row.rank == offset + index + 1)
        }
      }
    }
    try socialRequire(yours <= 1)
    if let nextCursor {
      try binding.publicID(nextCursor.viewerMemberID)
      try socialRequire(
        entries.count == limit && nextCursor.offset == offset + entries.count
          && nextCursor.weekStart == weekStart && nextCursor.throughDate == throughDate)
      if let cursor {
        try socialRequire(
          nextCursor.contextHash == cursor.contextHash
            && nextCursor.viewerMemberID == cursor.viewerMemberID)
      }
    }
  }
}

struct JourneySocialBlocksCursor: Equatable, Sendable {
  let revision: Int
  let afterMemberID: UUID
  fileprivate init(_ raw: ConversationMealEditJSON) throws {
    let o = try raw.object(["revision", "after_member_id"])
    revision = try socialInteger(o.required("revision"), min: 1)
    afterMemberID = try o.required("after_member_id").uuid()
  }
  var json: ConversationMealEditJSON {
    .object([
      "revision": .number(Double(revision)),
      "after_member_id": .string(afterMemberID.uuidString.lowercased()),
    ])
  }
}
struct JourneySocialBlocksPage: Decodable, Sendable {
  struct Entry: Sendable, Identifiable {
    let memberID: UUID
    let nickname: String?
    var id: UUID { memberID }
  }
  let revision: Int
  let entries: [Entry]
  let nextCursor: JourneySocialBlocksCursor?
  init(from decoder: any Decoder) throws {
    let o = try socialDecode(decoder).object(["revision", "entries", "next_cursor"])
    revision = try socialInteger(o.required("revision"))
    let rows = try o.required("entries").array()
    try socialRequire(rows.count <= 100)
    entries = try rows.map { raw in
      let r = try raw.object(["member_id", "nickname"])
      return try Entry(
        memberID: r.required("member_id").uuid(),
        nickname: r.required("nickname").optional(socialNickname))
    }
    nextCursor = try o.required("next_cursor").optional(JourneySocialBlocksCursor.init)
  }
  func validate(binding: JourneySocialBinding, cursor: JourneySocialBlocksCursor?, limit: Int)
    throws
  {
    try socialRequire(
      (1...100).contains(limit) && entries.count <= limit
        && (cursor == nil || cursor?.revision == revision))
    var previous = cursor?.afterMemberID
    if let previous { try binding.publicID(previous) }
    for row in entries {
      try binding.publicID(row.memberID)
      if let previous { try socialRequire(row.memberID.uuidString > previous.uuidString) }
      previous = row.memberID
    }
    if let nextCursor {
      try socialRequire(
        entries.count == limit && nextCursor.revision == revision
          && nextCursor.afterMemberID == previous)
    }
  }
}

enum JourneySocialReportReason: String, Sendable { case nickname, harassment, spam, other }
struct JourneySocialOperation: Sendable, Equatable {
  enum Action: Sendable, Equatable {
    case participation(nickname: String?, consentVersion: String?)
    case block(memberID: UUID, blocked: Bool)
    case report(memberID: UUID, reason: JourneySocialReportReason)
  }
  let binding: JourneySocialBinding
  let id: UUID
  let expectedRevision: Int
  let action: Action
  let wireBody: Data
  var kind: String {
    switch action {
    case .participation: "profile"
    case .block: "block"
    case .report: "report"
    }
  }
  var idempotencyKey: String { "jsocial1:" + id.uuidString.lowercased() }
  var path: String {
    switch action {
    case .participation: "/api/mobile/v1/profile/journey-social"
    case .block: "/api/mobile/v1/profile/journey-social/blocks"
    case .report: "/api/mobile/v1/profile/journey-social/reports"
    }
  }
  var method: HTTPMethod { if case .participation = action { .patch } else { .post } }
  init(binding: JourneySocialBinding, id: UUID, expectedRevision: Int, action: Action) throws {
    try socialRequire((0...9_007_199_254_740_990).contains(expectedRevision))
    var o: [String: ConversationMealEditJSON] = [
      "operation_id": .string(id.uuidString.lowercased()),
      "expected_revision": .number(Double(expectedRevision)),
    ]
    switch action {
    case .participation(let nickname, let consentVersion):
      if let nickname {
        _ = try socialNickname(.string(nickname))
        try socialRequire(consentVersion == "journey-social.v1")
      } else {
        try socialRequire(consentVersion == nil)
      }
      o["opted_in"] = .bool(nickname != nil)
      o["nickname"] = nickname.map(ConversationMealEditJSON.string) ?? .null
      o["consent_version"] = consentVersion.map(ConversationMealEditJSON.string) ?? .null
    case .block(let member, let blocked):
      try socialRequire(expectedRevision >= 1)
      try binding.publicID(member)
      o["member_id"] = .string(member.uuidString.lowercased())
      o["blocked"] = .bool(blocked)
    case .report(let member, let reason):
      try socialRequire(expectedRevision >= 1)
      try binding.publicID(member)
      o["member_id"] = .string(member.uuidString.lowercased())
      o["reason"] = .string(reason.rawValue)
    }
    self.binding = binding
    self.id = id
    self.expectedRevision = expectedRevision
    self.action = action
    wireBody = try ConversationMealEditJSON.object(o).data()
  }
  /// Reconstruct only the existing closed command, not an arbitrary request.
  init(binding: JourneySocialBinding, kind: String, command: ConversationMealEditJSON) throws {
    let keys: Set<String>
    switch kind {
    case "profile":
      keys = ["operation_id", "expected_revision", "opted_in", "nickname", "consent_version"]
    case "block": keys = ["operation_id", "expected_revision", "member_id", "blocked"]
    case "report": keys = ["operation_id", "expected_revision", "member_id", "reason"]
    default: throw JourneySocialInvalid.value
    }
    let o = try command.object(keys)
    let id = try o.required("operation_id").uuid()
    let revision = try socialInteger(o.required("expected_revision"), max: 9_007_199_254_740_990)
    let action: Action
    switch kind {
    case "profile":
      let nickname = try o.required("nickname").optional { try $0.string() }
      try socialRequire(o.required("opted_in").bool() == (nickname != nil))
      action = .participation(
        nickname: nickname,
        consentVersion: try o.required("consent_version").optional { try $0.string() })
    case "block":
      action = .block(
        memberID: try o.required("member_id").uuid(), blocked: try o.required("blocked").bool())
    default:
      guard let reason = try JourneySocialReportReason(rawValue: o.required("reason").string())
      else { throw JourneySocialInvalid.value }
      action = .report(memberID: try o.required("member_id").uuid(), reason: reason)
    }
    try self.init(binding: binding, id: id, expectedRevision: revision, action: action)
    try socialRequire(command.data() == wireBody)
  }
}
struct JourneySocialMutationSnapshot: Decodable, Sendable {
  enum Status: String, Sendable { case applied, replayed }
  enum Receipt: Sendable {
    case participation(Bool)
    case block(UUID, Bool)
    case report(UUID)
  }
  let status: Status
  let operationID: UUID
  let revision: Int
  let receipt: Receipt
  let profile: JourneySocialProfile
  init(from decoder: any Decoder) throws {
    let o = try socialDecode(decoder).object(["status", "receipt", "profile"])
    guard let status = try Status(rawValue: o.required("status").string()) else {
      throw JourneySocialInvalid.value
    }
    self.status = status
    profile = try JourneySocialProfile(raw: o.required("profile"))
    let raw = try o.required("receipt")
    guard case .object(let r) = raw else { throw JourneySocialInvalid.value }
    operationID = try r.required("operation_id").uuid()
    revision = try socialInteger(r.required("revision"), min: 1)
    if r["opted_in"] != nil {
      _ = try raw.object(["operation_id", "revision", "opted_in"])
      receipt = .participation(try r.required("opted_in").bool())
    } else if r["blocked"] != nil {
      _ = try raw.object(["operation_id", "revision", "member_id", "blocked"])
      receipt = .block(try r.required("member_id").uuid(), try r.required("blocked").bool())
    } else {
      _ = try raw.object(["operation_id", "revision", "report_id", "report_status"])
      try socialRequire(r.required("report_status").string() == "pending")
      receipt = .report(try r.required("report_id").uuid())
    }
  }
  func validate(for operation: JourneySocialOperation) throws {
    try profile.validate(binding: operation.binding)
    try socialRequire(
      operationID == operation.id && revision == operation.expectedRevision + 1
        && profile.revision >= revision && (status != .applied || profile.revision == revision))
    switch (operation.action, receipt) {
    case (.participation(let nickname, _), .participation(let optedIn)):
      try socialRequire(optedIn == (nickname != nil))
      if status == .applied {
        try socialRequire(profile.optedIn == optedIn && profile.nickname == nickname)
      }
    case (.block(let member, let blocked), .block(let target, let value)):
      try socialRequire(member == target && blocked == value)
    case (.report, .report(let id)): try operation.binding.publicID(id)
    default: throw JourneySocialInvalid.value
    }
  }
}
