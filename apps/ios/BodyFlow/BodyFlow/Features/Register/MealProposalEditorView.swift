import SwiftUI

struct MealProposalEditorSeed {
    let mealType: MealType
    let foodName: String
    let quantityG: String
    let userKcal: String
    let consumedAt: Date

    init(registration: RegistrationSnapshot, initialConsumedAt: Date) {
        let proposal: MealProposalSnapshot
        switch registration.proposal {
        case let .meal(value): proposal = value
        case .workout, .unknown:
            proposal = MealProposalSnapshot(
                mealType: "outro",
                items: [],
                totals: nil,
                warnings: []
            )
        }
        let item = proposal.items.first
        mealType = MealType(rawValue: proposal.mealType) ?? .other
        foodName = item?.name ?? ""
        quantityG = item.map { NSDecimalNumber(decimal: $0.quantityG).stringValue } ?? ""
        userKcal = item?.kcal.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        consumedAt = initialConsumedAt
    }
}

struct MealProposalEditorView: View {
    private let save: @MainActor (MealProposalRequest) -> Void

    @State private var mealType: MealType
    @State private var foodName: String
    @State private var quantityG: String
    @State private var userKcal: String
    @State private var consumedAt: Date

    init(
        registration: RegistrationSnapshot,
        initialConsumedAt: Date,
        isSubmitting: Bool,
        save: @escaping @MainActor (MealProposalRequest) -> Void
    ) {
        let seed = MealProposalEditorSeed(
            registration: registration,
            initialConsumedAt: initialConsumedAt
        )
        _mealType = State(initialValue: seed.mealType)
        _foodName = State(initialValue: seed.foodName)
        _quantityG = State(initialValue: seed.quantityG)
        _userKcal = State(initialValue: seed.userKcal)
        _consumedAt = State(initialValue: seed.consumedAt)
        self.save = save
        _ = isSubmitting
    }

    var body: some View {
        Form {
            Section("Itens") {
                TextField("Alimento", text: $foodName)
                    .accessibilityIdentifier("registration.proposal.edit.food-name")
                TextField("Quantidade (g)", text: $quantityG)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("registration.proposal.edit.quantity")
                TextField("Calorias informadas", text: $userKcal)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("registration.proposal.edit.user-kcal")
            }
            Section("Refeição") {
                Menu {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Button(type.rawValue) { mealType = type }
                    }
                } label: {
                    Text(mealType.rawValue)
                }
                .accessibilityIdentifier("registration.proposal.edit.meal-type")

                DatePicker("Horário", selection: $consumedAt)
                    .accessibilityIdentifier("registration.proposal.edit.consumed-at")
            }
        }
        .accessibilityIdentifier("registration.proposal.editor")
        .navigationTitle("Editar proposta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar", action: saveProposal)
                    .accessibilityIdentifier("registration.proposal.edit.save")
            }
        }
    }

    private func saveProposal() {
        guard let quantity = Decimal(string: quantityG) else { return }
        let kcal = userKcal.isEmpty ? nil : Decimal(string: userKcal)
        save(MealProposalRequest(
            mealType: mealType,
            items: [MealProposalItemRequest(
                foodName: foodName,
                quantityG: quantity,
                userKcal: kcal
            )],
            consumedAt: APITimestamp(value: consumedAt)
        ))
    }

    static func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
