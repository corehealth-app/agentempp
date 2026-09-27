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
    }
}

protocol MeProviding: Sendable {
    func me() async throws -> MeResponse
}
