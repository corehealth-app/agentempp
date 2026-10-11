import Observation
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// The meal capture of a real account, hosted as the sheet hosts it, over a
/// simulated server.
@MainActor
final class MealLiveCaptureRenderingTests: XCTestCase {
    private typealias Probe = PremiumRenderingTestSupport.AccessibilityProbe

    private struct Wording {
        let locale: Locale
        let question: String
        let write: String
        let describe: String
        let readFoods: String
        let startRecording: String
        let photoTitle: String
        let takePhoto: String
        let choosePhoto: String
        let recordAudio: String
        let importAudio: String
        // The one loading block.
        let title: String
        let cancel: String
        let preparing: String
        let uploading: String
        let analyzingPhoto: String
        let transcribing: String
        let reading: String
        let calculating: String
        let reviewTitle: String
        let calculate: String
    }

    private let wordings = [
        Wording(
            locale: Locale(identifier: "pt-BR"),
            question: "Como deseja adicionar a refeição?",
            write: "Escrever",
            describe: "Descreva a refeição",
            readFoods: "Ler alimentos",
            startRecording: "Começar gravação",
            photoTitle: "Foto da refeição",
            takePhoto: "Tirar foto",
            choosePhoto: "Escolher foto",
            recordAudio: "Gravar áudio",
            importAudio: "Importar áudio",
            title: "Analisando sua refeição",
            cancel: "Cancelar",
            preparing: "Preparando o arquivo…",
            uploading: "Enviando…",
            analyzingPhoto: "Analisando a foto…",
            transcribing: "Transcrevendo o áudio…",
            reading: "Lendo os alimentos…",
            calculating: "Calculando os valores…",
            reviewTitle: "Revise os alimentos",
            calculate: "Calcular refeição"
        ),
        Wording(
            locale: Locale(identifier: "en"),
            question: "How would you like to add the meal?",
            write: "Write",
            describe: "Describe the meal",
            readFoods: "Read foods",
            startRecording: "Start recording",
            photoTitle: "Meal photo",
            takePhoto: "Take photo",
            choosePhoto: "Choose photo",
            recordAudio: "Record audio",
            importAudio: "Import audio",
            title: "Analyzing your meal",
            cancel: "Cancel",
            preparing: "Preparing the file…",
            uploading: "Uploading…",
            analyzingPhoto: "Analyzing the photo…",
            transcribing: "Transcribing the audio…",
            reading: "Reading the foods…",
            calculating: "Calculating the values…",
            reviewTitle: "Review the foods",
            calculate: "Calculate meal"
        ),
    ]

    /// Asked for on 2026-10-10: the way chosen on the meal card opens its
    /// own step; the five-option question is not asked again.
    func testDirectEntryNeverShowsTheChoiceAgain() throws {
        for wording in wordings {
            let harness = makeHarness()
            defer { harness.cleanUp() }
            let context = wording.locale.identifier

            // Lock: with no entry the sheet opens on the full choice.
            let choice = probe(harness, entry: nil, wording)
            XCTAssertTrue(choice.contains { $0.label == wording.question }, "\(context): \(choice)")
            XCTAssertTrue(choice.contains { $0.isButton && $0.label == wording.write }, "\(context): \(choice)")
            XCTAssertTrue(choice.contains { $0.isButton && $0.label == wording.recordAudio }, "\(context): \(choice)")

            let text = probe(harness, entry: .text, wording)
            _ = try XCTUnwrap(
                text.first { $0.label == wording.describe },
                "Texto must open the field (\(context)): \(text)"
            )
            _ = try XCTUnwrap(text.first { $0.isButton && $0.label == wording.readFoods }, "\(context): \(text)")
            XCTAssertFalse(text.contains { $0.label == wording.question }, "\(context): \(text)")
            XCTAssertFalse(text.contains { $0.isButton && $0.label == wording.write }, "\(context): \(text)")

            let audio = probe(harness, entry: .audio, wording)
            _ = try XCTUnwrap(
                audio.first { $0.isButton && $0.label == wording.startRecording },
                "Áudio must open the recorder (\(context)): \(audio)"
            )
            XCTAssertFalse(audio.contains { $0.label == wording.question }, "\(context): \(audio)")
            XCTAssertFalse(audio.contains { $0.isButton && $0.label == wording.write }, "\(context): \(audio)")

            let photo = probe(harness, entry: .photo, wording)
            let header = try XCTUnwrap(
                photo.first { $0.label == wording.photoTitle },
                "Foto must open the photo step (\(context)): \(photo)"
            )
            XCTAssertFalse(header.isButton, context)
            _ = try XCTUnwrap(photo.first { $0.isButton && $0.label == wording.choosePhoto }, "\(context): \(photo)")
            XCTAssertFalse(photo.contains { $0.label == wording.question }, "\(context): \(photo)")
            for absent in [wording.write, wording.recordAudio, wording.importAudio] {
                XCTAssertFalse(photo.contains { $0.isButton && $0.label == absent }, "\(absent) (\(context)): \(photo)")
            }
        }
    }

