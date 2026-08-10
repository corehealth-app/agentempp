import Foundation

typealias PlanResponse = MobileResponse<PlanSnapshot>

struct PlanSnapshot: Codable, Equatable, Sendable {
    let training: TrainingPlanSnapshot?
    let nutrition: [NutritionPrescriptionSnapshot]
}

struct TrainingPlanSnapshot: Codable, Equatable, Sendable {
    let id: String
    let planType: String
    let daysPerWeek: Int
    let equipmentSummary: String?
    let generatedAt: APITimestamp
    let validUntil: APITimestamp?
    let version: Int?
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case planType = "plan_type"
        case daysPerWeek = "days_per_week"
        case equipmentSummary = "equipment_summary"
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case version
        case notes
    }
}

struct NutritionPrescriptionSnapshot: Codable, Equatable, Sendable {
    let id: String
    let type: String
    let payload: JSONValue?
    let generatedAt: APITimestamp
    let validUntil: APITimestamp?
    let version: Int?
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case version
        case notes
    }
}
