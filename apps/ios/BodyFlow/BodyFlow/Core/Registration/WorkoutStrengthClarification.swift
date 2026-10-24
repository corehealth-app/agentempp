import Foundation

typealias WorkoutStrengthClarificationResponse = MobileResponse<WorkoutStrengthClarification>

/// Validated server identity. Never substitutes a pending registration ID.
struct WorkoutStrengthScope: Hashable, Sendable {
    let workoutID: String
    let lifecycleKey: String

    init?(workoutID: String, lifecycleKey: String) {
        guard let workout = WorkoutStrengthWire.uuid(workoutID),
              let lifecycle = WorkoutStrengthWire.uuid(lifecycleKey) else { return nil }
        self.workoutID = workout
        self.lifecycleKey = lifecycle
    }
}

struct WorkoutStrengthQuestion: Hashable, Sendable {
    let scope: WorkoutStrengthScope
    let factRevision: Int
    let questionKey: String

    init?(workoutID: String, lifecycleKey: String, factRevision: Int, questionKey: String) {
        guard factRevision == 0,
              let scope = WorkoutStrengthScope(workoutID: workoutID, lifecycleKey: lifecycleKey),
              let question = WorkoutStrengthWire.uuid(questionKey) else { return nil }
        self.scope = scope
        self.factRevision = factRevision
        self.questionKey = question
    }
}

enum WorkoutStrengthAnswer: String, Codable, Hashable, Sendable { case yes, no }

struct WorkoutStrengthAnswerReceipt: Hashable, Sendable {
    let scope: WorkoutStrengthScope
    let questionKey: String
    let answer: WorkoutStrengthAnswer
    /// Official UTC with all six fractional digits; never converted to Date.
    let acceptedAt: String

    init?(scope: WorkoutStrengthScope, questionKey: String, answer: WorkoutStrengthAnswer, acceptedAt: String) {
        guard let question = WorkoutStrengthWire.uuid(questionKey),
              WorkoutStrengthWire.isUTC6(acceptedAt) else { return nil }
        self.scope = scope
        self.questionKey = question
        self.answer = answer
        self.acceptedAt = acceptedAt
    }
}

/// The four closed public states. Unknown/partial wire never authorizes an answer.
enum WorkoutStrengthClarification: Codable, Hashable, Sendable {
    case unanswered(WorkoutStrengthQuestion)
    case answered(WorkoutStrengthAnswerReceipt)
    case notApplicable(WorkoutStrengthScope)
    case unavailable