    // MARK: Second update (2026-10-10) — Foto opens the camera by itself
    //
    // The owner, on build 1.0 (3): "mesmo quando eu coloco pra registrar a
    // refeição em audio ou foto, ao inves dele abrir direto, ele abre uma
    // tela q pergunta novamente sobre isso". The camera here is one that
    // counts how often it is asked for and never presents anything: its
    // access is not granted in the test host.
    //
    // HOW A ZERO COUNTS: the request runs in a task, so "0 requests" alone
    // could be read too early. Every zero below is read by the SAME helper,
    // in the same test body, as a control that does reach 1; and the mark
    // the sheet keeps — written in the same turn as the decision — is read
    // too.

    func testPhotoEntryAsksForTheCameraOnceAfterTheSheetSettles() throws {
        for wording in wordings {
            let harness = makeHarness(closed: [])
            defer { harness.cleanUp() }
            let context = wording.locale.identifier
            let camera = CountingCamera()
            let sheet = CameraSheetBox()

            let first = runSheet(harness, entry: .photo, camera: camera, sheet: sheet, wording)
            XCTAssertEqual(first.requestsWhileArriving, 0, "Nothing is asked while the sheet is still arriving (\(context))")
            XCTAssertFalse(first.markWhileArriving, context)
            XCTAssertEqual(
                first.requestsOnceSettled, 1,
                "Foto asks for the camera once, by itself, when the sheet has settled (\(context))"
            )
            XCTAssertTrue(first.markOnceSettled, context)
            // The access was not granted here: nothing was presented and no
            // refusal is shown — the step is simply underneath.
            XCTAssertEqual(sheet.log.presentations, 0, context)
            XCTAssertEqual(harness.model.phase, .idle, context)
            XCTAssertTrue(first.probes.contains { $0.label == wording.photoTitle }, "\(context): \(first.probes)")
            XCTAssertTrue(first.probes.contains { $0.isButton && $0.label == wording.takePhoto }, "\(context): \(first.probes)")
            XCTAssertTrue(first.probes.contains { $0.isButton && $0.label == wording.choosePhoto }, "\(context): \(first.probes)")
            XCTAssertFalse(first.probes.contains { $0.label == wording.question }, context)

            // The same sheet with its capture view built again: never by
            // itself a second time.
            let rebuilt = runSheet(harness, entry: .photo, camera: camera, sheet: sheet, wording)
            XCTAssertEqual(rebuilt.requestsWhileArriving + rebuilt.requestsOnceSettled, 0, context)
            XCTAssertTrue(rebuilt.markOnceSettled, context)
            // A new sheet does ask: the zero above was not read too early.
            let another = runSheet(harness, entry: .photo, camera: camera, sheet: CameraSheetBox(), wording)
            XCTAssertEqual(another.requestsOnceSettled, 1, context)
            XCTAssertEqual(camera.requests, 2, context)
        }
    }

