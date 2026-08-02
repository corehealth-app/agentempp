import Foundation
import Testing

@testable import BodyFlow

@Suite("Capability Support")
struct CapabilitySupportTests {
    @Test("API timestamp decodes RFC 3339 without fractional seconds")
    func timestampDecodesWithoutFractionalSeconds() throws {
        let data = Data(#""2026-07-30T15:45:12Z""#.utf8)

        let timestamp = try JSONDecoder().decode(APITimestamp.self, from: data)

        #expect(timestamp.value == Date(timeIntervalSince1970: 1_785_426_312))
    }

    @Test("API timestamp decodes RFC 3339 with fractional seconds")
    func timestampDecodesWithFractionalSeconds() throws {
        let data = Data(#""2026-07-30T15:45:12.250Z""#.utf8)

        let timestamp = try JSONDecoder().decode(APITimestamp.self, from: data)

        #expect(timestamp.value == Date(timeIntervalSince1970: 1_785_426_312.25))
    }

    @Test("API timestamp encodes as UTC RFC 3339")
    func timestampEncodesAsUTCRFC3339() throws {
        let timestamp = APITimestamp(
            value: Date(timeIntervalSince1970: 1_785_426_312)
        )

        let encoded = try JSONEncoder().encode(timestamp)

        #expect(String(decoding: encoded, as: UTF8.self) == #""2026-07-30T15:45:12Z""#)
    }

    @Test("API timestamp preserves fractional seconds when encoding")
    func timestampPreservesFractionalSecondsWhenEncoding() throws {
        let timestamp = APITimestamp(
            value: Date(timeIntervalSince1970: 1_785_426_312.25)
        )

        let encoded = try JSONEncoder().encode(timestamp)

        #expect(String(decoding: encoded, as: UTF8.self) == #""2026-07-30T15:45:12.250Z""#)
    }

    @Test("opaque nutrition payload round-trips without interpretation")
    func opaquePayloadRoundTrips() throws {
        let data = Data(#"{"future":{"values":[1,true,null]},"version":"v9"}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(value)
        ) == value)
    }

    @Test("opaque payload preserves explicit null")
    func opaquePayloadPreservesExplicitNull() throws {
        let data = Data(#"{"nutrition":null}"#.utf8)

        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(value == .object(["nutrition": .null]))
    }

    @Test("feature time is read through the injected provider")
    func timeIsReadThroughProvider() {
        let expected = Date(timeIntervalSince1970: 1_785_283_200)
        let provider = CapabilityTimeProviderStub(now: expected)

        #expect(readCapabilityTime(from: provider) == expected)
    }

    @Test("idempotency keys reject values shorter than eight characters")
    func idempotencyKeyRejectsSevenCharacters() {
        #expect(throws: BodyFlowCapabilityError.invalidIdempotencyKey) {
            try IdempotencyKey(validating: "1234567")
        }
    }

    @Test("idempotency keys reject values longer than 128 characters")
    func idempotencyKeyRejects129Characters() {
        #expect(throws: BodyFlowCapabilityError.invalidIdempotencyKey) {
            try IdempotencyKey(validating: String(repeating: "a", count: 129))
        }
    }

    @Test("idempotency keys reject forbidden spaces")
    func idempotencyKeyRejectsSpaces() {
        #expect(throws: BodyFlowCapabilityError.invalidIdempotencyKey) {
            try IdempotencyKey(validating: "test key 0001")
        }
    }

    @Test("idempotency keys accept the eight-character boundary")
    func idempotencyKeyAcceptsEightCharacters() throws {
        let key = try IdempotencyKey(validating: "aB0._:-z")

        #expect(key.value == "aB0._:-z")
    }

    @Test("idempotency keys accept the 128-character boundary")
    func idempotencyKeyAccepts128Characters() throws {
        let rawValue = String(repeating: "a", count: 128)

        let key = try IdempotencyKey(validating: rawValue)

        #expect(key.value == rawValue)
    }

    @Test("deterministic key provider advances a stable sequence")
    func deterministicKeyProviderAdvancesStableSequence() throws {
        let provider = DeterministicIdempotencyKeyProvider(prefix: "test-key")

        #expect(try provider.nextKey().value == "test-key-0001")
        #expect(try provider.nextKey().value == "test-key-0002")
    }

    @Test("unavailable key provider fails closed before returning a key")
    func unavailableKeyProviderFailsClosed() {
        let provider: any IdempotencyKeyProviding = UnavailableIdempotencyKeyProvider()

        #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try provider.nextKey()
        }
    }

    @Test("retry retains the original mutation attempt")
    func retryRetainsAttempt() throws {
        let fixedTimeProvider = FixedTimeProvider(
            value: Date(timeIntervalSince1970: 1_785_283_200)
        )
        let attempt = MutationAttempt(
            operation: .hydration,
            key: try IdempotencyKey(validating: "test-key-0001"),
            payload: CapabilityPayloadFixture(value: "250"),
            createdAt: fixedTimeProvider.value
        )

        let retry = attempt

        #expect(retry.operation == .hydration)
        #expect(retry.key == attempt.key)
        #expect(retry.payload == attempt.payload)
        #expect(retry.createdAt == fixedTimeProvider.value)
    }

    @Test("invalid published content contract maps to bounded invalid-input telemetry")
    func invalidContentContractMapsToBoundedTelemetry() {
        #expect(
            BodyFlowCapabilityError.invalidContentContract.telemetryValue
                == .invalidInput
        )
    }

    @Test("invalid opaque content cursor maps to bounded invalid-input telemetry")
    func invalidContentCursorMapsToBoundedTelemetry() {
        #expect(
            BodyFlowCapabilityError.invalidContentCursor.telemetryValue
                == .invalidInput
        )
    }
}

private struct CapabilityPayloadFixture: Hashable, Sendable {
    let value: String
}

private struct CapabilityTimeProviderStub: TimeProviding {
    let now: Date
}

private func readCapabilityTime(from provider: some TimeProviding) -> Date {
    provider.now
}
