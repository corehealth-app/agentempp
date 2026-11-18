import SwiftUI
import UIKit
import XCTest

@testable import BodyFlow

@MainActor final class JourneySocialRenderingTests: XCTestCase {
  func testClosingTheSameReportSheetRemovesCachedPeerAndSubmitAction() async throws {
    let h = try JourneySocialUIHarness()
    await h.model.load()
    let peer = try XCTUnwrap(h.model.rankings.first { !$0.isYou })
    let host = PremiumRenderingTestSupport.liveAccessibilityHost(
      JourneySocialReportSheet(model: h.model, member: peer)
        .environment(\.locale, Locale(identifier: "pt_BR")), width: 375)
    defer { host.detach() }
    XCTAssertTrue(host.probe().contains { $0.label == peer.nickname })
    XCTAssertTrue(host.probe().contains { $0.identifier == "journey-social.report-submit" })
    h.model.invalidateSynchronously()
    let closed = host.probe()
    XCTAssertFalse(
      closed.contains { $0.label == peer.nickname },
      "A cached sheet must react to the same model's synchronous close")
    XCTAssertFalse(closed.contains { $0.identifier == "journey-social.report-submit" })
    XCTAssertTrue(closed.contains { $0.label == "Esta sessão foi encerrada." })
    let submitted = await h.provider.submitted()
    XCTAssertTrue(submitted.isEmpty)
  }

  func testNativeConsentAndPendingRecoveryKeepTheActionExplicit() async throws {
    for pending in [false, true] {
      let h = try JourneySocialUIHarness(participating: false)
      if pending { try await h.store.claim(pendingSocial()) }
      await h.model.load()
      let host = PremiumRenderingTestSupport.liveAccessibilityHost(
        JourneySocialView(model: h.model).environment(\.locale, Locale(identifier: "pt_BR")),
        width: 375)
      defer { host.detach() }
      _ = host.probe()  // Mount the SwiftUI .task before awaiting its actor work.
      for _ in 0..<100 {
        await Task.yield()
        host.settle()
        if h.model.phase == .ready && !h.model.isWorking { break }
      }
      XCTAssertEqual(h.model.phase, .ready)
      XCTAssertFalse(h.model.isWorking)
      let probe = host.probe()
      if pending {
        XCTAssertTrue(
          probe.contains { $0.identifier == "journey-social.resolve" },
          "Recovery tree: \(probe.map { ($0.label, $0.identifier, $0.isEnabled) })")
      } else {
        XCTAssertTrue(
          probe.contains { $0.identifier == "journey-social.consent" },
          "Consent tree: \(probe.map { ($0.label, $0.identifier, $0.isEnabled) })")
        XCTAssertTrue(
          probe.contains { $0.identifier == "journey-social.participate" && !$0.isEnabled },
          "Submit tree: \(probe.map { ($0.label, $0.identifier, $0.isEnabled) })")
      }
      let attachment = XCTAttachment(
        data: try XCTUnwrap(host.image().pngData()), uniformTypeIdentifier: "public.png")
      attachment.name = pending ? "journey-social-pending-pt-375" : "journey-social-consent-pt-375"
      attachment.lifetime = .keepAlways
      add(attachment)
      let submitted = await h.provider.submitted()
      XCTAssertTrue(submitted.isEmpty)
    }
  }
}