    func testNoCameraOrRefusedCameraLeavesThePhotoStepAsToday() throws {
        for wording in wordings {
            let harness = makeHarness(closed: [])
            defer { harness.cleanUp() }
            let context = wording.locale.identifier
            let camera = CountingCamera()

            // Control: read the same way, a camera that can be asked is.
            let control = runSheet(harness, entry: .photo, camera: camera, sheet: CameraSheetBox(), wording)
            XCTAssertEqual(control.requestsOnceSettled, 1, "Control (\(context))")

            // No camera: the step, with the gallery only.
            let noCameraSheet = CameraSheetBox()
            let noCamera = runSheet(
                harness, entry: .photo, camera: camera, available: false, sheet: noCameraSheet, wording
            )
            XCTAssertEqual(noCamera.requestsOnceSettled, 0, context)
            XCTAssertFalse(noCamera.markOnceSettled, context)
            XCTAssertTrue(noCamera.probes.contains { $0.label == wording.photoTitle }, context)
            XCTAssertTrue(noCamera.probes.contains { $0.isButton && $0.label == wording.choosePhoto }, context)
            XCTAssertFalse(noCamera.probes.contains { $0.isButton && $0.label == wording.takePhoto }, context)

            // A camera refused before: the step with its two actions, and
            // nothing asked or said by itself.
            let refusedSheet = CameraSheetBox()
            let refused = runSheet(
                harness, entry: .photo, camera: camera, permission: .denied, sheet: refusedSheet, wording
            )
            XCTAssertEqual(refused.requestsOnceSettled, 0, context)
            XCTAssertFalse(refused.markOnceSettled, context)
            XCTAssertTrue(refused.probes.contains { $0.label == wording.photoTitle }, context)
            XCTAssertTrue(refused.probes.contains { $0.isButton && $0.label == wording.takePhoto }, context)
            XCTAssertTrue(refused.probes.contains { $0.isButton && $0.label == wording.choosePhoto }, context)
            XCTAssertEqual(harness.model.phase, .idle, "No refusal is reported by itself (\(context))")
            XCTAssertEqual(camera.requests, 1, "Only the control asked (\(context))")
        }
    }

    func testAudioAndTextEntriesNeverTouchTheCamera() throws {
        for wording in wordings {
            let harness = makeHarness(closed: [])
            defer { harness.cleanUp() }
            let context = wording.locale.identifier
            let camera = CountingCamera()

            let control = runSheet(harness, entry: .photo, camera: camera, sheet: CameraSheetBox(), wording)
            XCTAssertEqual(control.requestsOnceSettled, 1, "Control (\(context))")

            for entry in [MealCaptureEntry.audio, .text, nil] {
                let sheet = CameraSheetBox()
                let run = runSheet(harness, entry: entry, camera: camera, sheet: sheet, wording)
                let name = entry.map { "\($0)" } ?? "no entry"
                XCTAssertEqual(run.requestsWhileArriving + run.requestsOnceSettled, 0, "\(name) (\(context))")
                XCTAssertFalse(run.markOnceSettled, "\(name) (\(context))")
                XCTAssertEqual(sheet.log, MealCameraLog(), "\(name) (\(context))")
                if entry == .audio {
                    // The recorder is open and nothing records by itself.
                    XCTAssertTrue(
                        run.probes.contains { $0.isButton && $0.label == wording.startRecording },
                        "\(context): \(run.probes)"
                    )
                    XCTAssertEqual(harness.recorder.state, .idle, context)
                }
                if entry == .text {
                    XCTAssertTrue(run.probes.contains { $0.isButton && $0.label == wording.readFoods }, context)
                }
            }
            XCTAssertEqual(camera.requests, 1, "Only the control asked (\(context))")
        }
    }

    private struct CameraRun {
        let requestsWhileArriving: Int
        let markWhileArriving: Bool
        let requestsOnceSettled: Int
        let markOnceSettled: Bool
        let probes: [Probe]
    }

    /// Mounts the capture on `sheet`, reads, lets the sheet settle and reads
    /// again — always the same way, for the controls and for the zeros.
    private func runSheet(
        _ harness: Harness,
        entry: MealCaptureEntry?,
        camera: CountingCamera,
        available: Bool = true,
        permission: MealCameraAccess.Permission = .notAsked,
        sheet: CameraSheetBox,
        _ wording: Wording
    ) -> CameraRun {
        let start = camera.requests
        let host = PremiumRenderingTestSupport.liveAccessibilityHost(
            CameraHost(
                harness: harness, sheet: sheet, entry: entry,
                camera: camera.access(available: available, permission: permission)
            )
            .environment(\.locale, wording.locale),
            width: 393
        )
        defer { host.detach() }
        _ = host.probe()
        _ = host.probe()
        let whileArriving = camera.requests - start
        let markWhileArriving = sheet.log.openedByItself
        sheet.settled = true
        _ = host.probe()
        let probes = host.probe()
        return CameraRun(
            requestsWhileArriving: whileArriving,
            markWhileArriving: markWhileArriving,
            requestsOnceSettled: camera.requests - start - whileArriving,
            markOnceSettled: sheet.log.openedByItself,
            probes: probes
        )
    }

