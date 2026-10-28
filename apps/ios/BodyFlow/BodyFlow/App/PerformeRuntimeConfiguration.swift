import Foundation

struct PerformeRuntimeConfiguration: Equatable, Sendable {
    static let supabaseURLKey = "PERFORME_SUPABASE_URL"
    static let supabasePublishableKey = "PERFORME_SUPABASE_PUBLISHABLE_KEY"
    static let mobileAPIOriginKey = "PERFORME_MOBILE_API_ORIGIN"
    static let currentClinicalRuntimeKey = "PERFORME_CURRENT_CLINICAL_RUNTIME"

    let supabase: SupabaseAuthConfiguration
    let mobileAPI: MobileAPIConfiguration
    var currentClinicalRuntimeMode: CurrentClinicalRuntimeMode = .legacy
    var currentClinicalQABinding: CurrentClinicalQABinding = .absent

    static func load(from values: [String: Any]?) -> PerformeRuntimeConfiguration? {
        guard let values,
              let supabaseURL = resolvedString(values[supabaseURLKey]),
              let publishableKey = resolvedString(values[supabasePublishableKey]),
              let mobileAPIOrigin = resolvedString(values[mobileAPIOriginKey]),
              let supabase = try? SupabaseAuthConfiguration(
                  originString: supabaseURL,
                  key: publishableKey
              ),
              let mobileAPI = try? MobileAPIConfiguration(
                  originString: mobileAPIOrigin
              )
        else {
            return nil
        }
        let qaBinding = CurrentClinicalQABinding.load(from: values[CurrentClinicalQABinding.infoKey])
        let clinicalMode: CurrentClinicalRuntimeMode
        if values[currentClinicalRuntimeKey] == nil { clinicalMode = .legacy }
        else if resolvedString(values[currentClinicalRuntimeKey]) == "current_clinical_v1",
                CurrentClinicalRuntimeComposition.allows(storageOrigin: supabase.origin,
                    apiOrigin: mobileAPI.origin, qaBinding: qaBinding) {
            clinicalMode = .currentV1
        } else { clinicalMode = .unavailable }
        return PerformeRuntimeConfiguration(
            supabase: supabase,
            mobileAPI: mobileAPI,
            currentClinicalRuntimeMode: clinicalMode,
            currentClinicalQABinding: qaBinding
        )
    }

    private static func resolvedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              !candidate.hasPrefix("$("),
              !candidate.hasPrefix("${")
        else {
            return nil
        }
        return candidate
    }
}
