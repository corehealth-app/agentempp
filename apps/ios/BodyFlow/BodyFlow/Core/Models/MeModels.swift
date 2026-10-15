import Foundation

typealias MeResponse = MobileResponse<MeSnapshot>

/// `GET /me`: the account row the BFF exposes for the signed-in patient.
/// Only documented fields are decoded; everything but the id is optional so
/// a partially filled account still resolves.
struct MeSnapshot: Codable, Equatable, Sendable {
    let id: String
    let email: String?
    let name: String?
    let locale: String?
    let timezone: String?
    let country: String?
    let countryConfirmed: Bool?
    let status: String?
    let emailConfirmed: Bool?
    let workoutRegistrationProtocol: String?

    /// Only the exact server-advertised protocol may select a new ui-v1
    /// intention. Pending proposals carry their own version independently.
    var supportsVersionedWorkoutRegistration: Bool {
        workoutRegistrationProtocol == WorkoutRegistrationProtocol.uiV1.rawValue
    }

    init(
        id: String,
        email: String?,
        name: String?,
        locale: String?,
        timezone: String?,
        country: String?,
        countryConfirmed: Bool?,
        status: String?,
        emailConfirmed: Bool?,
        workoutRegistrationProtocol: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.locale = locale
        self.timezone = timezone
        self.country = country
        self.countryConfirmed = countryConfirmed
        self.status = status
        self.emailConfirmed = emailConfirmed
        self.workoutRegistrationProtocol = workoutRegistrationProtocol
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case locale
        case timezone
        case country
        case countryConfirmed = "country_confirmed"
        case status
        case emailConfirmed = "email_confirmed"
        case workoutRegistrationProtocol = "workout_registration_protocol"
    }
}

protocol MeProviding: Sendable {
    func me() async throws -> MeResponse
}
