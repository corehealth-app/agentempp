import Foundation
@testable import BodyFlow

/// Controlled unit fixture for the integrated Today v4 wire contract. This is
/// not a provider response, clinical prescription or connected QA observation.
enum TodayFieldAvailabilityFixture {
    static func response(_ change: (inout [String: Any]) throws -> Void = { _ in }) throws -> TodayResponse {
        var root = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
        var data = root["data"] as! [String: Any]
        try change(&data)
        root["data"] = data
        return try JSONDecoder().decode(TodayResponse.self, from: JSONSerialization.data(withJSONObject: root))
    }

    static let payload = #"""
    {"data":{
      "local_date":"2026-11-05","protocol":"recomposicao","current_protocol":"recomposicao",
      "clinical_policy":{"version":1,"observed_at":"2026-11-05T12:00:00.123456Z","assessment":"complete","recording_allowed":true,"pause_weight_loss_guidance":false,"professional_assessment_recommended":false,"phase_selection_pending":false,"target_source":"assigned_phase","hide":{"objective":false,"calories":false,"protein":false,"balance":false,"block":false}},
      "targets":{"calories_kcal":1900,"protein_g":130,"source":"daily_snapshot","calories_source":"daily_snapshot","protein_source":"daily_snapshot"},
      "consumed":{"calories_kcal":1200,"protein_g":90.5,"carbs_g":110.25,"fat_g":42.75,"source":"daily_snapshot"},
      "remaining_food_kcal":700,"food_excess_kcal":0,
      "exercise_kcal":null,"exercise_energy":{"status":"unavailable","reason":"unknown_workout_energy"},
      "daily_balance_kcal":null,"daily_balance_reference_kcal":null,"daily_balance_includes_exercise":null,"daily_balance_status":"provisional",
      "daily_balance_energy":{"status":"unavailable","reason":"unknown_workout_energy"},
      "protein_status":{"consumed_g":90.5,"target_g":130,"remaining_g":39.5,"percentage":70,"status":"below_target"},
      "meals":[{"id":"unit-meal","meal_type":"almoco","food_name":"Arroz cozido","quantity_g":200,"kcal":260,"protein_g":5,"carbs_g":56,"fat_g":0.4,"consumed_at":"2026-11-05T11:30:00Z","nutrition_source":"daily_snapshot"}],
      "workouts":[{"id":"unit-known-workout","workout_type":"caminhada","duration_min":30,"estimated_kcal":120,"intensity":null,"performed_at":"2026-11-05T09:00:00Z"},{"id":"unit-unknown-workout","workout_type":"musculacao","duration_min":null,"estimated_kcal":null,"intensity":null,"performed_at":"2026-11-05T10:00:00Z"}],
      "hydration":{"consumed_ml":750,"target_ml":2000,"remaining_ml":1250,"percentage":38,"status":"in_progress"},
      "supplements":{"availability":"available","items":[]},"medications":{"availability":"available","items":[]},
      "pending_actions":{"registrations":[],"meal_gaps":{"expected":[],"registered":[],"skipped":[],"open":[],"reliable":false,"source":"unavailable","active_days":0}},
      "block_7700":{"enabled":true,"availability":"available","target_kcal":7700,"current_kcal":300,"percentage":4,"completed_blocks":2,"total_credited_kcal":15700,"source":"user_progress"},
      "completion_status":{"status":"pending_information","day_closed":false,"has_sufficient_data":null},
      "sources":{"targets":"daily_snapshot","consumed":"daily_snapshot","exercise":"daily_snapshot","meals":"meal_logs","workouts":"workout_logs","hydration":"daily_snapshot","hydration_target":"daily_snapshot","supplements":"routine_items_and_adherence_logs","medications":"routine_items_and_adherence_logs","pending_actions":"pending_registrations_and_meal_pattern","block_7700":"user_progress"},
      "calculation_version":"bodyflow.daily-state.v4","updated_at":null,"generated_at":"2026-11-05T12:00:00.123456Z"
    },"meta":{"api_version":"v1","request_id":"unit-today-field-availability"}}
    """#
}
