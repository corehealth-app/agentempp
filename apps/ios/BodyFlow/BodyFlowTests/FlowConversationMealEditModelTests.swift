import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Actual Flow item editor preserves one original operation")
@MainActor
struct FlowConversationMealEditModelTests {
  @Test(arguments: [false, true])
  func coldRestoredACKRefreshesOfficialReadersEvenWhileJournalIsUnavailable(_ knownConflict: Bool)
    async throws
  {
    let f = try FlowEditUIFixture()
    let report = try OutboxDiskFixture()
    defer {
      f.base.disk.remove()
      report.remove()
    }
    await f.base.seedKey()
    let keys = OutboxKeychainFake()
    await keys.seed(report.key.withUnsafeBytes { Data($0) }, owner: f.base.disk.owner.hash)
    let operation = f.base.preparedOperation
    if knownConflict {
      let conflicting = try ConversationMealCommand(
        commandID: operation.commandID, source: .text("different immutable original source"))
      #expect(conflicting.inputHash != operation.originalInputHash)
      try report.store.update(owner: f.base.disk.owner, key: report.key) {
        $0.append(
          .init(
            command: conflicting, originalServerEpoch: f.group.epoch,
            originalPatientOwnerID: f.group.ownerID))
      }
    }
    let oldSession = try await f.base.session()
    let id = try await oldSession.enqueue(operation: operation, server: f.base.context.observation)
    let ticket = try await oldSession.prepareDispatch(id: id, server: f.base.context.observation)
    try await oldSession.markWaiting(ticket: ticket, hold: .unknownOutcome)
    await oldSession.invalidate()
    let wire = try ConversationControllerWireFixture()
    await f.base.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true {
        return try wire.sessionReply(epoch: f.group.epoch)
      }
      if request.url?.path.hasSuffix("/journal") == true { throw URLError(.networkConnectionLost) }
      return .init(status: 200, body: f.base.preparedSaved)
    }
    let model = try await FlowConversationModel.open(
      transport: f.base.http.transport, lifecycle: f.base.http.lifecycle,
      store: report.store, keyVault: .init(service: "synthetic", security: keys),
      editing: .init(store: f.base.disk.store, keyVault: f.base.vault))
    await model.loadHistory()
    #expect(
      model.historyUnavailable && model.savedRows.isEmpty
        && model.pendingRows.isEmpty == !knownConflict)
    let editor = try #require(model.mealEditor)
    #expect(editor.pendingEntries.count == 1 && editor.heldCount == 0)
    try editor.presentPending(id: .init(operation: operation))
    await editor.reconcile()
    #expect(
      editor.lastSaved?.receipt.operationID == operation.operationID
        && editor.pendingOperation == nil)
    #expect(
      model.savedEffectRevision == (knownConflict ? 0 : 1)
        && model.knownEditRevision(commandID: operation.commandID) == (knownConflict ? 0 : 1))
    #expect(model.savedRows.isEmpty)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    let mutations = await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(mutations.count == 1 && mutations[0].url?.path.hasSuffix("/reconcile") == true)
    #expect(mutations.first?.httpBody == operation.wireBody)
    await model.close()
  }
  @Test func factoryDoesNotReturnTheOldFeatureAfterLogoutDuringItsInitialEditorSnapshot()
    async throws
  {
    let f = try FlowEditUIFixture()
    let report = try OutboxDiskFixture()
    defer {
      f.base.disk.remove()
      report.remove()
    }
    let wire = try ConversationControllerWireFixture()
    await f.base.seedKey()
    let keys = OutboxKeychainFake()
    await keys.seed(report.key.withUnsafeBytes { Data($0) }, owner: f.base.disk.owner.hash)
    await f.base.http.stub.respond { _, _ in try wire.sessionReply() }
    let barrier = ConversationControllerBarrier()
    let lifecycle = FlowEditorOpeningLifecycle(
      base: f.base.http.lifecycle, gate: .init(barrier: barrier))
    let work = Task {
      try await FlowConversationModel.open(
        transport: f.base.http.transport, lifecycle: lifecycle,
        store: report.store, keyVault: .init(service: "synthetic", security: keys),
        editing: .init(store: f.base.disk.store, keyVault: f.base.vault))
    }
    #expect(await barrier.waitEnteredOrFinished())
    await f.base.http.lifecycle.replace(
      .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-replaced-during-open"))
    await barrier.release()
    await #expect(throws: (any Error).self) { try await work.value }
    #expect(await f.base.http.lifecycle.workCount == 0)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
  }
  @Test func failedUndoPreparationNeverBecomesAnEmptyEditableFoodForm() async throws {
    let f = try FlowEditUIFixture()
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let model = try await openEditor(f)
    await model.undoRegistration(group: f.group)
    #expect(!model.isItemForm && model.pendingOperation == nil)
    if case .undoRegistration = model.formAction {
    } else {
      Issue.record("Keep the selected Undo action")
    }
    #expect(
      !model.canSave(language: .englishUnitedStates) && !model.canCheckStatus
        && model.failure == .offline)
    #expect(await f.base.http.stub.requests.count == 1 && model.lastSaved == nil)
    model.dismiss()
    #expect(model.presentation == nil && model.canBeginEditing)
    await model.close()
  }
  @Test func preparationLocksFieldsBeforeItsFirstAwait() async throws {
    let f = try FlowEditUIFixture("milk")
    defer { f.base.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" {
        await barrier.enter()
        return .init(status: 200, body: f.groupBody)
      }
      return try f.savedReply(request)
    }
    let model = try await openEditor(f)
    try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    model.setQuantityText("250", language: .englishUnitedStates)
    let name = model.foodName
    let pending = Task { await model.save(language: .englishUnitedStates) }
    #expect(await barrier.waitEnteredOrFinished())
    #expect(model.isLocked && model.pendingOperation == nil)
    model.foodName = "replaced during current group GET"
    model.setQuantityText("999", language: .englishUnitedStates)
    model.toggleQuantityUnit(language: .englishUnitedStates)
    #expect(
      model.foodName == name && model.quantityText(language: .englishUnitedStates) == "250"
        && model.quantityUnit == "mL")
    await barrier.release()
    await pending.value
    #expect(model.lastSaved != nil)
    let post = try #require(await f.base.http.stub.requests.last)
    if case .save(_, let items) = try f.operation(post).action {
      #expect(items.first?.quantityG == Decimal(string: "257.5") && items.first?.foodName == name)
    } else {
      Issue.record("Original authored item required")
    }
    await model.close()
  }
  @Test func undoRegistrationUsesTheActualAllowedActionAndNoMealConfirmation() async throws {
    let f = try FlowEditUIFixture()
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      request.httpMethod == "GET"
        ? .init(status: 200, body: f.groupBody) : try f.savedReply(request)
    }
    let model = try await openEditor(f)
    await model.undoSave(group: f.group)
    #expect(await f.base.http.stub.requests.isEmpty)
    await model.undoRegistration(group: f.group)
    #expect(model.lastSaved?.receipt.kind == .registrationUndone && model.pendingOperation == nil)
    let posts = await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1)
    if case .undoRegistration = try f.operation(#require(posts.first)).action {
    } else {
      Issue.record("Only the exact allowed Undo registration action may be sent")
    }
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    await model.close()
  }
  @Test func undoSavePinsTheActualLastOperationAndRechecksItsServerCAS() async throws {
    let actual = try FlowActualEditLifecycleFixture()
    let disk = try EditOutboxFixture()
    defer { disk.remove() }
    struct Envelope: Decodable { let data: ConversationMealGroupSnapshot }
    let group = try JSONDecoder().decode(Envelope.self, from: actual.groupEnvelope).data
    let life = ConversationHTTPTestLifecycle()
    await life.replace(.init(userID: actual.authUserID, generation: 7, bearer: "synthetic-ui-undo"))
    let lease = await life.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let keys = OutboxKeychainFake()
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    let http = try ConversationHTTPFixture(lifecycle: life)
    await http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: actual.groupEnvelope) }
      let op = try ConversationMealEditOperation(
        ownerID: group.ownerID, commandID: group.commandID,
        originalInputHash: group.originalInputHash, epoch: group.epoch,
        operationID: #require(
          UUID(uuidString: String(request.url!.path.split(separator: "/").last!))),
        wireBody: #require(request.httpBody))
      if case .undoSave(let target) = op.action {
        #expect(target == group.lastOperation?.operationID)
      } else {
        Issue.record("The selected Undo Save target must be preserved")
      }
      return try controlledFlowEditSavedReply(operation: op)
    }
    let authority = ConversationOutboxObservationAuthority()
    let token = try authority.beginRefresh()
    let context = ConversationCommandContext(
      observation: try authority.accept(
        refreshID: token,
        authUserID: #require(UUID(uuidString: actual.authUserID)), ownerID: group.ownerID,
        localSessionGeneration: 7, epoch: group.epoch), observedAt: actual.session.observedAt)
    let controller = try await ConversationMealEditController.open(
      transport: http.transport, lifecycle: life,
      store: disk.store,
      keyVault: .init(service: ConversationMealEditOutboxSession.keychainService, security: keys))
    let model = try await FlowConversationMealEditModel.open(
      controller: controller, lifecycle: life, lease: lease
    ) { _, _ in }
    model.accept(context)
    await model.undoRegistration(group: group)
    #expect(await http.stub.requests.isEmpty)
    await model.undoSave(group: group)
    #expect(model.lastSaved?.receipt.kind == .saveUndone && model.lastSaved?.receipt.revision == 8)
    #expect(model.lastSaved?.receipt.targetOperationID == group.lastOperation?.operationID)
    #expect(await http.stub.requests.count == 2)
    #expect(try disk.store.load(owner: owner, key: disk.key).isEmpty)
    await model.close()
  }
  @Test(arguments: [true, false])
  func journalCanRecoverOnlyAnAlreadyClosedDeliveryNotAStillEncryptedOperation(_ closed: Bool)
    async throws
  {
    let f = try FlowEditUIFixture("milk")
    defer { f.base.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      if !closed { throw URLError(.networkConnectionLost) }
      await f.base.http.lifecycle.holdNextVisible(barrier)
      return try f.savedReply(request)
    }
    let model = try await openEditor(f)
    try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    model.setQuantityText("250", language: .englishUnitedStates)
    let work = Task { await model.save(language: .englishUnitedStates) }
    if closed {
      #expect(await barrier.waitEnteredOrFinished())
      #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
      work.cancel()
      await barrier.release()
    }
    await work.value
    let original = try #require(model.pendingOperation)
    #expect(model.lastSaved == nil)
    await model.restore()
    let before = try Data(contentsOf: f.base.disk.store.fileURL(owner: f.base.disk.owner))
    let journal = try f.journalReply(original)
    await f.base.http.stub.respond { _, _ in journal }
    let repository = try await MobileConversationHistoryRepository.scoped(
      transport: f.base.http.transport,
      lifecycle: f.base.http.lifecycle, lease: await f.base.http.lifecycle.leaseForRequest())
    let read = try await repository.journal(context: f.base.context)
    model.observeJournal(read)
    #expect((model.pendingOperation == nil) == closed)
    #expect((model.lastSaved != nil) == closed)
    #expect(try Data(contentsOf: f.base.disk.store.fileURL(owner: f.base.disk.owner)) == before)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
  #if canImport(UIKit)
    @Test(arguments: [true, false])
    func nativeItemPencilsRequireTheActualDependencyAndServerAllowedActions(_ enabled: Bool) throws
    {
      let f = try FlowEditUIFixture()
      defer { f.base.disk.remove() }
      let actions = FlowConversationMealEditActions(
        editItem: { _ in }, undoSave: { _ in }, undoRegistration: { _ in }, isWorking: false)
      let host = SignUpRenderingProbe.host(
        FlowConversationMealGroupView(group: f.group, editing: enabled ? actions : nil)
          .environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 900)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      #expect(
        nodes.contains { $0.identifier.hasPrefix("conversation.meal.edit.") } == enabled, diagnostic
      )
      #expect(
        nodes.contains { $0.identifier == "conversation.meal.undo-registration" } == enabled,
        diagnostic)
      #expect(!nodes.contains { $0.identifier == "conversation.meal.undo-save" }, diagnostic)
    }
    @Test func nativePrimarySixRemainVisibleBesideTheQualifiedItemActions() throws {
      let f = try ConversationMealPrimaryFeedbackPolicyTests.Fixture()
      let group = try f.group()
      let row = FlowConversationSavedRow(
        command: f.actual.command, receipt: f.saved.receipt, feedback: f.feedback)
      let actions = FlowConversationMealEditActions(
        editItem: { _ in }, undoSave: { _ in }, undoRegistration: { _ in }, isWorking: false)
      let host = SignUpRenderingProbe.host(
        FlowConversationSavedMealResponseView(
          row: row, group: group,
          scope: f.scope, editing: actions, refresh: {}
        ).environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 2800)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      #expect(
        Set(
          nodes.filter { $0.identifier.hasPrefix("conversation.feedback.section.") }.map(
            \.identifier)
        ).count == 6, diagnostic)
      #expect(nodes.contains { $0.identifier.hasPrefix("conversation.meal.edit.") }, diagnostic)
      #expect(!nodes.contains { $0.identifier == "conversation.meal.original-history" }, diagnostic)
    }
    @Test(arguments: ["milk", "whey"])
    func nativeEditorShowsTheQualifiedUnitAndDirectSaveWithoutManualCalories(_ kind: String)
      async throws
    {
      let f = try FlowEditUIFixture(kind)
      defer { f.base.disk.remove() }
      let model = try await openEditor(f)
      try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
      model.setQuantityText(kind == "milk" ? "250.5" : "1.5", language: .englishUnitedStates)
      let host = SignUpRenderingProbe.host(
        FlowConversationMealEditorContent(model: model)
          .environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 900)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      // NATIVE-1 reproduced the existing in-process AX walker limitation:
      // SwiftUI UITextField identifiers are not exposed. Read the actual
      // native controls and exercise editingChanged, without guessing IDs
      // from their traversal order or weakening the value/binding contract.
      let live = PremiumRenderingTestSupport.liveAccessibilityHost(
        FlowConversationMealEditorContent(model: model).environment(
          \.locale, Locale(identifier: "en_US")), width: 390)
      defer { live.detach() }
      let fields = live.nativeViews(UITextField.self)
      #expect(fields.count == 2)
      let quantity = try #require(fields.first { $0.keyboardType == .decimalPad })
      let name = try #require(fields.first { $0.keyboardType != .decimalPad })
      #expect(
        name.text == model.foodName && name.isEnabled && name.bounds.width > 0
          && name.bounds.height > 0)
      #expect(
        quantity.text == (kind == "milk" ? "250.5" : "1.5") && quantity.isEnabled
          && quantity.bounds.width > 0 && quantity.bounds.height > 0)
      quantity.text = kind == "milk" ? "275.5" : "1.75"
      quantity.sendActions(for: .editingChanged)
      live.settle()
      #expect(
        model.quantityText(language: .englishUnitedStates) == quantity.text
          && model.canSave(language: .englishUnitedStates))
      #expect(
        nodes.contains {
          $0.identifier == "conversation.edit.unit" && $0.label == (kind == "milk" ? "mL" : "scoop")
        }, diagnostic)
      #expect(
        nodes.contains { $0.identifier == "conversation.edit.save" && $0.isButton && $0.isEnabled },
        diagnostic)
      #expect(
        !nodes.contains {
          $0.label.lowercased().contains("kcal") || $0.identifier.contains("meal-selector")
        }, diagnostic)
      await model.close()
    }
    @Test func nativeUncertainEditorExposesOriginalReadOnlyFieldsAndReconciliationOnly()
      async throws
    {
      let f = try FlowEditUIFixture("milk")
      defer { f.base.disk.remove() }
      await f.base.http.stub.respond { request, _ in
        if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
        throw URLError(.networkConnectionLost)
      }
      let model = try await openEditor(f)
      try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
      model.setQuantityText("250.5", language: .englishUnitedStates)
      let name = model.foodName
      await model.save(language: .englishUnitedStates)
      let host = SignUpRenderingProbe.host(
        FlowConversationMealEditorContent(model: model)
          .environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 900)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      let live = PremiumRenderingTestSupport.liveAccessibilityHost(
        FlowConversationMealEditorContent(model: model).environment(
          \.locale, Locale(identifier: "en_US")), width: 390)
      defer { live.detach() }
      #expect(live.nativeViews(UITextField.self).isEmpty)
      #expect(
        nodes.contains { $0.identifier == "conversation.edit.locked-name" && $0.label == name },
        diagnostic)
      #expect(
        nodes.contains {
          $0.identifier == "conversation.edit.locked-quantity" && $0.label == "250.5 mL"
        }, diagnostic)
      #expect(
        nodes.contains { $0.identifier == "conversation.edit.reconcile" && $0.isEnabled },
        diagnostic)
      #expect(
        !nodes.contains {
          [
            "conversation.edit.name", "conversation.edit.quantity", "conversation.edit.save",
            "conversation.edit.discard", "conversation.edit.resubmit",
          ].contains($0.identifier)
        }, diagnostic)
      await model.close()
    }
  #endif
  @Test func restartRestoresTheExactUnknownOperationWithoutCreatingOrSendingAnotherEdit()
    async throws
  {
    let f = try FlowEditUIFixture("whey")
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      throw URLError(.networkConnectionLost)
    }
    let first = try await openEditor(f)
    try first.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    first.setQuantityText("1.5", language: .englishUnitedStates)
    await first.save(language: .englishUnitedStates)
    let original = try #require(first.pendingOperation)
    await first.close()
    let second = try await openEditor(f)
    await second.restore()
    #expect(!second.canBeginEditing)
    #expect(second.pendingEntries.count == 1 && second.pendingOperation == nil)
    try second.presentPending(id: .init(operation: original))
    #expect(second.isLocked && second.pendingOperation?.operationID == original.operationID)
    #expect(second.pendingOperation?.wireBody == original.wireBody)
    #expect(second.pendingItems.first?.grams == 45 && second.quantityUnit == "g")
    #expect(!second.canSave(language: .englishUnitedStates) && !second.canDiscardUnsent)
    #expect(await f.base.http.stub.requests.count == 2)
    await f.base.http.stub.respond { request, _ in try f.savedReply(request) }
    await second.reconcile()
    #expect(
      second.lastSaved?.receipt.operationID == original.operationID
        && second.pendingOperation == nil)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    #expect(
      await f.base.http.stub.requests.filter { $0.url?.path.hasSuffix("/reconcile") == true }.count
        == 1)
    await second.close()
  }
  @Test(arguments: ["patient", "epoch", "logout"])
  func invalidatedScopeImmediatelyHidesTheFormAndPreservesEncryptedUnknownWork(_ change: String)
    async throws
  {
    let f = try FlowEditUIFixture("milk")
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      throw URLError(.networkConnectionLost)
    }
    let model = try await openEditor(f)
    try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    model.setQuantityText("250", language: .englishUnitedStates)
    await model.save(language: .englishUnitedStates)
    let before = try Data(contentsOf: f.base.disk.store.fileURL(owner: f.base.disk.owner))
    if change == "logout" {
      await f.base.http.lifecycle.replace(
        .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-next-account"))
    } else {
      let token = try f.base.authority.beginRefresh()
      let observation = try f.base.authority.accept(
        refreshID: token, authUserID: f.base.context.authUserID,
        ownerID: change == "patient" ? UUID() : f.base.context.ownerID,
        localSessionGeneration: f.base.context.sessionGeneration,
        epoch: change == "epoch" ? UUID() : f.base.context.epoch)
      #expect(model.foodName.isEmpty && model.pendingOperation == nil && model.presentation == nil)
      model.accept(.init(observation: observation, observedAt: f.base.context.observedAt))
      await model.restore()
      #expect(model.heldCount == 1 && model.pendingEntries.isEmpty)
    }
    #expect(model.foodName.isEmpty && model.quantityText(language: .englishUnitedStates).isEmpty)
    #expect(model.pendingOperation == nil && model.presentation == nil && model.lastSaved == nil)
    #expect(try Data(contentsOf: f.base.disk.store.fileURL(owner: f.base.disk.owner)) == before)
    #expect(await f.base.http.stub.requests.count == 2)
    await model.close()
  }
  @Test func explicitUnsentDiscardIsExactAndANewEditRequiresANewPreparation() async throws {
    let f = try FlowEditUIFixture("milk")
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      request.httpMethod == "GET"
        ? .init(status: 200, body: f.groupBody) : try f.savedReply(request)
    }
    let model = try await openEditor(f)
    let item = try #require(f.group.current?.items.first)
    try model.beginEditing(group: f.group, itemID: item.id)
    #expect(!model.canBeginEditing)
    model.setQuantityText("250", language: .englishUnitedStates)
    try FileManager.default.createDirectory(
      at: f.base.disk.store.root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.base.disk.store.root.path)
    await model.save(language: .englishUnitedStates)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.base.disk.store.root.path)
    let original = try #require(model.pendingOperation)
    await model.discardUnsent(id: .init(commandID: original.commandID, operationID: UUID()))
    #expect(model.pendingOperation?.operationID == original.operationID)
    await model.discardUnsent(id: .init(operation: original))
    #expect(model.pendingOperation == nil && model.presentation == nil && model.canBeginEditing)
    try model.beginEditing(group: f.group, itemID: item.id)
    model.setQuantityText("260", language: .englishUnitedStates)
    await model.save(language: .englishUnitedStates)
    #expect(model.lastSaved?.receipt.operationID != original.operationID)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "GET" }.count == 2)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
  @Test func flowOwnsActualEditorAndKeepsFactualACKWhenCurrentRefreshFails() async throws {
    let actual = try FlowActualEditLifecycleFixture()
    let report = try OutboxDiskFixture()
    let edit = try EditOutboxFixture()
    defer {
      report.remove()
      edit.remove()
    }
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(userID: actual.authUserID, generation: 7, bearer: "synthetic-ui-integration"))
    let lease = await life.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let reportKeys = OutboxKeychainFake()
    let editKeys = OutboxKeychainFake()
    await reportKeys.seed(report.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    await editKeys.seed(edit.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    try report.store.update(owner: owner, key: report.key) {
      $0.append(
        .init(
          command: actual.command, originalServerEpoch: actual.session.epoch,
          originalPatientOwnerID: actual.session.ownerID))
    }
    let http = try ConversationHTTPFixture(lifecycle: life)
    let phase = FlowEditUIHTTPPhase()
    await http.stub.respond { request, _ in
      let path = request.url?.path ?? ""
      if path.hasSuffix("/session") { return .init(status: 200, body: actual.sessionEnvelope) }
      if path.hasSuffix("/meal") {
        if await phase.saved { throw URLError(.networkConnectionLost) }
        return .init(status: 200, body: actual.groupEnvelope)
      }
      if path.contains("/edits/") {
        let op = try ConversationMealEditOperation(
          ownerID: actual.session.ownerID,
          commandID: actual.command.commandID, originalInputHash: actual.command.inputHash,
          epoch: actual.session.epoch,
          operationID: #require(UUID(uuidString: String(path.split(separator: "/").last!))),
          wireBody: #require(request.httpBody))
        await phase.markSaved()
        return try controlledFlowEditSavedReply(operation: op)
      }
      return .init(status: 200, body: actual.savedEnvelope)
    }
    let model = try await FlowConversationModel.open(
      transport: http.transport, lifecycle: life,
      store: report.store, keyVault: .init(service: "synthetic", security: reportKeys),
      editing: .init(
        store: edit.store,
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: editKeys)))
    await model.sendQueued(commandID: actual.command.commandID)
    let original = try #require(model.savedRows.first)
    let originalRevision = model.savedEffectRevision
    await model.loadCurrentGroup(commandID: original.id)
    let group = try #require(model.currentGroup(commandID: original.id))
    let item = try #require(group.current?.items.first(where: { $0.foodName.contains("whey") }))
    await model.beginMealEdit(commandID: original.id, itemID: item.id)
    let editor = try #require(model.mealEditor)
    #expect(editor.quantityUnit == "scoop")
    editor.toggleQuantityUnit(language: .englishUnitedStates)
    #expect(
      editor.quantityUnit == "g" && editor.quantityText(language: .englishUnitedStates) == "35")
    editor.setQuantityText("45", language: .englishUnitedStates)
    await editor.save(language: .englishUnitedStates)
    #expect(editor.lastSaved?.receipt.revision == 8 && editor.pendingOperation == nil)
    #expect(
      model.currentGroup(commandID: original.id) == nil
        && model.knownEditRevision(commandID: original.id) == 8)
    #expect(model.savedEffectRevision == originalRevision + 1)
    await model.loadCurrentGroup(commandID: original.id)
    #expect(model.groupUnavailable(commandID: original.id) && editor.lastSaved != nil)
    #expect(
      model.savedRows.first?.receipt == original.receipt
        && model.savedRows.first?.feedback == original.feedback)
    #expect(try edit.store.load(owner: owner, key: edit.key).isEmpty)
    #expect(await http.stub.requests.filter { $0.url?.path.contains("/edits/") == true }.count == 1)
    await model.close()
    #expect(model.mealEditor == nil && editor.foodName.isEmpty && editor.pendingOperation == nil)
    #expect(await life.workCount == 0)
  }
  @Test func lostOutcomeAllowsOnlyReadOnlyReconciliationThenOneExplicitSameBodyReplay() async throws
  {
    let f = try FlowEditUIFixture("whey")
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      throw URLError(.networkConnectionLost)
    }
    let controller = try await f.base.openController()
    let probe = FlowEditUIProbe()
    let model = try await FlowConversationMealEditModel.open(
      controller: controller,
      lifecycle: f.base.http.lifecycle, lease: await f.base.http.lifecycle.leaseForRequest()
    ) { result, context in
      probe.saved.append(result)
      probe.contexts.append(context.identity)
    }
    model.accept(f.base.context)
    try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    model.setQuantityText("1.5", language: .englishUnitedStates)
    await model.save(language: .englishUnitedStates)
    let original = try #require(model.pendingOperation)
    #expect(
      model.isLocked && !model.canSave(language: .englishUnitedStates) && !model.canDiscardUnsent)
    await model.save(language: .englishUnitedStates)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await f.base.http.stub.respond { request, _ in
      request.url?.path.hasSuffix("/reconcile") == true
        ? try f.absentReply(request) : try f.savedReply(request)
    }
    await model.reconcile()
    #expect(model.canResubmit)
    // Repeating the same current grant is not a refresh or new permission.
    model.accept(f.base.context)
    #expect(model.canResubmit)
    #expect(probe.saved.isEmpty)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 2)
    await model.resubmit()
    #expect(probe.saved.count == 1 && model.pendingOperation == nil)
    let posts = await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 3 && posts.allSatisfy { $0.httpBody == original.wireBody })
    #expect(
      posts.allSatisfy {
        $0.value(forHTTPHeaderField: "Idempotency-Key") == original.idempotencyKey
      })
    await model.resubmit()
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 3)
    await model.close()
  }
  @Test func cancellationDoesNotExposeStaleQueuedSnapshotAsPermissionToDiscardOrSendAgain()
    async throws
  {
    let f = try FlowEditUIFixture("milk")
    defer { f.base.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      await barrier.enter()
      throw URLError(.networkConnectionLost)
    }
    let controller = try await f.base.openController()
    let probe = FlowEditUIProbe()
    let model = try await FlowConversationMealEditModel.open(
      controller: controller,
      lifecycle: f.base.http.lifecycle, lease: await f.base.http.lifecycle.leaseForRequest()
    ) { result, context in
      probe.saved.append(result)
      probe.contexts.append(context.identity)
    }
    model.accept(f.base.context)
    try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    model.setQuantityText("250", language: .englishUnitedStates)
    let pending = Task { await model.save(language: .englishUnitedStates) }
    #expect(await barrier.waitEnteredOrFinished())
    let original = try #require(model.pendingOperation)
    pending.cancel()
    await barrier.release()
    await pending.value
    #expect(model.isLocked && model.pendingOperation?.wireBody == original.wireBody)
    #expect(!model.canDiscardUnsent)
    #expect(!model.canSave(language: .englishUnitedStates))
    #expect(probe.saved.isEmpty)
    #expect(
      try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).first?.state
        != .queued)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }

  @Test func failedEnqueueLocksAuthoredNameQuantityAndReusesExactlyOneOperation() async throws {
    let f = try FlowEditUIFixture("milk")
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      request.httpMethod == "GET"
        ? .init(status: 200, body: f.groupBody) : try f.savedReply(request)
    }
    let controller = try await f.base.openController()
    let probe = FlowEditUIProbe()
    let model = try await FlowConversationMealEditModel.open(
      controller: controller,
      lifecycle: f.base.http.lifecycle, lease: await f.base.http.lifecycle.leaseForRequest()
    ) { result, context in
      probe.saved.append(result)
      probe.contexts.append(context.identity)
    }
    model.accept(f.base.context)
    try model.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    model.setQuantityText("250,5", language: .portugueseBrazil)
    let originalName = model.foodName
    try FileManager.default.createDirectory(
      at: f.base.disk.store.root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.base.disk.store.root.path)
    await model.save(language: .portugueseBrazil)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.base.disk.store.root.path)
    let original = try #require(model.pendingOperation)
    #expect(model.isLocked && model.canDiscardUnsent && model.failure == .storage)
    #expect(!model.canCheckStatus)
    model.foodName = "new name must not replace original"
    model.setQuantityText("999", language: .portugueseBrazil)
    model.toggleQuantityUnit(language: .portugueseBrazil)
    #expect(
      model.foodName == originalName && model.quantityText(language: .portugueseBrazil) == "250,5")
    #expect(model.quantityUnit == "mL" && model.pendingOperation?.wireBody == original.wireBody)
    #expect(await f.base.http.stub.requests.count == 1)
    await model.save(language: .portugueseBrazil)
    #expect(probe.saved.count == 1)
    let posts = await f.base.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1 && posts[0].httpBody == original.wireBody)
    #expect(posts[0].value(forHTTPHeaderField: "Idempotency-Key") == original.idempotencyKey)
    #expect(await f.base.http.stub.requests.filter { $0.httpMethod == "GET" }.count == 1)
    await model.close()
  }
  @Test(arguments: ["milk", "whey"])
  func oneSaveUsesTheQualifiedAuthoredUnitAndNeedsNoMealReconfirmation(_ kind: String) async throws
  {
    let f = try FlowEditUIFixture(kind)
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      return try f.savedReply(request)
    }
    let controller = try await f.base.openController()
    let acknowledgements = FlowEditUIProbe()
    let model = try await FlowConversationMealEditModel.open(
      controller: controller,
      lifecycle: f.base.http.lifecycle, lease: await f.base.http.lifecycle.leaseForRequest()
    ) { result, context in
      acknowledgements.saved.append(result)
      acknowledgements.contexts.append(context.identity)
    }
    model.accept(f.base.context)
    let item = try #require(f.group.current?.items.first)
    try model.beginEditing(group: f.group, itemID: item.id)
    #expect(model.quantityUnit == (kind == "milk" ? "mL" : "scoop"))
    #expect(model.quantityText(language: .portugueseBrazil) == (kind == "milk" ? "200" : "1"))
    model.setQuantityText(kind == "milk" ? "250,5" : "1,5", language: .portugueseBrazil)
    #expect(model.canSave(language: .portugueseBrazil))
    await model.save(language: .portugueseBrazil)
    #expect(
      acknowledgements.saved.count == 1 && acknowledgements.contexts == [f.base.context.identity])
    #expect(model.presentation == nil && model.pendingOperation == nil)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    let requests = await f.base.http.stub.requests
    #expect(requests.count == 2 && requests.map(\.httpMethod) == ["GET", "POST"])
    let body = try #require(requests.last?.httpBody)
    let operation = try f.operation(requests.last!)
    guard case .save(let recordID, let items) = operation.action else {
      Issue.record("A direct item Save is required")
      return
    }
    #expect(recordID == item.id && items.count == 1)
    #expect(items[0].quantityG == (kind == "milk" ? Decimal(string: "258.015") : 45))
    #expect(items[0].quantityBasis == .portionReference && items[0].userKcal == nil)
    #expect(!String(decoding: body, as: UTF8.self).contains("user_kcal"))
    await model.close()
    #expect(await f.base.http.lifecycle.workCount == 0)
  }
}

