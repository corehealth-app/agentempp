import Foundation
import Testing

@testable import BodyFlow

@Suite("Performe Runtime Configuration")
struct PerformeRuntimeConfigurationTests {
    @Test("complete public runtime values install Supabase auth and Mobile API origins")
    func loadsCompleteConfiguration() throws {
        let configuration = try #require(PerformeRuntimeConfiguration.load(from: [
            "PERFORME_SUPABASE_URL": "https://project.example.test",
            "PERFORME_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_synthetic",
            "PERFORME_MOBILE_API_ORIGIN": "https://mobile.example.test",
        ]))

        #expect(configuration.supabase.origin.absoluteString == "https://project.example.test/")
        #expect(configuration.mobileAPI.origin.absoluteString == "https://mobile.example.test/")
    }

    @Test("missing or unresolved build settings fail closed")
    func rejectsIncompleteConfiguration() {
        #expect(PerformeRuntimeConfiguration.load(from: [:]) == nil)
        #expect(PerformeRuntimeConfiguration.load(from: [
            "PERFORME_SUPABASE_URL": "$(PERFORME_SUPABASE_URL)",
            "PERFORME_SUPABASE_PUBLISHABLE_KEY": "$(PERFORME_SUPABASE_PUBLISHABLE_KEY)",
            "PERFORME_MOBILE_API_ORIGIN": "$(PERFORME_MOBILE_API_ORIGIN)",
        ]) == nil)
    }

    @Test("client runtime rejects service role material and unsafe origins")
    func rejectsUnsafeConfiguration() {
        #expect(PerformeRuntimeConfiguration.load(from: [
            "PERFORME_SUPABASE_URL": "http://project.example.test",
            "PERFORME_SUPABASE_PUBLISHABLE_KEY": "sb_secret_server_only",
            "PERFORME_MOBILE_API_ORIGIN": "https://mobile.example.test/path",
        ]) == nil)
    }
}