    private struct CameraHost: View {
        let harness: Harness
        @Bindable var sheet: CameraSheetBox
        let entry: MealCaptureEntry?
        let camera: MealCameraAccess

        var body: some View {
            MealLiveCaptureView(
                model: harness.model,
                stager: MealMediaStager(staging: harness.staging),
                recorder: harness.recorder,
                entry: entry,
                sheetSettled: sheet.settled,
                camera: camera,
                cameraLog: $sheet.log,
                analysisStage: nil,
                isProposing: false,
                submitText: { _ in },
                submitMedia: { _ in },
                retry: {},
                propose: { _ in }
            )
        }
    }

    // MARK: One loading block for the whole analysis
    //
    // Reported by the owner on 2026-10-10 (build 1.0 (3), real account,
    // PHOTO): "quando está processando, aparecem vários loading, o ideal
    // seria manter somente 1 e melhor estruturado". The exact scenario: one
    // photo, from the moment it is taken until the foods are read — the
    // SAME live view, read at each of the four stages while the model is
    // suspended inside the real call of that stage.

    func testPhotoIsOneBlockFromPreparingToReading() async throws {
        for wording in wordings {
            let harness = makeHarness(closed: [.create, .asset, .draft])
            defer { harness.cleanUp() }
            let staged = try stagedPhoto(harness)
            let host = PremiumRenderingTestSupport.liveAccessibilityHost(
                analysisHost(harness, SubmittingBox(), wording), width: 393
            )
            defer { host.detach() }

            // Lock: before any capture the sheet shows the choice.
            let before = host.probe()
            XCTAssertTrue(before.contains { $0.label == wording.question }, describe(before))
            XCTAssertFalse(before.contains { $0.label == wording.title }, describe(before))

            // 1. The photo was taken: its file is being prepared.
            harness.model.beginPreparing()
            let preparing = try block(host.probe(), wording, stage: wording.preparing, cancelEnabled: false)

            let run = Task { await harness.model.submitMedia(staged) }
            let outcome = await Result<Void, any Error>.catching {
                // 2. Suspended inside the creation of the upload.
                await harness.server.waitUntilSuspended(at: .create)
                let sending = try self.block(host.probe(), wording, stage: wording.uploading, cancelEnabled: true)
                // 3. Suspended while the server looks at the photo.
                await harness.server.open(.create)
                await harness.server.waitUntilSuspended(at: .asset)
                let analysing = try self.block(host.probe(), wording, stage: wording.analyzingPhoto, cancelEnabled: true)
                // 4. Suspended while the foods are read.
                await harness.server.open(.asset)
                await harness.server.waitUntilSuspended(at: .draft)
                let reading = try self.block(host.probe(), wording, stage: wording.reading, cancelEnabled: true)

                // One block: the status and the cancel action never moved.
                for later in [sending, analysing, reading] {
                    XCTAssertEqual(later.status.frame, preparing.status.frame, wording.locale.identifier)
                    XCTAssertEqual(later.cancel.frame, preparing.cancel.frame, wording.locale.identifier)
                }
            }
            await harness.server.openAll()
            await run.value
            try outcome.get()

            // The review takes the block's place.
            let review = host.probe()
            XCTAssertTrue(review.contains { $0.label == wording.reviewTitle }, describe(review))
            XCTAssertFalse(review.contains { $0.label == wording.title }, describe(review))
            XCTAssertFalse(review.contains { $0.isButton && $0.label == wording.cancel }, describe(review))
        }
    }

    func testAudioSaysItsOwnLineInTheSameBlock() async throws {
        for wording in wordings {
            let harness = makeHarness(closed: [.asset])
            defer { harness.cleanUp() }
            let staged = try stagedAudio(harness)
            let host = PremiumRenderingTestSupport.liveAccessibilityHost(
                analysisHost(harness, SubmittingBox(), wording), width: 393
            )
            defer { host.detach() }

            harness.model.beginPreparing()
            let preparing = try block(host.probe(), wording, stage: wording.preparing, cancelEnabled: false)

            let run = Task { await harness.model.submitMedia(staged) }
            let outcome = await Result<Void, any Error>.catching {
                await harness.server.waitUntilSuspended(at: .asset)
                let transcribing = try self.block(
                    host.probe(), wording, stage: wording.transcribing, cancelEnabled: true
                )
                XCTAssertEqual(transcribing.status.frame, preparing.status.frame, wording.locale.identifier)
                XCTAssertEqual(transcribing.cancel.frame, preparing.cancel.frame, wording.locale.identifier)
            }
            await harness.server.openAll()
            await run.value
            try outcome.get()
        }
    }

