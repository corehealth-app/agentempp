import Foundation
import Testing

@testable import BodyFlow

@Suite("Nutrition Day/Week uses only complete owned official observations")
@MainActor
struct NutritionWindowTests {
  @Test func completeCivilWindowKeepsPlannedAndConsumedDistinctWithoutDeduplicatingMeals() throws {
    let f = try NutritionWindowFixture()
    let value = try f.snapshot()
    #expect(
      value.days.count == 7 && value.weekStart == "2026-11-02" && value.weekEnd == "2026-11-08")
    #expect(value.currentLocalDate == "2026-11-04" && value.timezone == "America/Sao_Paulo")
    let day = try #require(value.days.first { $0.localDate == "2026-11-04" })
    #expect(day.meals.count == 2 && Set(day.meals.map(\.registrationKey)).count == 2)
    #expect(day.meals.allSatisfy { $0.foodName == "Arroz branco cozido" && $0.quantityG == 150 })
    #expect(day.totals.kcal == 385 && day.targets.caloriesKcal == nil)
    #expect(day.planned.meals.first?.items.first?.foodName == "Feijão cozido")
    #expect(
      value.days[0].meals.isEmpty && value.days[0].totals.kcal == 0
        && value.days[0].targets.caloriesKcal == nil)
  }
  @Test(arguments: [
    "zone", "calendar", "duplicate", "meal-date", "unknown-zero", "version", "policy-clock",
  ])
  func invalidOrUnqualifiedWindowCannotBecomeCurrentNutrition(_ attack: String) throws {
    let f = try NutritionWindowFixture()
    var raw = try f.raw()
    var days = try #require(raw["days"] as? [[String: Any]])
    switch attack {
    case "zone": raw["timezone"] = "Unknown/Not-A-Zone"
    case "calendar": days[0]["local_date"] = "2026-02-30"
    case "duplicate":
      var meals = try #require(days[2]["meals"] as? [[String: Any]])
      meals[1]["id"] = meals[0]["id"]
      days[2]["meals"] = meals
    case "meal-date":
      var meals = try #require(days[2]["meals"] as? [[String: Any]])
      meals[0]["consumed_at"] = "2026-11-05T15:00:00.000000Z"
      days[2]["meals"] = meals
    case "unknown-zero":
      var totals = try #require(days[0]["totals"] as? [String: Any])
      totals["source"] = "unavailable"
      days[0]["totals"] = totals
    case "version": raw["source_version"] = "not-a-source-version"
    default:
      var policy = try #require(raw["clinical_policy"] as? [String: Any])
      policy["observed_at"] = "2026-11-04T16:00:00.000000Z"
      raw["clinical_policy"] = policy
    }
    raw["days"] = days
    #expect(throws: (any Error).self) { try f.snapshot(raw) }
  }
  @Test func plannedDaySelectionDoesNotMutateRecordsAndRevisionReloadShowsCorrectedValues()
    async throws
  {
    let f = try NutritionWindowFixture()
    let before = try f.snapshot()
    let after = try f.corrected()
    let provider = NutritionWindowTestProvider([before, after])
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: before.authUserID)
    await model.load(revision: 0)
    model.selectDay("2026-11-02")
    #expect(model.selectedDay?.meals.isEmpty == true && model.selectedDay?.totals.kcal == 0)
    model.selectDay("2026-11-04")
    #expect(model.selectedDay?.meals.first?.quantityG == 150)
    await model.load(revision: 1)
    #expect(model.selectedDay?.meals.first?.quantityG == 200)
    #expect(model.selectedDay?.meals.first?.id != before.days[2].meals.first?.id)
    #expect(model.selectedDay?.totals.kcal == 449)
    #expect(await provider.calls == 2)
  }
  @Test func lateOldWindowCannotReplaceANewerFlowRevision() async throws {
    let f = try NutritionWindowFixture()
    let old = try f.snapshot()
    let newer = try f.corrected()
    let barrier = ConversationControllerBarrier()
    let provider = NutritionWindowBlockingProvider(old: old, new: newer, barrier: barrier)
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: old.authUserID)
    let first = Task { await model.load(revision: 0) }
    #expect(await barrier.waitEnteredOrFinished())
    await model.load(revision: 1)
    #expect(model.snapshot?.sourceVersion == newer.sourceVersion)
    await barrier.release()
    await first.value
    #expect(model.snapshot?.sourceVersion == newer.sourceVersion)
  }
  @Test func staleObservationsAndClosedScopeDoNotReuseCachedClinicalValues() async throws {
    let f = try NutritionWindowFixture()
    let before = try f.snapshot()
    let newer = try f.corrected()
    let provider = NutritionWindowTestProvider([newer, before, before])
    let scope = NutritionWindowTestScope()
    let model = NutritionWindowModel(
      provider: provider, expectedAuthUserID: before.authUserID, isCurrent: { scope.active })
    await model.load(revision: 0)
    #expect(model.snapshot != nil)
    await model.load(revision: 1)
    #expect(model.snapshot == nil && model.failure == .changed)
    await model.load(revision: 2)
    #expect(model.snapshot == nil && model.failure == .changed)
    scope.active = false
    #expect(model.snapshot == nil && model.phase == .unavailable)
  }
  @Test func refreshedUndoRemovesOnlyConfirmedFactsAndRetainsTheSeparatePlan() async throws {
    let f = try NutritionWindowFixture()
    let before = try f.snapshot()
    var raw = try f.raw()
    var days = try #require(raw["days"] as? [[String: Any]])
    days[2]["meals"] = [] as [[String: Any]]
    days[2]["totals"] = [
      "source": "daily_snapshot", "kcal": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0,
    ]
    raw["observed_at"] = "2026-11-04T15:00:02.000000Z"
    raw["source_version"] = String(repeating: "c", count: 64)
    days[2]["day_version"] = raw["observed_at"]
    raw["days"] = days
    let provider = NutritionWindowTestProvider([before, try f.snapshot(raw)])
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: before.authUserID)
    await model.load(revision: 0)
    await model.load(revision: 1)
    #expect(model.selectedDay?.meals.isEmpty == true && model.selectedDay?.totals.kcal == 0)
    #expect(model.selectedDay?.planned.meals.count == 1)
  }
  @Test func unavailableRefreshClearsThePreviousVisibleNumbersAndCanRetry() async throws {
    let f = try NutritionWindowFixture()
    let snapshot = try f.snapshot()
    let provider = NutritionWindowFailingProvider(value: snapshot)
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: snapshot.authUserID)
    await model.load(revision: 0)
    #expect(model.snapshot != nil)
    await model.load(revision: 1)
    #expect(model.snapshot == nil && model.phase == .unavailable)
    await model.load(revision: 1)
    #expect(model.snapshot?.sourceVersion == snapshot.sourceVersion)
  }
  @Test func weekNavigationRequestsAnOfficialCivilDateAndTodayNeverUsesTheDeviceClock() async throws
  {
    let f = try NutritionWindowFixture()
    let snapshot = try f.snapshot()
    let provider = NutritionWindowTestProvider([
      snapshot, try f.emptyWeek(start: "2026-11-09"), try f.emptyWeek(start: "2026-11-02"),
      snapshot,
    ])
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: snapshot.authUserID)
    await model.load(revision: 0)
    await model.shiftWeek(1, revision: 0)
    #expect(model.snapshot?.weekStart == "2026-11-09")
    await model.shiftWeek(-1, revision: 0)
    #expect(model.snapshot?.weekStart == "2026-11-02")
    await model.showToday(revision: 0)
    #expect(await provider.dates == [nil, "2026-11-09", "2026-11-02", nil])
  }
  @Test func aResponseForAnotherRequestedDayCannotBecomeVisible() async throws {
    let f = try NutritionWindowFixture()
    let snapshot = try f.snapshot()
    let provider = NutritionWindowTestProvider([snapshot])
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: snapshot.authUserID)
    await model.load(revision: 0)
    await model.shiftWeek(1, revision: 0)
    #expect(model.snapshot == nil && model.phase == .unavailable)
  }
  @Test func sameOwnerScopeChangeHidesOldValuesThenRequiresAnExplicitFreshLeaseRebind() async throws
  {
    let f = try NutritionWindowFixture()
    let original = try f.snapshot()
    var raw = try f.raw()
    raw["epoch"] = "abbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    raw["timezone"] = "America/Fortaleza"
    raw["observed_at"] = "2026-11-04T15:00:01.000000Z"
    let changed = try f.snapshot(raw)
    raw["observed_at"] = "2026-11-04T15:00:02.000000Z"
    let fresh = try f.snapshot(raw)
    let provider = NutritionScopeRebindingProvider(values: [original, changed], fresh: fresh)
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: original.authUserID)
    await model.load(revision: 0)
    await model.load(revision: 1)
    #expect(model.snapshot == nil && model.failure == .changed)
    #expect(await provider.rebindCalls == 0)
    await model.load(revision: 1)
    #expect(model.snapshot?.epoch == fresh.epoch && model.snapshot?.timezone == fresh.timezone)
    #expect(await provider.rebindCalls == 1)
  }
  @Test func foreignOwnerNeverAcquiresTheSameSessionRebindCapability() async throws {
    let f = try NutritionWindowFixture()
    let original = try f.snapshot()
    var raw = try f.raw()
    raw["owner_id"] = "accccccc-cccc-4ccc-8ccc-cccccccccccc"
    raw["observed_at"] = "2026-11-04T15:00:01.000000Z"
    let foreign = try f.snapshot(raw)
    let provider = NutritionScopeRebindingProvider(values: [original, foreign], fresh: foreign)
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: original.authUserID)
    await model.load(revision: 0)
    await model.load(revision: 1)
    await model.load(revision: 1)
    #expect(model.snapshot == nil && model.failure == .changed)
    #expect(await provider.rebindCalls == 0)
  }
  @Test func anOldSuspendedResponseCannotReplaceTheExplicitlyReboundScope() async throws {
    let f = try NutritionWindowFixture()
    let original = try f.snapshot()
    var raw = try f.raw()
    raw["epoch"] = "abbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    raw["observed_at"] = "2026-11-04T15:00:01.000000Z"
    let changed = try f.snapshot(raw)
    raw["observed_at"] = "2026-11-04T15:00:02.000000Z"
    let fresh = try f.snapshot(raw)
    let barrier = ConversationControllerBarrier()
    let provider = NutritionLateScopeProvider(
      original: original, changed: changed, fresh: fresh, barrier: barrier)
    let model = NutritionWindowModel(provider: provider, expectedAuthUserID: original.authUserID)
    await model.load(revision: 0)
    let old = Task { await model.load(revision: 1) }
    #expect(await barrier.waitEnteredOrFinished())
    await model.load(revision: 2)
    #expect(model.snapshot == nil)
    await model.load(revision: 3)
    #expect(model.snapshot?.epoch == fresh.epoch)
    await barrier.release()
    await old.value
    #expect(model.snapshot?.epoch == fresh.epoch && model.snapshot?.observedAt == fresh.observedAt)
  }
  @Test func actualScopedAdapterUsesOnlyTheClosedReadQueryAndWithholdsForeignAuth() async throws {
    let f = try NutritionWindowFixture()
    let snapshot = try f.snapshot()
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(
        userID: snapshot.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-nutrition"))
    let http = try ConversationHTTPFixture(lifecycle: life)
    let body = try f.envelope()
    await http.stub.respond { _, _ in .init(status: 200, body: body) }
    let repository = try await MobileNutritionWindowRepository.scoped(
      transport: http.transport, lifecycle: life, lease: await life.leaseForRequest())
    let result = try await repository.nutritionWindow(date: "2026-11-04")
    #expect(result.sourceVersion == snapshot.sourceVersion)
    let rebound = try await repository.rebindNutritionWindow(.init(snapshot), date: "2026-11-04")
    #expect(rebound.sourceVersion == snapshot.sourceVersion)
    let request = try #require(await http.stub.requests.first)
    #expect(request.httpMethod == "GET" && request.httpBody == nil)
    #expect(request.url?.path == "/api/mobile/v1/nutrition/window")
    let url = try #require(request.url)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(Set(query.map(\.name)) == ["date", "clinical_policy"])
    var foreign = try f.raw()
    foreign["auth_user_id"] = UUID().uuidString.lowercased()
    let wrongBody = try f.envelope(foreign)
    await http.stub.respond { _, _ in .init(status: 200, body: wrongBody) }
    await #expect(throws: (any Error).self) { try await repository.nutritionWindow(date: nil) }
    let requestsBefore = await http.stub.requests.count
    await life.replace(
      .init(
        userID: snapshot.authUserID.uuidString.lowercased(), generation: 8,
        bearer: "different-session"))
    await #expect(throws: (any Error).self) {
      try await repository.rebindNutritionWindow(.init(snapshot), date: nil)
    }
    #expect(await http.stub.requests.count == requestsBefore)
  }
}

