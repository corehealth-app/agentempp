import Foundation
import Testing

@testable import BodyFlow

@Suite("Flow presentation")
struct FlowChatPresentationTests {
    @Test
    func composerMatchesUnchangedModelGuard() {
        #expect(!FlowChatPresentation.canSubmit(" \n ", isSending: false))
        #expect(FlowChatPresentation.canSubmit(String(repeating: "a", count: 4_000), isSending: false))
        #expect(!FlowChatPresentation.canSubmit(String(repeating: "a", count: 4_001), isSending: false))
        #expect(!FlowChatPresentation.canSubmit("QA", isSending: true))
        #expect(!FlowChatPresentation.isOverLimit("  " + String(repeating: "a", count: 4_000) + " \n"))
        #expect(FlowChatPresentation.isOverLimit(String(repeating: "a", count: 4_001)))
    }

    @Test
    func readerPolicyDoesNotStealHistoryOrAnimateReducedMotion() {
        #expect(!FlowChatScrollPolicy.shouldFollow(atEnd: false, initiatedSend: false))
        #expect(FlowChatScrollPolicy.shouldFollow(atEnd: true, initiatedSend: false))
        #expect(FlowChatScrollPolicy.shouldFollow(atEnd: false, initiatedSend: true))
        #expect(!FlowChatScrollPolicy.shouldAnimate(reduceMotion: true))
        #expect(FlowChatScrollPolicy.shouldAnimate(reduceMotion: false))
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func publicRoleAndLimitLabelsAreReviewed(_ language: SupportedAppLanguage) throws {
        #expect(try AppLocalization.string(FlowChatPresentation.roleLabelKey(.user), for: language)
            == (language == .portugueseBrazil ? "Você" : "You"))
        #expect(try AppLocalization.string(FlowChatPresentation.roleLabelKey(.assistant), for: language)
            == "Flow")
        #expect(try AppLocalization.string("flow.role-line", for: language).contains("Performe AI"))
        #expect(try AppLocalization.string("flow.limit.detail", for: language).contains("4"))
    }
    @Test(arguments: SupportedAppLanguage.allCases)
    func waitingAndCancellationCopyDescribeOnlyRealLocalState(_ language: SupportedAppLanguage) throws {
        #expect(try AppLocalization.string("flow.responding", for: language) ==
            (language == .portugueseBrazil
                ? "Enviando e aguardando o Flow…" : "Sending and waiting for Flow…"))
        #expect(try AppLocalization.string("flow.cancel", for: language) ==
            (language == .portugueseBrazil ? "Cancelar espera" : "Cancel waiting"))
        #expect(try AppLocalization.string("flow.message.processing", for: language) ==
            (language == .portugueseBrazil ? "Em processamento" : "Processing"))
    }
}