    func testReadingTextShowsTheSameBlock() async throws {
        for wording in wordings {
            let harness = makeHarness(closed: [.draft])
            defer { harness.cleanUp() }
            let host = PremiumRenderingTestSupport.liveAccessibilityHost(
                analysisHost(harness, SubmittingBox(), wording), width: 393
            )
            defer { host.detach() }

            let run = Task { await harness.model.submitText("2 ovos mexidos") }
            let outcome = await Result<Void, any Error>.catching {
                await harness.server.waitUntilSuspended(at: .draft)
                _ = try self.block(host.probe(), wording, stage: wording.reading, cancelEnabled: true)
            }
            await harness.server.openAll()
            await run.value
            try outcome.get()
            let review = host.probe()
            XCTAssertTrue(review.contains { $0.label == wording.reviewTitle }, describe(review))
        }
    }

    /// After "Calcular refeição" the same block takes the review's place
    /// until the calculation comes back; there is nothing to cancel.
    func testCalculatingUsesTheSameLoaderInPlaceOfTheReview() async throws {
        for wording in wordings {
            let harness = makeHarness()
            defer { harness.cleanUp() }
            await harness.model.submitText("2 ovos mexidos")
            XCTAssertEqual(harness.model.phase, .review)
            let submitting = SubmittingBox()
            let host = PremiumRenderingTestSupport.liveAccessibilityHost(
                analysisHost(harness, submitting, wording), width: 393
            )
            defer { host.detach() }

            // Lock: the review, with its action, while nothing was sent.
            let review = host.probe()
            XCTAssertTrue(review.contains { $0.label == wording.reviewTitle }, describe(review))
            XCTAssertTrue(review.contains { $0.isButton && $0.label == wording.calculate }, describe(review))
            XCTAssertFalse(review.contains { $0.label == wording.title }, describe(review))

            // The reviewed foods were sent: no proposal yet.
            submitting.isSubmitting = true
            let waiting = host.probe()
            let statuses = waiting.filter { !$0.isButton && $0.label == wording.title }
            let status = try XCTUnwrap(
                statuses.first, "No loading block while the meal is calculated: \(describe(waiting))"
            )
            XCTAssertEqual(statuses.count, 1, describe(waiting))
            XCTAssertEqual(status.value, wording.calculating)
            XCTAssertFalse(waiting.contains { $0.isButton && $0.label == wording.calculate }, describe(waiting))
            XCTAssertFalse(waiting.contains { $0.isButton && $0.label == wording.cancel }, describe(waiting))
            XCTAssertFalse(waiting.contains { $0.label == wording.reviewTitle }, describe(waiting))
            XCTAssertEqual(waiting.count, 1, describe(waiting))

            // The calculation failed (nothing came back): the review returns
            // with what it had.
            submitting.isSubmitting = false
            let back = host.probe()
            XCTAssertTrue(back.contains { $0.isButton && $0.label == wording.calculate }, describe(back))
            XCTAssertFalse(back.contains { $0.label == wording.title }, describe(back))
            XCTAssertEqual(harness.model.review?.items.map(\.name), ["ovos mexidos"])
        }
    }