private actor FlowEditorOpeningGate {
  let barrier: ConversationControllerBarrier
  private var count = 0
  init(barrier: ConversationControllerBarrier) { self.barrier = barrier }
  func armIfEditor(_ lifecycle: ConversationHTTPTestLifecycle) async {
    count += 1
    // Actual ownership registrations: report outbox/controller/feature,
    // then edit outbox/controller/editor. Block only the editor's first view.
    if count == 6 { await lifecycle.holdNextVisible(barrier) }
  }
}
private struct FlowEditorOpeningLifecycle: SessionLifecycleProviding {
  let base: ConversationHTTPTestLifecycle
  let gate: FlowEditorOpeningGate
  func currentBearerToken() async -> String? { await base.currentBearerToken() }
  func leaseForRequest() async throws -> SessionLease { await base.leaseForRequest() }
  func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
  func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
    try await base.refreshAfterUnauthorized(lease: lease)
  }
  func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
  func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws
    -> UUID
  {
    let id = try await base.beginPatientWork(lease: lease, cancel: cancel)
    await gate.armIfEditor(base)
    return id
  }
  func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
  func performPatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @Sendable () throws -> Value
  ) async throws -> Value {
    try await base.performPatientStateOperation(lease: lease, operation: operation)
  }
  func performVisiblePatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @MainActor @Sendable () throws -> Value
  ) async throws -> Value {
    try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
  }
}

