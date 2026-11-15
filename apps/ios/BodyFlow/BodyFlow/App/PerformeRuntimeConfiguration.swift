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
    var todayEnergyRepresentation: TodayEnergyRepresentation = .legacy
    var flowConversationRuntime: FlowConversationRuntimeSelection = .legacy
    var trainingExecutionRuntime: TrainingExecutionRuntimeSelection = .progressV1

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
        var clinicalMode: CurrentClinicalRuntimeMode
        if values[currentClinicalRuntimeKey] == nil { clinicalMode = .legacy }
        else if resolvedString(values[currentClinicalRuntimeKey]) == "current_clinical_v1",
                CurrentClinicalRuntimeComposition.allows(storageOrigin: supabase.origin,
                    apiOrigin: mobileAPI.origin, qaBinding: qaBinding) {
            clinicalMode = .currentV1
        } else { clinicalMode = .unavailable }
        let todayEnergy: TodayEnergyRepresentation
        if values[TodayEnergyRepresentation.infoKey] == nil { todayEnergy = .legacy }
        else if let raw = resolvedString(values[TodayEnergyRepresentation.infoKey]),
                raw == TodayEnergyRepresentation.fieldAvailabilityV1.rawValue,
                clinicalMode == .currentV1, case .candidate = qaBinding {
            todayEnergy = .fieldAvailabilityV1
        } else {
            // An invalid explicit choice cannot silently restore numeric v3.
            todayEnergy = .legacy
            clinicalMode = .unavailable
        }
        let flow = FlowConversationRuntimeSelection.load(values[FlowConversationRuntimeSelection.infoKey])
        var training = TrainingExecutionRuntimeSelection.load(values[TrainingExecutionRuntimeSelection.infoKey])
        if training == .completionV1 {
            if clinicalMode != .currentV1 || (flow != .mealCommandV1 && flow != .neutralIntakeV1) {
                training = .unavailable
            } else if case .candidate = qaBinding {
                // The clinical family above already matched both exact origins.
            } else { training = .unavailable }
        }
        return PerformeRuntimeConfiguration(
            supabase: supabase,
            mobileAPI: mobileAPI,
            currentClinicalRuntimeMode: clinicalMode,
            currentClinicalQABinding: qaBinding,
            todayEnergyRepresentation: todayEnergy,
            flowConversationRuntime: flow,
            trainingExecutionRuntime: training
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
