import Foundation

extension RegistrationFeedbackV2Snapshot {
    struct Section: Hashable, Sendable {
        enum Key: String, Hashable, Sendable { case saved, items, summary, day, block, education }
        let key: Key
        let text: String
    }

    /// Pinned registration.education.v1 validation, not a local recommendation generator.
    /// A different catalog needs a different reader; historical text is never regenerated for storage.
    func expectedEducation(preferencesKnown: Bool) -> Education {
        let en = locale == .english
        var id: String
        var body: String
        if guidance == .paused {
            id = "clinical_pause"
            body = en
                ? "Your record remains available. Weight-loss guidance is paused; seek a professional assessment before changing your targets."
                : "Seu registro continua disponível. As orientações de perda de peso estão pausadas; procure avaliação profissional antes de alterar suas metas."
        } else {
            switch registration {
            case let .workout(r):
                let type = Self.normalized(r.workoutType)
                if ["caminhada", "walking", "walk"].contains(type) {
                    id = "activity_walking"
                    body = en
                        ? "Walking contributes to an active routine. Its value goes beyond estimated calories; it is a different stimulus from muscle-strengthening exercise."
                        : "A caminhada contribui para uma rotina ativa. Seu valor vai além das calorias estimadas; é um estímulo diferente dos exercícios de fortalecimento muscular."
                } else if ["musculacao", "treino de forca", "strength training", "resistance training"].contains(type) {
                    id = "activity_strength"
                    body = en
                        ? "This strength session records a muscle-strengthening stimulus. Energy expenditure alone does not describe the session; sets, repetitions and load help track its execution."
                        : "Este treino de força registra um estímulo de fortalecimento muscular. O gasto energético sozinho não descreve a sessão; séries, repetições e carga ajudam a acompanhar sua execução."
                } else {
                    id = "activity_general"
                    body = en
                        ? "This activity contributes to your movement routine. Estimated expenditure varies with duration and intensity and is not a measurement of muscle gain."
                        : "Esta atividade contribui para sua rotina de movimento. O gasto estimado varia com duração e intensidade e não mede ganho de massa muscular."
                }
            case let .meal(r):
                let names = r.items.map { Self.normalized($0.foodName) }
                if names.contains(where: { ["leite", "leite integral"].contains($0) }) &&
                    names.contains(where: { ["whey", "whey protein", "whey protein em po"].contains($0) }) {
                    id = "milk_whey"
                    body = en
                        ? "Milk and whey both contribute to the protein shown for this drink. The scoop is an editable reference; checking the label helps account for differences between products."
                        : "Leite e whey contribuem juntos para a proteína mostrada nesta bebida. A medida é uma referência editável; conferir o rótulo ajuda a considerar diferenças entre produtos."
                } else if r.totals.proteinG > 0 {
                    id = "meal_protein"
                    // A validated meal is nonempty. Ties preserve the first saved item, as on the server.
                    let energy = r.items.dropFirst().reduce(r.items[0]) { $0.nutrients.kcal >= $1.nutrients.kcal ? $0 : $1 }
                    let protein = r.items.dropFirst().reduce(r.items[0]) { $0.nutrients.proteinG >= $1.nutrients.proteinG ? $0 : $1 }
                    body = en
                        ? "Among the recorded items, \(energy.foodName) has the largest energy contribution and \(protein.foodName) the largest protein contribution. Changing a portion affects both energy and nutrients; compare the items before deciding what to adjust."
                        : "Entre os itens registrados, \(energy.foodName) tem a maior contribuição de energia e \(protein.foodName) a maior contribuição de proteína. Mudar uma porção afeta a energia e os nutrientes; compare os itens antes de decidir o que ajustar."
                } else if r.totals.kcal > 0 {
                    id = "meal_energy"
                    body = en
                        ? "The portions determine the energy shown for this meal. Check the individual items to see which contributes most; one record alone does not define the quality of your whole day."
                        : "As porções determinam a energia mostrada nesta refeição. Confira os itens para ver qual contribui mais; um registro isolado não define a qualidade de todo o seu dia."
                } else {
                    id = "meal_general"
                    body = en
                        ? "This record preserves the amounts you provided. If the food or preparation changes, editing the item updates its calculation without recording the meal again."
                        : "Este registro preserva as quantidades informadas. Se o alimento ou preparo mudar, editar o item atualiza seu cálculo sem registrar a refeição outra vez."
                }
            }
        }
        if guidance == .available && day?.currentProtocol == "ganho_massa" {
            body += en
                ? " For your current goal, follow the whole routine rather than interpreting this event as muscle gain."
                : " No seu objetivo atual, acompanhe o conjunto da rotina sem interpretar este evento como ganho de massa."
        } else if guidance == .available && day?.currentProtocol == "recomposicao", case .available = block {
            body += en
                ? " Your long-term block uses consolidated days, not an immediate credit for this record."
                : " Seu bloco de longo prazo usa dias consolidados, sem crédito imediato por este registro."
        }
        if guidance != .paused {
            if preferencesKnown {
                body += en
                    ? " Would you like to explore an adjustment that respects the preferences you already shared?"
                    : " Quer pensar em um ajuste que respeite as preferências que você já informou?"
            } else {
                body += en
                    ? " Would you like to tell me what you prefer so we can discuss a suitable adjustment?"
                    : " Quer me contar o que você prefere para conversarmos sobre um ajuste adequado?"
            }
        }
        return Education(text: body, templateID: id, preferencesKnown: preferencesKnown)
    }