@MainActor private func openEditor(_ f: FlowEditUIFixture) async throws
  -> FlowConversationMealEditModel
{
  let controller = try await f.base.openController()
  let model = try await FlowConversationMealEditModel.open(
    controller: controller,
    lifecycle: f.base.http.lifecycle, lease: await f.base.http.lifecycle.leaseForRequest()
  ) { _, _ in }
  model.accept(f.base.context)
  return model
}

private actor FlowEditUIHTTPPhase {
  private(set) var saved = false
  func markSaved() { saved = true }
}

private func controlledFlowEditSavedReply(operation: ConversationMealEditOperation) throws
  -> ConversationHTTPReply
{
  let f = try FlowActualEditLifecycleFixture()
  #if SWIFT_PACKAGE
    let url = try #require(
      Bundle.module.url(forResource: "FlowMealEditLifecycleFixtures", withExtension: "json"))
  #else
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "Fixtures/FlowMealEditLifecycleFixtures.json")
  #endif
  let raw = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  let key: String
  if case .undoSave = operation.action { key = "undo_ack" } else { key = "edit_ack" }
  var envelope = try #require(raw[key] as? [String: Any])
  var data = try #require(envelope["data"] as? [String: Any])
  var receipt = try #require(data["receipt"] as? [String: Any])
  receipt["operation_id"] = operation.operationID.uuidString.lowercased()
  receipt["input_hash"] = operation.operationInputHash
  receipt["revision"] = operation.expectedRevision + 1
  if case .save(let id, _) = operation.action {
    receipt["removed_item_ids"] = [id.uuidString.lowercased()]
    let newID = "70000000-0000-4000-8000-000000000001"
    receipt["new_item_ids"] = [newID]
    receipt["next_record_id"] = newID
  }
  data["receipt"] = receipt
  envelope["data"] = data
  #expect(f.command.commandID == operation.commandID)
  return .init(status: 200, body: try JSONSerialization.data(withJSONObject: envelope))
}

