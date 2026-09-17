import Foundation
import UIKit

/// Optional future resources. Absence never selects or replaces historical artwork.
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