    private static func normalized(_ value: String) -> String {
        trimmedText(value.decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\\p{Diacritic}", with: "", options: .regularExpression)
            .lowercased())
    }

    /// Six fixed sections from saved facts. No totals, target, budget or exercise credits are recalculated.
    var sections: [Section] {
        let en = locale == .english
        let formatter = NumberFormatter()
        formatter.locale = Foundation.Locale(identifier: en ? "en_US" : "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        func n(_ value: Double) -> String { formatter.string(from: NSNumber(value: value)) ?? String(value) }
        func macros(_ value: Nutrients) -> String {
            "\(n(value.kcal)) kcal | \(en ? "Protein" : "Proteína"): \(n(value.proteinG)) g | \(en ? "Carbohydrates" : "Carboidratos"): \(n(value.carbsG)) g | \(en ? "Fat" : "Gorduras"): \(n(value.fatG)) g"
        }
        var result: [Section]
        switch registration {
        case let .meal(r):
            let enLabels = ["cafe": "Breakfast", "almoco": "Lunch", "lanche": "Snack", "jantar": "Dinner", "ceia": "Supper", "outro": "Meal"]
            let ptLabels = ["cafe": "Café da manhã", "almoco": "Almoço", "lanche": "Lanche", "jantar": "Jantar", "ceia": "Ceia", "outro": "Refeição"]
            let label = (en ? enLabels : ptLabels)[r.mealKind] ?? (en ? "Meal" : "Refeição")
            result = [Section(key: .saved, text: "\(label) \(en ? "recorded" : "registrado").")]
            let items = r.items.map { item in
                let q = item.quantity
                let unit: String
                if q.unit == "scoop" { unit = en ? (q.value == 1 ? "scoop" : "scoops") : (q.value == 1 ? "medida" : "medidas") }
                else if q.unit == "unit" { unit = en ? (q.value == 1 ? "unit" : "units") : (q.value == 1 ? "unidade" : "unidades") }
                else { unit = q.unit }
                let estimate = q.estimated ? (en ? " (estimated, editable)" : " (estimado, editável)") : ""
                return "\(item.foodName) · \(n(q.value)) \(unit)\(estimate)\n\(macros(item.nutrients))"
            }.joined(separator: "\n\n")
            result.append(Section(key: .items, text: items))
            result.append(Section(key: .summary, text: "\(en ? "Approximate meal total" : "Total aproximado da refeição"): \(macros(r.totals))"))
        case let .workout(r):
            result = [Section(key: .saved, text: en ? "Activity recorded." : "Atividade registrada.")]
            let duration = r.durationMin.map { "\(n($0)) min" } ?? (en ? "Duration unavailable" : "Duração indisponível")
            let intensity = r.intensity ?? (en ? "Intensity unavailable" : "Intensidade indisponível")
            result.append(Section(key: .items, text: "\(r.workoutType) · \(duration) · \(intensity)"))
            let summary = r.estimatedKcal.map { "\(en ? "Estimated expenditure" : "Gasto estimado"): \(n($0)) kcal." }
                ?? (en ? "Estimated expenditure unavailable." : "Gasto estimado indisponível.")
            result.append(Section(key: .summary, text: summary))
        }
        var dayLines: [String] = []
        if let d = day {
            dayLines.append("\(en ? "Day" : "Dia"): \(d.localDate)")
            if let target = d.caloriesTarget, let percent = d.caloriePercentage {
                dayLines.append("\(en ? "Consumed" : "Consumido"): \(n(d.consumed.kcal)) / \(n(target)) kcal (\(n(percent))%).")
            } else {
                dayLines.append("\(en ? "Consumed" : "Consumido"): \(n(d.consumed.kcal)) kcal. \(en ? "Target unavailable" : "Meta indisponível").")
            }
            if let target = d.proteinTarget, let percent = d.proteinPercentage {
                dayLines.append("\(en ? "Protein" : "Proteína"): \(n(d.consumed.proteinG)) / \(n(target)) g (\(n(percent))%).")
            } else {
                dayLines.append("\(en ? "Protein" : "Proteína"): \(n(d.consumed.proteinG)) g. \(en ? "Target unavailable" : "Meta indisponível").")
            }
            if let excess = d.foodExcessKcal, excess > 0 {
                dayLines.append("\(en ? "Food excess" : "Excedente alimentar"): \(n(excess)) kcal.")
            } else if let remaining = d.remainingFoodKcal {
                dayLines.append("\(en ? "Remaining for food" : "Restam para comida"): \(n(remaining)) kcal.")
            } else { dayLines.append(en ? "Food budget unavailable." : "Saldo alimentar indisponível.") }
            dayLines.append("\(en ? "Recorded exercise" : "Exercício registrado"): \(n(d.exerciseKcal)) kcal. \(en ? "It does not increase the food budget." : "Esse gasto não aumenta a comida disponível.")")
        } else {
            dayLines.append(en
                ? "The official summary for this day is unavailable; your record was saved."
                : "O resumo oficial deste dia está indisponível; seu registro foi salvo.")
        }
        result.append(Section(key: .day, text: dayLines.joined(separator: "\n")))
        let blockText: String
        switch block {
        case let .available(b):
            blockText = "\(en ? "Block 7,700" : "Bloco 7.700"): \(n(b.currentKcal)) / \(n(b.targetKcal)) kcal (\(n(b.percentage))%).\n\(en ? "Total already consolidated" : "Saldo total já consolidado"): \(n(b.totalCreditedKcal)) kcal · \(en ? "Completed blocks" : "Blocos concluídos"): \(n(b.completedBlocks)).\n\(en ? "Theoretical reference; this record does not create an immediate credit or guarantee a physical weight change." : "Referência teórica; este registro não cria crédito imediato nem garante uma mudança física de peso.")"
        case .notApplicable: blockText = en ? "Block 7,700 does not apply to your current objective." : "O Bloco 7.700 não se aplica ao seu objetivo atual."
        case .protected: blockText = en ? "Long-term guidance is paused." : "As orientações de longo prazo estão pausadas."
        case .unavailable: blockText = en ? "Consolidated block data is unavailable." : "Os dados consolidados do bloco estão indisponíveis."
        }
        result.append(Section(key: .block, text: blockText))
        result.append(Section(key: .education, text: education?.text ?? (en
            ? "The educational comment is unavailable; your record remains saved."
            : "O comentário educativo está indisponível; seu registro continua salvo.")))
        return result
    }
}
