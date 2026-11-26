import Foundation

struct FlowMealReminder: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case pending, processing, resolved, expired
    }

    let id: UUID
    let localDate: String
    let mealType: MealType
    let state: State

    enum CodingKeys: String, CodingKey {
        case id, state
        case localDate = "local_date"
        case mealType = "meal_type"
    }
}

protocol FlowMealReminderProviding: Sendable {
    func reminder(id: UUID, skip: Bool) async throws -> FlowMealReminder
}

struct MobileFlowMealReminderRepository: FlowMealReminderProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func reminder(id: UUID, skip: Bool) async throws -> FlowMealReminder {
        let response: MobileResponse<FlowMealReminder> = try await transport.executeCapability {
            try MobileAPIRequest(
                method: skip ? .post : .get,
                path: "/api/mobile/v1/conversation/meal-reminders/\(id.uuidString.lowercased())",
                body: skip ? Data(#"{"action":"skipped"}"#.utf8) : nil,
                unauthorizedReplay: skip ? .never : .standard
            )
        }
        guard response.data.id == id, response.data.mealType != .other else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return response.data
    }
}

struct MobileFlowMealPushRepository: Sendable {
    private struct DeviceInput: Encodable {
        struct FlowMealGap: Encodable {
            let daytime_enabled: Bool
        }
        let installation_id: UUID
        let apns_environment: FlowMealPushEnvironment
        let apns_token: String
        let flow_meal_gap: FlowMealGap
    }

    private struct Device: Codable, Sendable {
        let id: UUID
        let installation_id: UUID
        let active: Bool
    }

    private struct DeactivatedDevice: Codable, Sendable {
        let id: UUID
        let active: Bool
    }

    let transport: any MobileAPIEnvelopeExecuting
    private static let devicesPath = "/api/mobile/v1/devices"

    func register(installation: UUID, environment: FlowMealPushEnvironment, token: Data,
                  daytime: Bool) async throws {
        let input = DeviceInput(
            installation_id: installation,
            apns_environment: environment,
            apns_token: token.map { String(format: "%02x", $0) }.joined(),
            flow_meal_gap: .init(daytime_enabled: daytime)
        )
        let response: MobileResponse<Device> = try await transport.executeCapability {
            try MobileAPIRequest(method: .post, path: Self.devicesPath,
                                 body: JSONEncoder().encode(input))
        }
        guard response.data.active, response.data.installation_id == installation else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }

    func unregister(installation: UUID) async throws {
        // Read first so a registration whose response was interrupted can
        // still be withdrawn, and other devices keep their own preferences.
        let response: MobileResponse<[Device]> = try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: Self.devicesPath)
        }
        guard let device = response.data.first(where: { $0.installation_id == installation && $0.active }) else {
            return
        }
        let result: MobileResponse<DeactivatedDevice> = try await transport.executeCapability {
            try MobileAPIRequest(method: .delete,
                                 path: Self.devicesPath + "/" + device.id.uuidString.lowercased())
        }
        guard result.data.id == device.id, !result.data.active else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}

struct FlowMealReminderSource: Sendable {
    let transport: MobileAPITransport
    let lifecycle: any SessionLifecycleProviding
    let pushEnvironment: FlowMealPushEnvironment?

    func scopedTransport(expectedUserID: String) async throws -> MobileAPITransport {
        let lease = try await lifecycle.leaseForRequest()
        guard let expected = UUID(uuidString: expectedUserID),
              UUID(uuidString: lease.userID) == expected else {
            throw SessionLifecycleError.sessionSuperseded
        }
        let scoped = transport.scoped(to: lease)
        try await scoped.validateOriginalSession(lease)
        return scoped
    }
}