struct FlowEditUIFixture: Sendable {
  let base: EditControllerFixture
  let group: ConversationMealGroupSnapshot
  let groupBody: Data
  init(_ variant: String = "group") throws {
    base = try .init()
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditPublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditPublicFixtures.json")
    #endif
    let data = try Data(contentsOf: url)
    #expect(
      ConversationMealCommand.digest(data)
        == "da84f8538ded15873383dd38e3611db493e9f079d14742ec8f1c623354618f63")
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    groupBody = try JSONSerialization.data(withJSONObject: #require(raw[variant]))
    struct Envelope: Decodable { let data: ConversationMealGroupSnapshot }
    group = try JSONDecoder().decode(Envelope.self, from: groupBody).data
  }
  func operation(_ request: URLRequest) throws -> ConversationMealEditOperation {
    var path = try #require(request.url?.path.split(separator: "/"))
    if path.last == "reconcile" { path.removeLast() }
    let operationID = try #require(UUID(uuidString: String(path.last!)))
    return try .init(
      ownerID: group.ownerID, commandID: group.commandID,
      originalInputHash: group.originalInputHash, epoch: group.epoch, operationID: operationID,
      wireBody: #require(request.httpBody))
  }
  func absentReply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let operation = try operation(request)
    var envelope = try #require(JSONSerialization.jsonObject(with: base.absent) as? [String: Any])
    var data = try #require(envelope["data"] as? [String: Any])
    data["operation_id"] = operation.operationID.uuidString.lowercased()
    data["operation_input_hash"] = operation.operationInputHash
    envelope["data"] = data
    return .init(status: 200, body: try JSONSerialization.data(withJSONObject: envelope))
  }
  func journalReply(_ operation: ConversationMealEditOperation) throws -> ConversationHTTPReply {
    var request = URLRequest(
      url: URL(
        string:
          "https://unit.invalid/api/mobile/v1/conversation/meal-commands/\(operation.commandID.uuidString.lowercased())/edits/\(operation.operationID.uuidString.lowercased())"
      )!)
    request.httpBody = operation.wireBody
    let saved = try #require(
      JSONSerialization.jsonObject(with: savedReply(request).body) as? [String: Any])
    let result = try #require(saved["data"] as? [String: Any])
    let receipt = try #require(result["receipt"] as? [String: Any])
    let at = try #require(receipt["applied_at"] as? String)
    let page: [String: Any] = [
      "schema": "conversation.journal-page.v1",
      "auth_user_id": base.context.authUserID.uuidString.lowercased(),
      "owner_id": group.ownerID.uuidString.lowercased(),
      "epoch": group.epoch.uuidString.lowercased(), "observed_at": at,
      "items": [
        [
          "event_id":
            "edit/\(operation.commandID.uuidString.lowercased())/\(operation.operationID.uuidString.lowercased())",
          "kind": "edit", "at": at, "result": result,
        ]
      ],
      "has_more": false, "next_cursor": NSNull(),
    ]
    return .init(
      status: 200,
      body: try JSONSerialization.data(withJSONObject: [
        "data": page, "meta": ["api_version": "v1", "request_id": "unit-edit-delivery-recovery"],
      ]))
  }
  /// Controlled unit HTTP echo bound to the ACTUAL outgoing operation. This
  /// does not change any frozen fixture or claim a new SQL/server/native E2E.
  func savedReply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let operation = try operation(request)
    var envelope = try #require(JSONSerialization.jsonObject(with: base.saved) as? [String: Any])
    var data = try #require(envelope["data"] as? [String: Any])
    var receipt = try #require(data["receipt"] as? [String: Any])
    receipt["operation_id"] = operation.operationID.uuidString.lowercased()
    receipt["input_hash"] = operation.operationInputHash
    receipt["revision"] = operation.expectedRevision + 1
    if case .save(let recordID, _) = operation.action {
      receipt["removed_item_ids"] = [recordID.uuidString.lowercased()]
    } else if case .undoRegistration = operation.action {
      receipt["kind"] = "registration_undone"
      receipt["undo_expires_at"] = NSNull()
      receipt["target_operation_id"] = NSNull()
      receipt["new_item_ids"] = []
      receipt["next_record_id"] = NSNull()
    }
    data["receipt"] = receipt
    envelope["data"] = data
    return .init(status: 200, body: try JSONSerialization.data(withJSONObject: envelope))
  }
}
@MainActor final class FlowEditUIProbe {
  var saved: [ConversationMealEditResultSnapshot] = []
  var contexts: [ConversationCommandContext.Identity] = []
}
