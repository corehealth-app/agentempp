import SwiftUI
import Testing

@testable import BodyFlow

@Suite("Onboarding presentation policies")
struct OnboardingPresentationTests {
    @Test("release resolves synthetic consent presentation as unavailable")
    func releaseHidesSyntheticConsentPresentation() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing"],
            buildFlavor: .release
        )

        #expect(configuration.developmentConsentAvailability == .unavailable)
    }

    @MainActor
    @Test("development consent exposes its legacy group and child identifiers")
    func developmentConsentAccessibilityIdentifiers() {
        var visitedObjects: Set<ObjectIdentifier> = []
        let presentationStrings = reflectedStrings(
            in: ConsentStepView(model: .preview(step: .consent)).body,
            visitedObjects: &visitedObjects
        )

        #expect(presentationStrings.contains("onboarding.development-consent"))
        #expect(presentationStrings.contains("consent.terms"))
        #expect(presentationStrings.contains("consent.privacy"))
    }

    @Test("the root renders a flow model only for the active onboarding user")
    func rootRenderRequiresMatchingUser() {
        #expect(OnboardingRootLoadState.canRender(
            modelUserID: "user-a",
            activeUserID: "user-a"
        ))
        #expect(!OnboardingRootLoadState.canRender(
            modelUserID: "user-a",
            activeUserID: "user-b"
        ))
    }

    @Test("a newer load attempt supersedes an older attempt for the same user")
    func newerLoadSupersedesOlderAttempt() {
        var state = OnboardingRootLoadState()
        let attemptA = state.begin(for: "fixture-user")
        let attemptB = state.begin(for: "fixture-user")

        #expect(!state.canPublish(
            attemptA,
            activeUserID: "fixture-user",
            isCancelled: false
        ))
        #expect(state.canPublish(
            attemptB,
            activeUserID: "fixture-user",
            isCancelled: false
        ))
    }

    @Test("a cancelled or identity-mismatched load cannot publish")
    func cancelledLoadCannotPublish() {
        var state = OnboardingRootLoadState()
        let attempt = state.begin(for: "fixture-user")

        #expect(!state.canPublish(
            attempt,
            activeUserID: "fixture-user",
            isCancelled: true
        ))
        #expect(!state.canPublish(
            attempt,
            activeUserID: "other-user",
            isCancelled: false
        ))
    }

    @Test("body fat is optional and exposes its name and unit to accessibility")
    func bodyFatDescriptorIsExplicitlyOptional() {
        let descriptor = OnboardingDecimalFieldDescriptor.bodyFat

        #expect(descriptor.prompt == "Opcional")
        #expect(descriptor.accessibilityLabel == "Gordura corporal")
        #expect(descriptor.unit == "%")
        #expect(descriptor.accessibilityValue(for: nil) == "Não informado, %")
        #expect(descriptor.accessibilityValue(for: 25.5) == "25,5 %")
    }

    @Test("height and weight retain coherent prompts, labels and units")
    func requiredBodyDescriptorsRemainCoherent() {
        #expect(OnboardingDecimalFieldDescriptor.height.prompt == "0")
        #expect(OnboardingDecimalFieldDescriptor.height.accessibilityLabel == "Altura")
        #expect(OnboardingDecimalFieldDescriptor.height.unit == "cm")
        #expect(OnboardingDecimalFieldDescriptor.height.accessibilityValue(for: 170) == "170 cm")

        #expect(OnboardingDecimalFieldDescriptor.weight.prompt == "0")
        #expect(OnboardingDecimalFieldDescriptor.weight.accessibilityLabel == "Peso")
        #expect(OnboardingDecimalFieldDescriptor.weight.unit == "kg")
        #expect(OnboardingDecimalFieldDescriptor.weight.accessibilityValue(for: nil) == "Não informado, kg")
    }

    @MainActor
    @Test("onboarding validation exposes the matching hint and announcement")
    func onboardingValidationAccessibilityText() {
        let model = OnboardingFlowModel.preview(
            step: .welcome,
            validationIssues: [.displayNameRequired, .countryInvalid]
        )

        #expect(
            model.accessibilityHint(for: [.displayNameRequired])
                == "Erro: Informe como você quer ser chamado."
        )
        #expect(
            FormAccessibilityText.validationAnnouncement(
                messages: model.validationIssues.map(\.message)
            )
                == "Erros no formulário: Informe como você quer ser chamado. Confirme um país válido."
        )
    }

    private func reflectedStrings(
        in value: Any,
        depth: Int = 0,
        visitedObjects: inout Set<ObjectIdentifier>
    ) -> Set<String> {
        guard depth < 24 else { return [] }
        if let string = value as? String {
            return [string]
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .class {
            let identifier = ObjectIdentifier(value as AnyObject)
            guard visitedObjects.insert(identifier).inserted else {
                return []
            }
        }

        return mirror.children.reduce(into: Set<String>()) { strings, child in
            strings.formUnion(reflectedStrings(
                in: child.value,
                depth: depth + 1,
                visitedObjects: &visitedObjects
            ))
        }
    }
}
