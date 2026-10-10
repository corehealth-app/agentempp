import Foundation
import Testing

@testable import BodyFlow

/// Asked for on 2026-10-10: while the plate is analysed several loading
/// indicators followed one another. These are the stages of the ONE loading
/// block that replaces them — only stages the app really knows.
@Suite("Meal analysis stage")
struct MealAnalysisStageTests {
    private static let workingPhases: [MealDraftPhase] = [.preparing, .uploading, .processing, .reading]

    @Test("every real stage of the analysis has one line")
    func everyRealStageHasOneLine() {
        #expect(MealAnalysisStage.resolve(phase: .preparing, channel: nil, isProposing: false) == .preparing)
        #expect(MealAnalysisStage.resolve(phase: .uploading, channel: .camera, isProposing: false) == .sending)
        #expect(MealAnalysisStage.resolve(phase: .uploading, channel: .audioRecording, isProposing: false) == .sending)
        #expect(MealAnalysisStage.resolve(phase: .processing, channel: .camera, isProposing: false) == .photo)
        #expect(MealAnalysisStage.resolve(phase: .processing, channel: .gallery, isProposing: false) == .photo)
        #expect(MealAnalysisStage.resolve(phase: .processing, channel: .audioRecording, isProposing: false) == .audio)
        #expect(MealAnalysisStage.resolve(phase: .processing, channel: .audioImport, isProposing: false) == .audio)
        #expect(MealAnalysisStage.resolve(phase: .reading, channel: .text, isProposing: false) == .reading)
        #expect(MealAnalysisStage.resolve(phase: .reading, channel: .camera, isProposing: false) == .reading)
        // Totality: no phase of the wait is left without a stage.
        for phase in Self.workingPhases {
            for channel in [MealSourceChannel?.none, .text, .camera, .gallery, .audioRecording, .audioImport] {
                #expect(
                    MealAnalysisStage.resolve(phase: phase, channel: channel, isProposing: false) != nil,
                    "\(phase) / \(String(describing: channel))"
                )
            }
        }
        // Locks: nothing is being waited for.
        #expect(MealAnalysisStage.resolve(phase: .idle, channel: nil, isProposing: false) == nil)
        #expect(MealAnalysisStage.resolve(phase: .idle, channel: nil, isProposing: true) == nil)
        #expect(MealAnalysisStage.resolve(phase: .failed(.offline), channel: .camera, isProposing: false) == nil)
        #expect(MealAnalysisStage.resolve(phase: .failed(.offline), channel: .camera, isProposing: true) == nil)
        #expect(MealAnalysisStage.resolve(phase: .review, channel: .camera, isProposing: false) == nil)
    }

    /// The wait after "Calcular refeição" is a stage of the same block.
    @Test("calculating is a stage only while a proposal is being created")
    func calculatingIsAStageOnlyWhileAProposalIsBeingCreated() {
        for channel in [MealSourceChannel.text, .camera, .gallery, .audioRecording, .audioImport] {
            #expect(MealAnalysisStage.resolve(phase: .review, channel: channel, isProposing: true) == .calculating)
            #expect(MealAnalysisStage.resolve(phase: .review, channel: channel, isProposing: false) == nil)
        }
        // The calculation never had a cancel, and reserves only its own line.
        #expect(!MealAnalysisStage.calculating.offersCancel)
        #expect(MealAnalysisStage.calculating.reservedLines == [.calculating])
        #expect(MealAnalysisFocus.takesFocus(from: nil, to: .calculating))
    }

    @Test("a stage line never invents progress", arguments: SupportedAppLanguage.allCases)
    func stageLinesNeverInventProgress(_ language: SupportedAppLanguage) {
        let expected: [(MealAnalysisStage, String, String)] = [
            (.preparing, "Preparando o arquivo…", "Preparing the file…"),
            (.sending, "Enviando…", "Uploading…"),
            (.photo, "Analisando a foto…", "Analyzing the photo…"),
            (.audio, "Transcrevendo o áudio…", "Transcribing the audio…"),
            (.reading, "Lendo os alimentos…", "Reading the foods…"),
            (.calculating, "Calculando os valores…", "Calculating the values…"),
        ]
        #expect(expected.map(\.0) == MealAnalysisStage.allCases)
        for (stage, pt, en) in expected {
            let line = PremiumPresentationCopy.string(
                stage.lineKey, locale: language.formattingLocale, fallback: ""
            )
            #expect(line == (language == .portugueseBrazil ? pt : en), "\(stage)")
            // Never a percentage, never a number.
            #expect(!line.contains("%"), "\(stage)")
            #expect(line.rangeOfCharacter(from: .decimalDigits) == nil, "\(stage)")
        }
    }

    @Test("the capture reserves exactly the five lines of its one wait")
    func reservedLinesAreExactlyTheCaptureLines() {
        #expect(MealAnalysisStage.captureLines == [.preparing, .sending, .photo, .audio, .reading])
        for stage in MealAnalysisStage.captureLines {
            #expect(stage.reservedLines == MealAnalysisStage.captureLines)
            #expect(stage.offersCancel)
        }
        // While the file is prepared there is nothing to cancel yet: the
        // action keeps its place, disabled (it did not exist there before).
        #expect(!MealAnalysisStage.preparing.isCancelEnabled)
        for stage in [MealAnalysisStage.sending, .photo, .audio, .reading] {
            #expect(stage.isCancelEnabled)
        }
        // Every stage the capture can resolve to is one of the reserved lines.
        for phase in Self.workingPhases {
            for channel in [MealSourceChannel?.none, .text, .camera, .audioRecording] {
                let stage = MealAnalysisStage.resolve(phase: phase, channel: channel, isProposing: false)
                #expect(stage.map(MealAnalysisStage.captureLines.contains) == true, "\(phase)")
            }
        }
    }

    @Test("VoiceOver focus is asked for once per appearance of the block")
    func voiceOverFocusIsAskedOncePerAppearance() {
        for stage in MealAnalysisStage.allCases {
            #expect(MealAnalysisFocus.takesFocus(from: nil, to: stage), "\(stage)")
            // Leaving, and nothing on screen: no focus is asked for.
            #expect(!MealAnalysisFocus.takesFocus(from: stage, to: nil))
            // A change of stage is the new value of the same element.
            for next in MealAnalysisStage.allCases {
                #expect(!MealAnalysisFocus.takesFocus(from: stage, to: next))
            }
        }
        #expect(!MealAnalysisFocus.takesFocus(from: nil, to: nil))
    }
}
