import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class FinalPolishRenderingTests: XCTestCase {
    // ScrollView accessibility is exercised by the real UI runner: the
    // profile-first weight/date and landscape Splash tests passed there.
    // A manual UIKit descendant probe cannot enumerate SwiftUI virtual rows.

    func testSplashKeepsNegativeMarkOnDeepTealInBothThemes() throws {
        for dark in [false, true] {
            let image = PremiumRenderingTestSupport.nativeImage(
                SplashView().frame(height: 650), width: 375, dark: dark,
                size: .large, locale: Locale(identifier: "pt_BR")
            )
            let cgImage = try XCTUnwrap(image.cgImage)
            let pixel = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 8, y: 8, width: 1, height: 1)))
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(
                data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            XCTAssertEqual(Int(bytes[0]), 0, accuracy: 2)
            XCTAssertEqual(Int(bytes[1]), 59, accuracy: 2)
            XCTAssertEqual(Int(bytes[2]), 59, accuracy: 2)
            let attachment = XCTAttachment(image: image)
            attachment.name = "final-polish-splash-\(dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testRuntimeMarkMatchesStaticLaunchCenter() throws {
        let size = CGSize(width: 375, height: 650)
        let launch = try XCTUnwrap(UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController())
        launch.loadViewIfNeeded()
        launch.view.frame = CGRect(origin: .zero, size: size)
        launch.view.layoutIfNeeded()
        let staticImage = UIGraphicsImageRenderer(size: size).image { context in
            launch.view.layer.render(in: context.cgContext)
        }
        let runtime = PremiumRenderingTestSupport.nativeImage(
            SplashView().frame(height: size.height), width: size.width, dark: false,
            size: .large, locale: Locale(identifier: "pt_BR")
        )
        let staticBounds = try markBounds(staticImage, size: size)
        let runtimeBounds = try markBounds(runtime, size: size)
        XCTAssertEqual(runtimeBounds.midX, staticBounds.midX, accuracy: 2)
        XCTAssertEqual(runtimeBounds.midY, staticBounds.midY, accuracy: 2)
        XCTAssertEqual(runtimeBounds.width, staticBounds.width, accuracy: 2)
        XCTAssertEqual(runtimeBounds.height, staticBounds.height, accuracy: 2)
    }

    private func markBounds(_ image: UIImage, size: CGSize) throws -> CGRect {
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(try XCTUnwrap(image.cgImage), in: CGRect(origin: .zero, size: size))
        var points: [CGPoint] = []
        for y in (height / 2 - 56)..<(height / 2 + 56) {
            for x in (width / 2 - 56)..<(width / 2 + 56) {
                let offset = (y * width + x) * 4
                if bytes[offset] > 200 && bytes[offset + 1] > 200 && bytes[offset + 2] > 200 {
                    points.append(CGPoint(x: x, y: y))
                }
            }
        }
        XCTAssertFalse(points.isEmpty)
        let minX = try XCTUnwrap(points.map(\.x).min()), maxX = try XCTUnwrap(points.map(\.x).max())
        let minY = try XCTUnwrap(points.map(\.y).min()), maxY = try XCTUnwrap(points.map(\.y).max())
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func testTabBarKeepsFiveAccessibleTargetsAtCompactAXXXL() {
        for language in SupportedAppLanguage.allCases {
            let bar = PerformeTabBar(selection: .constant(.today), language: language)
            let probes = PremiumRenderingTestSupport.accessibilityProbe(
                bar, width: 375, size: .accessibility5
            )
            for tab in AppTab.displayOrder {
                let targets = probes.filter { $0.label == tab.title(for: language) && $0.isButton }
                XCTAssertEqual(targets.count, 1, "\(tab): \(probes)")
                guard let target = targets.first else { continue }
                // UIKit populates the external AX frame through the system
                // service; this in-process hosting probe sees CGRect.zero.
                // Measure its laid-out native bounds here. The UI test checks
                // actual screen frames, containment, order and hit targets.
                guard let bounds = target.nativeBounds else {
                    XCTFail("Navigation must expose one real native control")
                    continue
                }
                XCTAssertGreaterThanOrEqual(bounds.width, 44)
                XCTAssertGreaterThanOrEqual(bounds.height, 44)
                XCTAssertLessThanOrEqual(bounds.width, 375 / 5)
            }
        }
    }

    func testSixBrandStatesRenderWithReducedMotionAndHighContrast() {
        for state in PerformeBrandState.allCases {
            let brand = PerformeBrandAction(state: state, label: "Registrar", selected: state == .active)
                .environment(\.bodyFlowReduceMotion, true)
                .environment(\.bodyFlowVisualPolicy, BodyFlowVisualPolicy(reduceMotion: true, increasedContrast: true))
            let frame = PremiumRenderingTestSupport.fittingSize(
                brand, width: 100, dark: true, size: .accessibility5, locale: Locale(identifier: "pt_BR")
            )
            XCTAssertLessThanOrEqual(frame.width, 100)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
        }
    }

    func testNavigationAtAXXXLKeepsItsControlsWithinOneCompactBar() {
        for language in SupportedAppLanguage.allCases {
            for width: CGFloat in [375, 440] {
                for dark in [false, true] {
                    let bar = PerformeTabBar(selection: .constant(.today), language: language)
                    let locale = language.formattingLocale
                    let size = PremiumRenderingTestSupport.fittingSize(
                        bar, width: width, dark: dark, size: .accessibility5, locale: locale
                    )
                    XCTAssertLessThanOrEqual(
                        size.height, 96,
                        "Navigation must reserve a compact bar for five complete labels and the LCV, not consume the content viewport"
                    )
                    let attachment = XCTAttachment(image: PremiumRenderingTestSupport.nativeImage(
                        bar, width: width, dark: dark, size: .accessibility5, locale: locale
                    ))
                    attachment.name = "navigation-axxxl-\(language)-\(Int(width))-\(dark ? "dark" : "light")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
