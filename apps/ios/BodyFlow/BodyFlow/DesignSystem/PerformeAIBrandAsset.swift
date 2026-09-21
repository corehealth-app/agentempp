import Foundation
import UIKit

/// Approved Performe AI Signal Spark resources. Historical BodyFlow artwork remains separate.
enum PerformeAIBrandAsset: String, CaseIterable {
    case symbolLight, symbolDark, symbolMono, symbolNegative
    case wordmarkLight, wordmarkDark, lockup

    var resourceName: String {
        switch self {
        case .symbolLight: "PerformeAISymbolLightV1"
        case .symbolDark: "PerformeAISymbolDarkV1"
        case .symbolMono: "PerformeAISymbolMonoV1"
        case .symbolNegative: "PerformeAISymbolNegativeV1"
        case .wordmarkLight: "PerformeAIWordmarkLightV1"
        case .wordmarkDark: "PerformeAIWordmarkDarkV1"
        case .lockup: "PerformeAILockupV1"
        }
    }

    func isAvailable(in bundle: Bundle = .main) -> Bool {
        UIImage(named: resourceName, in: bundle, compatibleWith: nil) != nil
    }
}