struct NutritionWindowFixture {
  let data: Data
  init() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "NutritionWindowControlledFixture", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/NutritionWindowControlledFixture.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    data = try JSONSerialization.data(withJSONObject: #require(root["window"]))
  }
  func raw() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  func snapshot(_ raw: [String: Any]? = nil) throws -> NutritionWindowSnapshot {
    try .init(data: raw.map { try JSONSerialization.data(withJSONObject: $0) } ?? data)
  }
  func envelope(_ raw: [String: Any]? = nil) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "data": raw ?? self.raw(),
      "meta": ["api_version": "v1", "request_id": "controlled-nutrition-read"],
    ])
  }
  func emptyWeek(start: String) throws -> NutritionWindowSnapshot {
    var raw = try self.raw()
    let days = try #require(raw["days"] as? [[String: Any]])
    raw["week_start"] = start
    raw["week_end"] = NutritionCivilDate.add(start, days: 6)
    raw["selected_local_date"] = start
    raw["days"] = (0..<7).map { offset -> [String: Any] in
      var day = days[0]
      day["local_date"] = NutritionCivilDate.add(start, days: offset)
      return day
    }
    return try snapshot(raw)
  }
  func corrected() throws -> NutritionWindowSnapshot {
    var raw = try self.raw()
    var days = try #require(raw["days"] as? [[String: Any]])
    raw["observed_at"] = "2026-11-04T15:00:01.000000Z"
    raw["source_version"] = String(repeating: "b", count: 64)
    var meals = try #require(days[2]["meals"] as? [[String: Any]])
    meals[0]["id"] = "a9999999-9999-4999-8999-999999999999"
    meals[0]["quantity_g"] = 200
    meals[0]["kcal"] = 256.6
    meals[0]["protein_g"] = 5.04
    meals[0]["carbs_g"] = 56.12
    meals[0]["fat_g"] = 0.46
    days[2]["meals"] = meals
    var totals = try #require(days[2]["totals"] as? [String: Any])
    totals["kcal"] = 449
    totals["protein_g"] = 8.82
    totals["carbs_g"] = 98.21
    totals["fat_g"] = 0.805
    days[2]["totals"] = totals
    days[2]["day_version"] = raw["observed_at"]
    raw["days"] = days
    return try snapshot(raw)
  }
}
private actor NutritionWindowTestProvider: NutritionWindowProviding {
  let values: [NutritionWindowSnapshot]
  private(set) var calls = 0
  private(set) var dates: [String?] = []
  init(_ values: [NutritionWindowSnapshot]) { self.values = values }
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    dates.append(date)
    defer { calls += 1 }
    return values[min(calls, values.count - 1)]
  }
}
private actor NutritionWindowBlockingProvider: NutritionWindowProviding {
  let old: NutritionWindowSnapshot, new: NutritionWindowSnapshot
  let barrier: ConversationControllerBarrier
  private var calls = 0
  init(
    old: NutritionWindowSnapshot, new: NutritionWindowSnapshot,
    barrier: ConversationControllerBarrier
  ) {
    self.old = old
    self.new = new
    self.barrier = barrier
  }
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    calls += 1
    if calls == 1 {
      await barrier.enter()
      return old
    }
    return new
  }
}
@MainActor private final class NutritionWindowTestScope { var active = true }

