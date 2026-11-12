import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
  @MainActor @Suite("Real neutral composer and factual transcript content")
  struct FlowNeutralIntakeRenderingTests {
    @Test(.serialized, arguments: [false, true])
    func actualCaptureSurvivesTemporaryRevalidationButClosesOnSessionInvalidation(_ camera: Bool)
      async throws
    {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let staging = MediaStagingStore(temporaryDirectory: f.disk.directory)
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault,
        media: .init(uploader: ConversationMediaUploaderProbe(), staging: staging),
        neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      let identity = try #require(model.captureContext)
      let permission = ConversationControllerBarrier()
      let access = MealCameraAccess(
        origin: .none, isAvailable: { false }, permission: { .notAsked },
        requestAccess: {
          await permission.enter()
          return false
        })
      let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
      let oldWindow = scene.windows.first(where: \.isKeyWindow)
      let window = UIWindow(windowScene: scene)
      let probe = NeutralCaptureSheetPresentationProbe()
      let root = UIHostingController(
        rootView:
          Text("Capture root").sheet(
            isPresented: Binding(
              get: { probe.isPresented }, set: { probe.isPresented = $0 })
          ) {
            FlowConversationCaptureView(
              capability: .init(stager: .init(staging: staging), camera: access),
              presentation: .init(
                choice: camera ? .camera : .recording, context: identity, neutral: true),
              model: model
            ).environment(\.locale, Locale(identifier: "pt_BR"))
              .environment(\.accessibilityEnabled, true)
          })
      window.rootViewController = root
      window.makeKeyAndVisible()
      for _ in 0..<40 {
        if root.presentedViewController != nil { break }
        try await Task.sleep(for: .milliseconds(15))
      }
      let capture = try #require(root.presentedViewController)
      defer {
        window.isHidden = true
        oldWindow?.makeKeyAndVisible()
      }
      if camera { #expect(await permission.waitEnteredOrFinished()) }
      neutral.suspendVisibility()
      // Allow the actual view's onChange/dismiss and permission callback to run.
      if camera { await permission.release() }
      for _ in 0..<12 { try await Task.sleep(for: .milliseconds(15)) }
      #expect(probe.isPresented && capture.presentingViewController != nil)
      await model.refreshConversation()
      for _ in 0..<12 { try await Task.sleep(for: .milliseconds(15)) }
      #expect(
        model.captureContext == identity && probe.isPresented
          && capture.presentingViewController != nil)
      if camera {
        // Parameter cases own a real modal window and must not race each
        // other's presentation. Read only after SwiftUI has rendered the
        // permission result in that window; no fixed frame-time assumption.
        capture.view.setNeedsLayout()
        capture.view.layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: capture.view)
        for _ in 0..<150 {
          if SignUpRenderingProbe.nodes(in: capture.view).contains(where: {
            $0.label.contains("Não foi possível preparar este anexo")
          }) {
            break
          }
          try await Task.sleep(for: .milliseconds(15))
        }
        #expect(
          SignUpRenderingProbe.nodes(in: capture.view).contains {
            $0.label.contains("Não foi possível preparar este anexo")
          }, Comment(rawValue: String(describing: SignUpRenderingProbe.nodes(in: capture.view))))
      }
      model.invalidateSynchronously()
      // The binding is invalidated synchronously; UIKit tears down its modal
      // asynchronously. Await that observable transition instead of assuming
      // a fixed animation duration while the full rendering suite is running.
      for _ in 0..<150 {
        if !probe.isPresented && capture.presentingViewController == nil { break }
        try await Task.sleep(for: .milliseconds(15))
      }
      #expect(!probe.isPresented && capture.presentingViewController == nil)
      root.dismiss(animated: false)
      await model.close()
    }
    @Test func actualNeutralComposerOffersCaptureWhenItsScopedMediaServiceExists() async throws {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let staging = MediaStagingStore(temporaryDirectory: f.disk.directory)
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault,
        media: .init(uploader: ConversationMediaUploaderProbe(), staging: staging),
        neutralIntakeEnabled: true)
      let host = SignUpRenderingProbe.host(
        FlowConversationComposerContent(
          model: model, capture: .init(stager: .init(staging: staging), camera: .device),
          captureAction: { _ in }, discardAction: { _, _ in }
        ).environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 500)
      defer { host.detach() }
      #expect(
        host.nodes().contains { $0.identifier == "conversation.neutral.attach" && $0.isEnabled })
      #expect(
        !host.nodes().contains {
          $0.label.contains(
            "Fotos, áudio e respostas vinculadas de atividade ainda não estão disponíveis")
        })
      await model.close()
    }
    @Test func failedUploadHasOneUsableSendActionInsteadOfLookingUpAnUnqueuedMessage() async throws
    {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let staging = MediaStagingStore(temporaryDirectory: f.disk.directory)
      let file = try stageConversationSyntheticMedia(
        staging: staging, data: Data("synthetic-media".utf8), fileExtension: "mp3")
      let server = NeutralCaptureUnitServer(
        sessions: f.server, kind: "audio_note", failCreate: true)
      await f.http.stub.respond { request, _ in try await server.reply(request) }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault,
        media: .init(uploader: ConversationMediaUploaderProbe(), staging: staging),
        neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      try model.attach(
        .init(
          fileURL: file, kind: .audioNote, mimeType: "audio/mpeg", sizeBytes: 15, duration: 12,
          channel: .audioRecording), expectedContext: #require(model.captureContext))
      neutral.composer = "Legenda original"
      await neutral.submit()
      #expect(neutral.preparedInput == nil && neutral.isComposerLocked && neutral.canSubmit)
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeComposerContent(
          model: neutral, capture: .init(stager: .init(staging: staging), camera: .device)
        ).environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 700)
      defer { host.detach() }
      #expect(!host.nodes().contains { $0.label == "Consultar original" })
      #expect(
        host.nodes().contains { $0.identifier == "conversation.neutral.send" && $0.isEnabled })
      neutral.composer = "Não substituir o original"
      await neutral.submit()
      let creates = await f.http.stub.requests.filter {
        $0.httpMethod == "POST" && $0.url?.path == "/api/mobile/v1/media"
      }
      #expect(
        creates.count == 2
          && creates[0].value(forHTTPHeaderField: "Idempotency-Key")
            == creates[1].value(forHTTPHeaderField: "Idempotency-Key")
      )
      let intake = try #require(
        await f.http.stub.requests.first {
          $0.httpMethod == "POST" && $0.url?.path == "/api/mobile/v1/conversation/intakes"
        })
      let input = try FlowNeutralIntakeInput(wireBody: #require(intake.httpBody))
      guard case .media(_, let caption) = input.source else {
        Issue.record("Original attachment lost")
        await model.close()
        return
      }
      #expect(caption == "Legenda original")
      await model.close()
    }
    @Test func actualFlowComposerMountsNeutralInputAndSendInsteadOfMealOnlyComposer() async throws {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      let host = SignUpRenderingProbe.host(
        FlowConversationComposerContent(
          model: model, capture: nil, captureAction: { _ in }, discardAction: { _, _ in }
        ).environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 500)
      defer { host.detach() }
      let initial = host.nodes()
      // Vertical SwiftUI TextField embeds a UITextView/ScrollView. The shared
      // probe cannot read that scroll's AX descendants. Exercise the actual
      // mounted native input and its binding instead; no synthetic AX nodes.
      let fields = host.scrollViews().compactMap { $0 as? UITextView }
      #expect(fields.count == 1)
      let field = try #require(fields.first)
      #expect(
        field.window != nil && field.isEditable && field.isUserInteractionEnabled
          && !field.isHidden && field.bounds.width > 0 && field.bounds.height > 0)
      #expect(initial.contains { $0.identifier == "conversation.neutral.send" && !$0.isEnabled })
      #expect(field.becomeFirstResponder())
      field.insertText("leite integral 206 g")
      host.settle()
      #expect(neutral.composer == "leite integral 206 g" && field.text == "leite integral 206 g")
      neutral.mealTypeHint = .cafe
      let typed = host.nodes()
      #expect(
        typed.contains {
          $0.identifier == "conversation.neutral.send" && $0.isEnabled
            && $0.frame.width > 0 && $0.frame.height > 0
        }, Comment(rawValue: String(describing: typed)))
      field.resignFirstResponder()
      await neutral.submit()
      #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
      await model.close()
    }
    @Test(arguments: ["workout_known_unit", "workout_unknown_unit"])
    func confirmedWorkoutRendersFactualDurationAndUnknownEnergyDistinctly(_ variant: String)
      async throws
    {
      let f = try await neutralVisibleFixture(variant: variant)
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      neutral.composer = "Fiz 30 minutos de caminhada."
      await neutral.submit()
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 1000)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.label.contains("Atividade registrada") })
      #expect(nodes.contains { $0.label.contains("30 min") })
      #expect(!nodes.contains { $0.label.contains("154 kcal") || $0.label.contains("0 kcal") })
      if variant == "workout_unknown_unit" {
        #expect(nodes.contains { $0.label.contains("Gasto estimado indisponível") })
      } else {
        #expect(nodes.contains { $0.label.contains("O comentário atual está indisponível") })
      }
      await model.close()
    }
    @Test(arguments: ["pt", "en"])
    func workoutSixSectionsRenderVerbatimFromLegitimateCurrentPolicyWrapper(_ language: String)
      throws
    {
      let (saved, scope) = try neutralWorkoutPresentationUnit(language: language)
      let input = try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("Fiz caminhada"))
      let bound = try #require(
        ConversationFeedbackPresentationSnapshot.boundWorkout(saved, scope: scope))
      let row = FlowNeutralIntakeSavedRow(
        input: input, acknowledgement: .workout(saved),
        identity: .init(
          authUserID: UUID(), ownerID: saved.ownerID, sessionGeneration: 7, epoch: saved.epoch),
        feedback: bound)
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeSavedContent(row: row, english: language == "en").environment(
          \.locale, Locale(identifier: language == "en" ? "en_US" : "pt_BR")), width: 390,
        height: 2400)
      defer { host.detach() }
      let nodes = host.nodes()
      guard case .v3Sections(_, let sections) = bound.presentation.content else {
        Issue.record("Missing six sections")
        return
      }
      for section in sections {
        let node = try #require(
          nodes.first { $0.identifier == "conversation.feedback.section." + section.key.rawValue })
        #expect(node.label == section.text && node.frame.width > 0 && node.frame.height > 0)
      }
    }
    @Test(arguments: [
      "meal_not_recorded_unit:pt", "meal_not_recorded_unit:en", "workout_not_recorded_unit:pt",
      "workout_not_recorded_unit:en",
    ])
    func selectedTypedNotRecordedRendersClosedWithoutWaitingOrContinuation(_ example: String)
      async throws
    {
      let parts = example.split(separator: ":").map(String.init)
      let english = parts[1] == "en"
      let f = try await neutralVisibleFixture(variant: parts[0])
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      neutral.composer = "Relato sem registro"
      await neutral.submit()
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral).environment(
          \.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390, height: 1000)
      defer { host.detach() }
      let nodes = host.nodes()
      let text =
        english
        ? "This message did not record a meal or activity."
        : "Esta mensagem não registrou refeição nem atividade."
      #expect(nodes.contains { $0.label.contains(text) })
      #expect(
        !nodes.contains {
          $0.label.contains("Waiting for the original factual confirmation")
            || $0.label.contains("Aguardando a confirmação factual")
            || $0.identifier == "conversation.neutral.continue"
        })
      #expect(model.savedEffectRevision == 0 && neutral.savedRows.isEmpty)
      await model.close()
    }
    @Test func confirmedMealRendersFromTheRealControllerPublication() async throws {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      neutral.composer = "leite integral 206 g"
      neutral.mealTypeHint = .cafe
      await neutral.submit()
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 900)
      defer { host.detach() }
      #expect(host.nodes().contains { $0.label.contains("Refeição registrada") })
      #expect(host.nodes().contains { $0.label.contains("leite integral 206 g") })
      #expect(!host.nodes().contains { $0.label.contains("Atividade registrada") })
      await model.close()
    }
  }
  @MainActor @Observable private final class NeutralCaptureSheetPresentationProbe {
    var isPresented = true
  }
#endif
