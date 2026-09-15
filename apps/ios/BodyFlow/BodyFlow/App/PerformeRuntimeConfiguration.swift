import Foundation

struct PerformeRuntimeConfiguration: Equatable, Sendable {
    static let supabaseURLKey = "PERFORME_SUPABASE_URL"
    static let supabasePublishableKey = "PERFORME_SUPABASE_PUBLISHABLE_KEY"
    static let mobileAPIOriginKey = "PERFORME_MOBILE_API_ORIGIN"

    let supabase: SupabaseAuthConfiguration
    let mobileAPI: MobileAPIConfiguration

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
        return PerformeRuntimeConfiguration(
            supabase: supabase,
            mobileAPI: mobileAPI
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
