import Foundation

/// Receives the original session envelope from its owner. No global client,
/// HTTP retry, mutation replay cache or follow-up GET is created here.
struct MobileWorkoutStrengthClarificationRepository: WorkoutStrengthClarificationProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func load(workoutID: String) async throws -> WorkoutStrengthClarificationResponse {
        guard let id = WorkoutStrengthWire.uuid(workoutID) else { throw BodyFlowCapabilityError.invalidInput }
        let response: WorkoutStrengthClarificationResponse = try await send(.get, workoutID: id, body: nil, key: nil)
        guard response.data.workoutID == nil || response.data.workoutID == id else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return response
    }

    func loadWithFeedback(workoutID: String) async throws -> WorkoutStrengthHistoryResponse {
        guard let id = WorkoutStrengthWire.uuid(workoutID) else { throw BodyFlowCapabilityError.invalidInput }
        let response: WorkoutStrengthHistoryResponse = try await send(.get, workoutID: id, body: nil, key: nil,
            queryItems: [URLQueryItem(name: "include", value: "registration_feedback")])
        guard response.data.clarification.workoutID == nil || response.data.clarification.workoutID == id else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return response
    }

    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) async throws -> WorkoutStrengthClarificationResponse {
        guard attempt.operation == .workoutStrengthAnswer else { throw BodyFlowCapabilityError.invalidInput }
        guard WorkoutStrengthWire.uuid(attempt.key.value) != nil else { throw BodyFlowCapabilityError.invalidIdempotencyKey }
        let command = attempt.payload
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(command)
        let response: WorkoutStrengthClarificationResponse = try await send(.post, workoutID: command.question.scope.workoutID, body: body, key: attempt.key)
        guard case let .answered(receipt) = response.data,
              receipt.scope == command.question.scope,
              receipt.questionKey == command.question.questionKey,
              receipt.answer == command.answer else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        // The writer's official answered revision is1, even for an original0
        // replay. A winning operation key is intentionally not public wire.
        return response
    }

    private func send<Payload: Codable & Sendable>(_ method: HTTPMethod, workoutID: String, body: Data?,
        key: IdempotencyKey?, queryItems: [URLQueryItem] = []) async throws -> MobileResponse<Payload> {
        do {
            return try await transport.executeEnvelope(MobileAPIRequest<Payload>(
                method: method, path: "/api/mobile/v1/workouts/\(workoutID)/strength-clarification",
                queryItems: queryItems, body: body, idempotencyKey: key
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch MobileAPITransportError.sessionSuperseded {
            throw CancellationError()
        } catch let error as MobileAPITransportError {
            switch error {
            case .conflict(code: "workout_strength_unavailable", requestID: _):
                throw WorkoutStrengthClarificationError.contextUnavailable
            case .conflict(code: "workout_strength_answer_conflict", requestID: _):
                throw WorkoutStrengthClarificationError.answerConflict
            case .server(status: 503, code: "workout_strength_clarification_unavailable", requestID: _):
                throw WorkoutStrengthClarificationError.disabled
            default: throw error.capabilityError
            }
        } catch let error as BodyFlowCapabilityError {
            throw error
        } catch is MobileAPIRequestError {
            throw BodyFlowCapabilityError.invalidInput
        } catch {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}