private actor NutritionWindowFailingProvider: NutritionWindowProviding {
  let value: NutritionWindowSnapshot
  var count = 0
  init(value: NutritionWindowSnapshot) { self.value = value }
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    count += 1
    if count == 2 { throw BodyFlowCapabilityError.serviceUnavailable }
    return value
  }
}

private actor NutritionScopeRebindingProvider: NutritionWindowProviding {
  let values: [NutritionWindowSnapshot]
  let fresh: NutritionWindowSnapshot
  var reads = 0
  private(set) var rebindCalls = 0
  init(values: [NutritionWindowSnapshot], fresh: NutritionWindowSnapshot) {
    self.values = values
    self.fresh = fresh
  }
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    defer { reads += 1 }
    return values[min(reads, values.count - 1)]
  }
  func rebindNutritionWindow(_ reference: NutritionWindowReadReference, date: String?) async throws
    -> NutritionWindowSnapshot
  {
    rebindCalls += 1
    guard reference.ownerID == fresh.ownerID else { throw MobileAPITransportError.invalidResponse }
    return fresh
  }
}

private actor NutritionLateScopeProvider: NutritionWindowProviding {
  let original: NutritionWindowSnapshot, changed: NutritionWindowSnapshot,
    fresh: NutritionWindowSnapshot
  let barrier: ConversationControllerBarrier
  var reads = 0
  init(
    original: NutritionWindowSnapshot, changed: NutritionWindowSnapshot,
    fresh: NutritionWindowSnapshot, barrier: ConversationControllerBarrier
  ) {
    self.original = original
    self.changed = changed
    self.fresh = fresh
    self.barrier = barrier
  }
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    reads += 1
    if reads == 1 { return original }
    if reads == 2 {
      await barrier.enter()
      return original
    }
    return changed
  }
  func rebindNutritionWindow(_ reference: NutritionWindowReadReference, date: String?) async throws
    -> NutritionWindowSnapshot
  { fresh }
}
