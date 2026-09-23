import Testing
import UIKit
@testable import BodyFlow

@Suite("Symbol vocabulary")
struct BodyFlowSymbolTests {
    @Test func everySymbolResolvesToAnInstalledSystemImage() {
        for symbol in BodyFlowSymbol.allCases {
            #expect(
                UIImage(systemName: symbol.systemName) != nil,
                "\(symbol) must name an SF Symbol available on the deployment target"
            )
        }
    }

    @Test func meaningsNeverShareAGlyphAndGlyphsNeverShareAMeaning() {
        let names = BodyFlowSymbol.allCases.map(\.systemName)
        #expect(Set(names).count == names.count)
    }

    @Test func stateGlyphsMatchTheScreenStateDescriptors() {
        #expect(BodyFlowSymbol.empty.systemName == ScreenState.empty.descriptor.systemImage)
        #expect(BodyFlowSymbol.offline.systemName == ScreenState.offline.descriptor.systemImage)
        #expect(BodyFlowSymbol.unavailable.systemName == ScreenState.unavailable.descriptor.systemImage)
        #expect(BodyFlowSymbol.refresh.systemName == ScreenState.recoverableError.descriptor.systemImage)
    }

    @Test func statusLinesUseTheVocabularyAndFeedbackRoles() {
        #expect(BodyFlowStatusLine.Kind.error.symbol == .error)
        #expect(BodyFlowStatusLine.Kind.error.foregroundRole == .feedbackDestructive)
        #expect(BodyFlowStatusLine.Kind.warning.symbol == .warning)
        #expect(BodyFlowStatusLine.Kind.warning.foregroundRole == .feedbackWarning)
        #expect(BodyFlowStatusLine.Kind.success.symbol == .success)
        #expect(BodyFlowStatusLine.Kind.success.foregroundRole == .feedbackPositive)
        for kind in [BodyFlowStatusLine.Kind.info, .pending, .empty, .unavailable] {
            #expect(kind.foregroundRole == .textSecondary)
        }
        #expect(BodyFlowStatusLine.Kind.pending.symbol == .clock)
        #expect(BodyFlowStatusLine.Kind.empty.symbol == .empty)
    }
}