    var workoutID: String? {
        switch self {
        case let .unanswered(question): question.scope.workoutID
        case let .answered(receipt): receipt.scope.workoutID
        case let .notApplicable(scope): scope.workoutID
        case .unavailable: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case status, reason, receipt
        case workoutID = "workout_id"
        case lifecycleKey = "lifecycle_key"
        case factRevision = "fact_revision"
        case questionKey = "question_key"
    }
    private enum ReceiptKeys: String, CodingKey {
        case answer
        case acceptedAt = "accepted_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        if status == "unavailable" {
            try WorkoutStrengthWire.requireKeys(["status", "reason"], decoder: decoder)
            guard try container.decode(String.self, forKey: .reason) == "provenance_gap" else {
                throw Self.invalid(decoder)
            }
            self = .unavailable
            return
        }
        let keys = ["status", "workout_id", "lifecycle_key", "fact_revision"]
        switch status {
        case "unanswered": try WorkoutStrengthWire.requireKeys(keys + ["question_key"], decoder: decoder)
        case "answered": try WorkoutStrengthWire.requireKeys(keys + ["question_key", "receipt"], decoder: decoder)
        case "not_applicable": try WorkoutStrengthWire.requireKeys(keys, decoder: decoder)
        default: throw Self.invalid(decoder)
        }
        let workout = try container.decode(String.self, forKey: .workoutID)
        let lifecycle = try container.decode(String.self, forKey: .lifecycleKey)
        let revision = try container.decode(Int.self, forKey: .factRevision)
        guard let scope = WorkoutStrengthScope(workoutID: workout, lifecycleKey: lifecycle) else {
            throw Self.invalid(decoder)
        }
        switch status {
        case "unanswered":
            guard let question = try WorkoutStrengthQuestion(workoutID: workout, lifecycleKey: lifecycle,
                factRevision: revision, questionKey: container.decode(String.self, forKey: .questionKey)) else {
                throw Self.invalid(decoder)
            }
            self = .unanswered(question)
        case "answered":
            guard revision == 1 else { throw Self.invalid(decoder) }
            let receiptDecoder = try container.superDecoder(forKey: .receipt)
            try WorkoutStrengthWire.requireKeys(["answer", "accepted_at"], decoder: receiptDecoder)
            let value = try receiptDecoder.container(keyedBy: ReceiptKeys.self)
            guard let receipt = try WorkoutStrengthAnswerReceipt(scope: scope,
                questionKey: container.decode(String.self, forKey: .questionKey),
                answer: value.decode(WorkoutStrengthAnswer.self, forKey: .answer),
                acceptedAt: value.decode(String.self, forKey: .acceptedAt)) else {
                throw Self.invalid(decoder)
            }
            self = .answered(receipt)
        default:
            guard revision == 0 else { throw Self.invalid(decoder) }
            self = .notApplicable(scope)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .unanswered(question):
            try container.encode("unanswered", forKey: .status)
            try container.encode(question.scope.workoutID, forKey: .workoutID)
            try container.encode(question.scope.lifecycleKey, forKey: .lifecycleKey)
            try container.encode(question.factRevision, forKey: .factRevision)
            try container.encode(question.questionKey, forKey: .questionKey)
        case let .answered(receipt):
            try container.encode("answered", forKey: .status)
            try container.encode(receipt.scope.workoutID, forKey: .workoutID)
            try container.encode(receipt.scope.lifecycleKey, forKey: .lifecycleKey)
            try container.encode(1, forKey: .factRevision)
            try container.encode(receipt.questionKey, forKey: .questionKey)
            var value = container.nestedContainer(keyedBy: ReceiptKeys.self, forKey: .receipt)
            try value.encode(receipt.answer, forKey: .answer)
            try value.encode(receipt.acceptedAt, forKey: .acceptedAt)
        case let .notApplicable(scope):
            try container.encode("not_applicable", forKey: .status)
            try container.encode(scope.workoutID, forKey: .workoutID)
            try container.encode(scope.lifecycleKey, forKey: .lifecycleKey)
            try container.encode(0, forKey: .factRevision)
        case .unavailable:
            try container.encode("unavailable", forKey: .status)
            try container.encode("provenance_gap", forKey: .reason)
        }
    }

    private static func invalid(_ decoder: any Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid workout strength clarification"))
    }
}

struct WorkoutStrengthAnswerCommand: Encodable, Hashable, Sendable {
    let question: WorkoutStrengthQuestion
    let answer: WorkoutStrengthAnswer

    private enum CodingKeys: String, CodingKey {
        case expectedLifecycleKey = "expected_lifecycle_key"
        case expectedFactRevision = "expected_fact_revision"
        case questionKey = "question_key"
        case answer
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(question.scope.lifecycleKey, forKey: .expectedLifecycleKey)
        try container.encode(question.factRevision, forKey: .expectedFactRevision)
        try container.encode(question.questionKey, forKey: .questionKey)
        try container.encode(answer, forKey: .answer)
    }
}

protocol WorkoutStrengthClarificationProviding: Sendable {
    func load(workoutID: String) async throws -> WorkoutStrengthClarificationResponse
    func loadWithFeedback(workoutID: String) async throws -> WorkoutStrengthHistoryResponse
    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) async throws -> WorkoutStrengthClarificationResponse
}

enum WorkoutStrengthClarificationError: Error, Equatable, Sendable {
    case contextUnavailable
    case answerConflict
    case disabled
}

/// Domain-only validation; generic identifier/key contracts remain unchanged.
enum WorkoutStrengthWire {
    static func uuid(_ value: String) -> String? {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return nil }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard byte == 45 else { return nil }
            } else if !(48...57).contains(byte) && !(65...70).contains(byte) && !(97...102).contains(byte) {
                return nil
            }
        }
        return value.lowercased()
    }

    static func isUTC6(_ value: String) -> Bool {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$"#,
            options: .regularExpression) == (value.startIndex..<value.endIndex) else { return false }
        let bytes = Array(value.utf8)
        func two(_ offset: Int) -> Int { Int(bytes[offset] - 48) * 10 + Int(bytes[offset + 1] - 48) }
        let year = two(0) * 100 + two(2), month = two(5), day = two(8)
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = month == 2 ? (leap ? 29 : 28) : [4, 6, 9, 11].contains(month) ? 30 : 31
        return year >= 1 && (1...12).contains(month) && (1...days).contains(day)
            && two(11) < 24 && two(14) < 60 && two(17) < 60
    }

    static func requireKeys(_ expected: [String], decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: JSONKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(expected) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unexpected workout strength fields"))
        }
    }

    private struct JSONKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
