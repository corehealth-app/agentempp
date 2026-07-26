struct TodaySummary: Decodable, Equatable, Sendable {
    struct Energy: Decodable, Equatable, Sendable {
        let consumedKcal: Int
        let targetKcal: Int
        let remainingFoodKcal: Int

        private enum CodingKeys: String, CodingKey {
            case consumedKcal = "consumed_kcal"
            case targetKcal = "target_kcal"
            case remainingFoodKcal = "remaining_food_kcal"
        }
    }

    struct Routine: Decodable, Equatable, Sendable {
        let statusLabel: String
        let nextItemLabel: String

        private enum CodingKeys: String, CodingKey {
            case statusLabel = "status_label"
            case nextItemLabel = "next_item_label"
        }
    }

    struct NextAction: Decodable, Equatable, Sendable {
        let id: String
        let title: String
        let detail: String
    }

    let localDate: String
    let energy: Energy
    let routine: Routine
    let nextAction: NextAction
    let calculationVersion: String

    private enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case energy
        case routine
        case nextAction = "next_action"
        case calculationVersion = "calculation_version"
    }
}
