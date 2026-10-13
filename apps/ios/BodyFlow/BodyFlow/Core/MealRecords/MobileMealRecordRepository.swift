import Foundation

struct MobileMealRecordRepository: MealRecordProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func mealRecord(id: String) async throws -> MealRecordResponse {
        let response: MealRecordResponse = try await send(.get, id: id, body: nil, key: nil)
        let value = response.data
        guard value.recordID == id, !value.expectedVersion.isEmpty,
              (1...30).contains(value.items.count), value.itemIDs == value.items.map(\.id),
              Set(value.itemIDs).count == value.itemIDs.count,
              value.itemIDs.contains(id), !(value.editable && value.dayClosed),
              value.scope != .item || value.itemIDs == [id]
        else { throw MealRecordFailure.invalidInput }
        return response
    }

    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        guard attempt.operation == .mealRecordPatch,
              attempt.payload.body.itemIDs == [attempt.payload.recordID],
              (1...30).contains(attempt.payload.body.items.count),
              attempt.payload.body.items.allSatisfy({ !$0.usesNutritionLabel }) else {
            throw MealRecordFailure.invalidInput
        }
        return try await send(.patch, id: attempt.payload.recordID,
            body: encode(attempt.payload.body), key: attempt.key)
    }

    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        guard attempt.operation == .mealRecordDelete,
              (1...30).contains(attempt.payload.body.itemIDs.count),
              Set(attempt.payload.body.itemIDs).count == attempt.payload.body.itemIDs.count
        else { throw MealRecordFailure.invalidInput }
        return try await send(.delete, id: attempt.payload.recordID,
            body: encode(attempt.payload.body), key: attempt.key)
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func send<Payload: Codable & Sendable>(
        _ method: HTTPMethod, id: String, body: Data?, key: IdempotencyKey?
    ) async throws -> MobileResponse<Payload> {
        do {
            let path = "/api/mobile/v1/meal-records/\(try MobileAPIPathSegment.identifier(id))"
            return try await transport.executeEnvelope(MobileAPIRequest(
                method: method, path: path, body: body, idempotencyKey: key
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MobileAPITransportError {
            switch error {
            case .sessionSuperseded: throw CancellationError()
            case .conflict("meal_record_version_changed", _): throw MealRecordFailure.versionChanged
            case .conflict("MEAL_VERSION_CONFLICT", _), .conflict("MEAL_CONTEXT_CHANGED", _),
                 .conflict("MEAL_SELECTION_CONFLICT", _): throw MealRecordFailure.versionChanged
            case .conflict("meal_record_not_editable", _): throw MealRecordFailure.notEditable
            case .conflict("MEAL_DAY_NOT_EDITABLE", _): throw MealRecordFailure.notEditable
            case .conflict("COUNTRY_REQUIRED", _): throw MealRecordFailure.countryRequired
            case .conflict("idempotency_key_conflict", _): throw MealRecordFailure.commandConflict
            case .conflict("IDEMPOTENCY_KEY_CONFLICT", _): throw MealRecordFailure.commandConflict
            case .conflict("idempotency_request_in_progress", _): throw MealRecordFailure.requestInProgress
            case .conflict("IDEMPOTENCY_REQUEST_IN_PROGRESS", _): throw MealRecordFailure.requestInProgress
            case .validation("MEAL_QUANTITY_NOT_REPRESENTABLE", _): throw MealRecordFailure.quantityNotRepresentable
            case .validation("MEAL_NUTRITION_UNRESOLVED", _): throw MealRecordFailure.nutritionUnresolved
            case .validation("MEAL_GROUP_LIMIT_EXCEEDED", _): throw MealRecordFailure.groupLimitExceeded
            case .conflict("MEAL_GROUP_LIMIT_EXCEEDED", _): throw MealRecordFailure.groupLimitChanged
            case .http(404, "meal_record_not_found", _): throw MealRecordFailure.notFound
            case .http(404, "MEAL_RECORD_NOT_FOUND", _): throw MealRecordFailure.notFound
            default: throw MealRecordFailure.capability(error.capabilityError)
            }
        } catch is MobileAPIRequestError {
            throw MealRecordFailure.invalidInput
        } catch let error as BodyFlowCapabilityError {
            throw MealRecordFailure.capability(error)
        }
    }
}
