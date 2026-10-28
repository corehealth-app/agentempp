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

    @Test("Current runtime is explicit and restricted to the same staging pair", arguments: [0, 1, 2, 3, 4])
    func currentClinicalBuildSelection(_ mode: Int) throws {
        var values: [String: Any] = [
            "PERFORME_SUPABASE_URL": "https://xitugspwfxkcluxvrdeg.supabase.co",
            "PERFORME_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_synthetic",
            "PERFORME_MOBILE_API_ORIGIN": "https://performe-ai-staging-bff.vercel.app",
        ]
        if mode != 0 { values[PerformeRuntimeConfiguration.currentClinicalRuntimeKey] = "current_clinical_v1" }
        if mode == 2 { values[PerformeRuntimeConfiguration.currentClinicalRuntimeKey] = "unknown" }
        if mode == 3 { values[PerformeRuntimeConfiguration.supabaseURLKey] = "https://xuxehkhdvjivitduarvb.supabase.co" }
        if mode == 4 { values[PerformeRuntimeConfiguration.mobileAPIOriginKey] = "https://other-mobile.example.invalid" }
        let runtime = try #require(PerformeRuntimeConfiguration.load(from: values))
        #expect(runtime.currentClinicalRuntimeMode == (mode == 0 ? .legacy : mode == 1 ? .currentV1 : .unavailable))
    }

    @Test("A build-owned exact preview binding permits candidate QA without canonical promotion")
    func qualifiedPreviewBinding() throws {
        let runtime = try #require(PerformeRuntimeConfiguration.load(from: Self.previewValues()))
        #expect(runtime.currentClinicalRuntimeMode == .currentV1)
    }

    @Test("An explicit invalid preview binding is never ignored for the canonical origin", arguments: [0, 1, 2, 3, 4, 5, 6])
    func invalidPreviewBindingFailsClosed(_ defect: Int) throws {
        var values = Self.previewValues()
        values["PERFORME_MOBILE_API_ORIGIN"] = "https://performe-ai-staging-bff.vercel.app"
        var binding = try #require(values["PERFORME_CURRENT_CLINICAL_QA_BINDING"] as? [String: String])
        switch defect {
        case 0: binding.removeValue(forKey: "receipt_sha256")
        case 1: binding["project_id"] = "prj_other"
        case 2: binding["source_manifest_sha256"] = "HEAD"
        case 3: binding["region"] = "iad1"
        case 4: binding["origin"] = "https://candidate-qa.vercel.app/path"
        case 5: binding["deployment_id"] = ""
        default: binding["receipt_sha256"] = "$(RECEIPT_DIGEST)"
        }
        values["PERFORME_CURRENT_CLINICAL_QA_BINDING"] = binding
        let runtime = try #require(PerformeRuntimeConfiguration.load(from: values))
        #expect(runtime.currentClinicalRuntimeMode == .unavailable)
    }

    @Test("Preview binding accepts only its exact origin", arguments: [0, 1, 2, 3, 4])
    func previewBindingCannotAuthorizeOtherOrigins(_ mismatch: Int) throws {
        var values = Self.previewValues()
        let origins = ["https://other-qa.vercel.app", "https://candidate-qa.vercel.app.evil.test",
                       "https://candidate-qa.vercel.app:444", "https://performe-ai-staging-bff.vercel.app",
                       "https://candidate-qa.vercel.app"]
        values["PERFORME_MOBILE_API_ORIGIN"] = origins[mismatch]
        if mismatch == 4 { values.removeValue(forKey: "PERFORME_CURRENT_CLINICAL_QA_BINDING") }
        let runtime = try #require(PerformeRuntimeConfiguration.load(from: values))
        #expect(runtime.currentClinicalRuntimeMode == .unavailable)
    }

    private static func previewValues() -> [String: Any] {
        ["PERFORME_SUPABASE_URL": "https://xitugspwfxkcluxvrdeg.supabase.co",
         "PERFORME_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_synthetic",
         "PERFORME_MOBILE_API_ORIGIN": "https://candidate-qa.vercel.app",
         "PERFORME_CURRENT_CLINICAL_RUNTIME": "current_clinical_v1",
         "PERFORME_CURRENT_CLINICAL_QA_BINDING": [
            "origin": "https://candidate-qa.vercel.app",
            "deployment_id": "dpl_syntheticCandidate",
            "project_id": "prj_NTrnUNFXfmddMuci3VWjalfAoejW",
            "source_manifest_sha256": String(repeating: "a", count: 64),
            "receipt_sha256": String(repeating: "b", count: 64),
            "region": "gru1",
         ]]
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