    /// The loading block as the screen shows it: exactly one status element
    /// (title as label, stage as value), exactly one cancel action, and
    /// nothing else — no choice of ways, no second line saying the stage.
    private func block(
        _ probes: [Probe],
        _ wording: Wording,
        stage: String,
        cancelEnabled: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (status: Probe, cancel: Probe) {
        let context = "\(stage) (\(wording.locale.identifier)): \(describe(probes))"
        let statuses = probes.filter { !$0.isButton && $0.label == wording.title }
        let status = try XCTUnwrap(
            statuses.first, "No loading block for \(context)", file: file, line: line
        )
        XCTAssertEqual(statuses.count, 1, context, file: file, line: line)
        XCTAssertEqual(status.value, stage, context, file: file, line: line)
        let cancels = probes.filter { $0.isButton && $0.label == wording.cancel }
        let cancel = try XCTUnwrap(cancels.first, "No cancel for \(context)", file: file, line: line)
        XCTAssertEqual(cancels.count, 1, context, file: file, line: line)
        XCTAssertEqual(cancel.isEnabled, cancelEnabled, context, file: file, line: line)
        XCTAssertFalse(probes.contains { $0.label == wording.question }, context, file: file, line: line)
        XCTAssertFalse(probes.contains { $0.isButton && $0.label == wording.write }, context, file: file, line: line)
        XCTAssertFalse(probes.contains { $0.label == stage }, context, file: file, line: line)
        XCTAssertEqual(probes.count, 2, context, file: file, line: line)
        return (status, cancel)
    }

    private func describe(_ probes: [Probe]) -> String {
        probes.map { "[\($0.label) | \($0.value) | button=\($0.isButton) enabled=\($0.isEnabled)]" }
            .joined(separator: " ")
    }

    private func stagedPhoto(_ harness: Harness) throws -> StagedMedia {
        let url = try harness.staging.stage(Data([0xFF, 0xD8, 1, 2]), fileExtension: "jpg")
        return StagedMedia(
            fileURL: url, kind: .mealPhoto, mimeType: "image/jpeg",
            sizeBytes: 4, duration: nil, channel: .camera
        )
    }

    private func stagedAudio(_ harness: Harness) throws -> StagedMedia {
        let url = try harness.staging.stage(Data([1, 2, 3]), fileExtension: "m4a")
        return StagedMedia(
            fileURL: url, kind: .audioNote, mimeType: "audio/mp4",
            sizeBytes: 3, duration: 20, channel: .audioRecording
        )
    }

    /// The capture view as the sheet composes it: the stage comes from the
    /// SAME decision the sheet and the brand mark read.
    private func analysisHost(
        _ harness: Harness,
        _ submitting: SubmittingBox,
        _ wording: Wording
    ) -> some View {
        AnalysisHost(harness: harness, submitting: submitting)
            .environment(\.locale, wording.locale)
    }

    private struct AnalysisHost: View {
        let harness: Harness
        let submitting: SubmittingBox

        var body: some View {
            MealLiveCaptureView(
                model: harness.model,
                stager: MealMediaStager(staging: harness.staging),
                recorder: harness.recorder,
                entry: nil,
                sheetSettled: true,
                camera: .unavailable,
                cameraLog: .constant(MealCameraLog()),
                analysisStage: RegistrationSheet.mealAnalysisStage(
                    kind: .meal,
                    hasLiveCapture: true,
                    hasProposal: false,
                    registrationPhase: .capture,
                    draftPhase: harness.model.phase,
                    channel: harness.model.channel,
                    isSubmitting: submitting.isSubmitting
                ),
                isProposing: submitting.isSubmitting,
                submitText: { _ in },
                submitMedia: { _ in },
                retry: {},
                propose: { _ in }
            )
        }
    }

    // MARK: Support

    private struct Harness {
        let model: MealDraftModel
        let server: GatedCaptureServer
        let staging: MediaStagingStore
        let recorder: MealAudioRecorder
        let base: URL

        func cleanUp() { try? FileManager.default.removeItem(at: base) }
    }

    private func makeHarness(closed: Set<GatedCaptureServer.Gate> = []) -> Harness {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-capture-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let server = GatedCaptureServer(closed: closed)
        let model = MealDraftModel(
            media: server,
            drafts: server,
            uploader: server,
            staging: staging,
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1_790_000_000)),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "live-capture-key"),
            pollInterval: .milliseconds(1),
            maximumPolls: 5,
            calendar: Calendar(identifier: .gregorian)
        )
        return Harness(
            model: model, server: server, staging: staging,
            recorder: MealAudioRecorder(staging: staging), base: base
        )
    }

    private func view(_ harness: Harness, entry: MealCaptureEntry?, _ wording: Wording) -> some View {
        MealLiveCaptureView(
            model: harness.model,
            stager: MealMediaStager(staging: harness.staging),
            recorder: harness.recorder,
            entry: entry,
            sheetSettled: true,
            camera: .unavailable,
            cameraLog: .constant(MealCameraLog()),
            analysisStage: nil,
            isProposing: false,
            submitText: { _ in },
            submitMedia: { _ in },
            retry: {},
            propose: { _ in }
        )
        .environment(\.locale, wording.locale)
    }

    private func probe(_ harness: Harness, entry: MealCaptureEntry?, _ wording: Wording) -> [Probe] {
        PremiumRenderingTestSupport.accessibilityProbe(view(harness, entry: entry, wording), width: 393)
    }
}

/// Whether the sheet's registration is submitting, for the hosted view.
@MainActor
@Observable
final class SubmittingBox {
    var isSubmitting = false
}

extension Result where Success == Void, Failure == any Error {
    /// Runs the body and keeps its failure, so the gates can be opened
    /// before the failure is rethrown.
    @MainActor
    static func catching(_ body: @MainActor () async throws -> Void) async -> Self {
        do {
            try await body()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

/// A capture server whose answers wait at named gates, so a test reads the
/// screen while the model is suspended inside a real call. The handshake is
/// by continuation: no sleep and no polling.
actor GatedCaptureServer: MealMediaProviding, MealDraftProviding, StorageUploading {
    enum Gate: Hashable, Sendable { case create, asset, draft }

    static let assetID = "0a0a0a0a-1111-4222-8333-444455556666"
    static let draft = MealDraftSnapshot(
        source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
        items: [MealDraftCandidate(
            candidateID: "c1-0a1b2c3d", name: "ovos mexidos", quantityG: 100,
            quantityBasis: "portion_reference", count: 2, unitLabel: "unidade",
            confidence: nil, needsReview: true, reviewReason: "estimated_quantity"
        )],
        nutritionLabel: nil
    )

    private var closed: Set<Gate>
    private var arrived: Set<Gate> = []
    private var suspended: [Gate: CheckedContinuation<Void, Never>] = [:]
    private var watchers: [Gate: CheckedContinuation<Void, Never>] = [:]

    init(closed: Set<Gate>) { self.closed = closed }

    /// Returns once a call is suspended at `gate`.
    func waitUntilSuspended(at gate: Gate) async {
        if arrived.contains(gate) { return }
        await withCheckedContinuation { watchers[gate] = $0 }
    }

    func open(_ gate: Gate) {
        closed.remove(gate)
        arrived.remove(gate)
        suspended.removeValue(forKey: gate)?.resume()
    }

    func openAll() {
        for gate in [Gate.create, .asset, .draft] { open(gate) }
    }

    private func pass(_ gate: Gate) async {
        guard closed.contains(gate) else { return }
        arrived.insert(gate)
        watchers.removeValue(forKey: gate)?.resume()
        await withCheckedContinuation { suspended[gate] = $0 }
    }

    private func asset(_ status: String) -> MediaAssetSnapshot {
        MediaAssetSnapshot(
            id: Self.assetID, kind: "meal_photo", status: status,
            failureStage: nil, failureCode: nil
        )
    }

    func create(
        _ attempt: MutationAttempt<MediaUploadRequest>
    ) async throws -> MediaCreateSnapshot {
        await pass(.create)
        return MediaCreateSnapshot(
            asset: asset("pending_upload"),
            upload: MediaUploadTicket(
                signedURL: "https://project.supabase.co/storage/v1/object/upload/sign/b/u/a?token=t1",
                method: "PUT",
                headers: ["Content-Type": attempt.payload.mimeType],
                expiresAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_600))
            ),
            replayed: false
        )
    }

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {}

    func complete(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        asset("uploaded")
    }

    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        asset("uploaded")
    }

    func asset(id: String) async throws -> MediaAssetSnapshot {
        await pass(.asset)
        return asset("processed")
    }

    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws {}

    func draft(
        _ attempt: MutationAttempt<MealDraftRequest>
    ) async throws -> MealDraftSnapshot {
        await pass(.draft)
        return Self.draft
    }
}

/// What the sheet owns for the capture view: whether it has arrived, and its
/// record of the camera.
@MainActor
@Observable
final class CameraSheetBox {
    var settled = false
    var log = MealCameraLog()
}

/// A camera that counts how often it is asked for and never grants the
/// access, so nothing is ever presented in the test host.
final class CountingCamera: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var requests: Int { lock.withLock { count } }

    func access(
        available: Bool = true,
        permission: MealCameraAccess.Permission = .notAsked
    ) -> MealCameraAccess {
        MealCameraAccess(
            origin: .device,
            isAvailable: { available },
            permission: { permission },
            requestAccess: { [self] in
                lock.withLock { count += 1 }
                return false
            }
        )
    }
}
