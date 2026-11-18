import SwiftUI

@MainActor struct JourneySocialEntryCard: View {
  let coordinator: JourneySocialShellCoordinator
  @Environment(\.locale) private var locale
  var body: some View {
    NavigationLink {
      JourneySocialRootView(coordinator: coordinator)
    } label: {
      BodyFlowCard(surface: .card) {
        FeatureActionLabel(
          title: text("Ranking e privacidade", "Ranking and privacy"),
          detail: text(
            "Participe com um apelido e acompanhe sua adesão.",
            "Join with a nickname and follow your consistency."), systemImage: "person.2")
      }
    }
    .buttonStyle(.bodyFlowRow)
    .accessibilityIdentifier("journey-social.entry")
  }
  private func text(_ pt: String, _ en: String) -> String {
    locale.language.languageCode?.identifier == "en" ? en : pt
  }
}

@MainActor struct JourneySocialRootView: View {
  let coordinator: JourneySocialShellCoordinator
  @Environment(\.locale) private var locale
  var body: some View {
    Group {
      if let model = coordinator.model {
        JourneySocialView(model: model)
      } else if coordinator.phase == .unavailable || coordinator.phase == .ready {
        ContentUnavailableView {
          Label(
            text("Não foi possível abrir", "Unable to open"), systemImage: "wifi.exclamationmark")
        } description: {
          Text(
            text("Tente novamente para consultar seu perfil.", "Try again to read your profile."))
        } actions: {
          Button(text("Tentar novamente", "Try again")) { Task { await coordinator.load() } }
        }
      } else if coordinator.phase == .closed {
        Text(text("Esta sessão foi encerrada.", "This session has ended."))
      } else {
        ProgressView()
      }
    }
    .navigationTitle(text("Ranking e privacidade", "Ranking and privacy"))
    .task { await coordinator.load() }
  }
  private func text(_ pt: String, _ en: String) -> String {
    locale.language.languageCode?.identifier == "en" ? en : pt
  }
}

@MainActor struct JourneySocialView: View {
  let model: JourneySocialModel
  @Environment(\.locale) private var locale
  @State private var nickname = ""
  @State private var accepted = false
  @State private var reportPeer: JourneySocialRankingPage.Entry?

  var body: some View {
    Group {
      if model.isClosed {
        Text(text("Esta sessão foi encerrada.", "This session has ended."))
      } else {
        Form {
          status
          if let pending = model.pending { recovery(pending) }
          if let profile = model.profile {
            participation(profile)
            if profile.optedIn && profile.moderation == .active && model.pending == nil { ranking }
            if profile.revision > 0 { blocks }
          }
          if model.phase == .idle || model.phase == .loading { ProgressView() }
        }
      }
    }
    .transaction {
      if model.isClosed {
        $0.animation = nil
        $0.disablesAnimations = true
      }
    }
    .scrollContentBackground(.hidden)
    .background(BodyFlowColor.background)
    .tint(BodyFlowColor.accent)
    .navigationTitle(text("Ranking e privacidade", "Ranking and privacy"))
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("screen.journey-social")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await model.load() }
        } label: {
          Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(text("Atualizar ranking e privacidade", "Refresh ranking and privacy"))
        .accessibilityIdentifier("journey-social.refresh")
        .disabled(model.isWorking || model.isClosed)
      }
    }
    .task { await model.load() }
    .refreshable { await model.load() }
    .onDisappear { model.cancelWork() }
    .onChange(of: model.profile?.revision, initial: true) { _, _ in
      if model.isClosed { reportPeer = nil }
      nickname = model.profile?.nickname ?? ""
      accepted = model.profile?.optedIn ?? false
    }
    .sheet(item: $reportPeer) { peer in
      JourneySocialReportSheet(model: model, member: peer)
    }
  }

  @ViewBuilder private var status: some View {
    if let outcome = model.outcome {
      Section {
        Text(
          outcome == .saved
            ? text("Ação salva.", "Action saved.")
            : outcome == .recovered
              ? text(
                "Resultado consultado. O estado atual está abaixo.",
                "Result checked. Your current state is below.")
              : text(
                "O envio não aplicado foi cancelado.", "The unapplied submission was cancelled.")
        )
        .accessibilityIdentifier("journey-social.outcome")
      }
    }
    if let issue = model.issue {
      Section {
        Text(
          issue == .invalidInput
            ? text(
              "Confira o apelido, o aceite ou o participante selecionado.",
              "Check the nickname, consent or selected participant.")
            : model.outcome == .saved
              ? text(
                "A ação foi salva, mas não foi possível atualizar a lista. Atualize para consultar.",
                "Your action was saved, but the list could not be refreshed. Refresh to check it.")
              : text(
                "Não foi possível concluir esta consulta. Atualize ou confira o envio pendente abaixo.",
                "This request could not be completed. Refresh or check the pending submission below."
              )
        )
        .foregroundStyle(BodyFlowColor.warning)
        .accessibilityIdentifier("journey-social.issue")
      }
    }
  }
  private func recovery(_ pending: JourneySocialPendingOperation) -> some View {
    Section(text("Envio pendente", "Pending submission")) {
      Text(
        text(
          "Se este envio ainda não foi aplicado, ele será cancelado. Se já foi salvo, consultaremos o resultado sem repetir a ação.",
          "If this submission has not been applied, it will be cancelled. If it was saved, we will check the result without repeating the action."
        ))
      Button(text("Consultar ou cancelar envio", "Check or cancel submission")) {
        Task { await model.resolvePending() }
      }
      .buttonStyle(BodyFlowButtonStyle(role: .primary))
      .disabled(model.isWorking).accessibilityIdentifier("journey-social.resolve")
    }
  }
  private func participation(_ profile: JourneySocialProfile) -> some View {
    Section(text("Sua participação", "Your participation")) {
      Text(
        text(
          "A participação é opcional. Seu apelido e XP oficial semanal ficam visíveis no ranking. Peso, fotos e dados de saúde não aparecem nele.",
          "Participation is optional. Your nickname and official weekly XP are visible in the ranking. Weight, photos and health data do not appear there."
        ))
      if profile.moderation == .suspended {
        Text(
          text(
            "Sua participação está suspensa. Você ainda pode sair e gerenciar bloqueios.",
            "Your participation is suspended. You can still leave and manage blocks."))
      } else {
        TextField(text("Apelido", "Nickname"), text: $nickname)
          .textInputAutocapitalization(.words).autocorrectionDisabled()
          .accessibilityIdentifier("journey-social.nickname")
          .disabled(!model.canEdit)
        Text(
          text(
            "Use de 2 a 32 caracteres, sem contato ou e-mail.",
            "Use 2 to 32 characters, without contact details or email.")
        )
        .font(.caption).foregroundStyle(BodyFlowColor.secondaryText)
        Toggle(
          text(
            "Quero participar com este apelido e mostrar meu XP semanal.",
            "I want to join with this nickname and show my weekly XP."), isOn: $accepted
        )
        .disabled(!model.canEdit).accessibilityIdentifier("journey-social.consent")
        Button(
          profile.optedIn
            ? text("Salvar apelido", "Save nickname")
            : text("Participar do ranking", "Join ranking")
        ) {
          Task { await model.saveParticipation(nickname: nickname, accepted: accepted) }
        }
        .buttonStyle(BodyFlowButtonStyle(role: .primary))
        .disabled(!model.canEdit || !accepted || nickname.isEmpty)
        .accessibilityIdentifier("journey-social.participate")
      }
      if profile.optedIn {
        Button(text("Sair do ranking", "Leave ranking"), role: .destructive) {
          Task { await model.withdraw() }
        }
        .disabled(!model.canEdit).accessibilityIdentifier("journey-social.withdraw")
      }
    }
  }
  private var ranking: some View {
    Section(text("Ranking semanal", "Weekly ranking")) {
      Text(
        text(
          "XP oficial dos dias encerrados. Semana de segunda a domingo; empates compartilham a posição.",
          "Official XP from closed days. Monday to Sunday; ties share the same position."))
      if let page = model.rankingPage {
        Text(
          "\(civil(page.weekStart)) – \(civil(page.weekEnd)) · \(text("apurado até", "counted through")) \(civil(page.throughDate))"
        )
        .font(.caption).foregroundStyle(BodyFlowColor.secondaryText)
      }
      if model.rankings.isEmpty && !model.isWorking {
        Text(
          text(
            "Nenhum participante disponível nesta consulta.",
            "No participants available in this result."))
      }
      ForEach(model.rankings) { row in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text("#\(row.rank)").font(.headline)
            Text(row.nickname).frame(maxWidth: .infinity, alignment: .leading)
            Text(row.weeklyXP, format: .number).monospacedDigit()
            Text("XP").font(.caption)
          }
          if row.isYou {
            Text(text("Você", "You")).font(.caption).foregroundStyle(BodyFlowColor.accent)
          } else {
            HStack {
              Button(text("Bloquear", "Block")) {
                Task { await model.block(memberID: row.memberID) }
              }
              Button(text("Denunciar", "Report")) { reportPeer = row }
            }
            .buttonStyle(.borderless).disabled(!model.canEdit)
          }
        }
        .accessibilityIdentifier(
          "journey-social.ranking-row.\(row.memberID.uuidString.lowercased())")
      }
      if model.rankingPage?.nextCursor != nil {
        Button(text("Ver mais participantes", "Load more participants")) {
          Task { await model.loadMoreRanking() }
        }
        .disabled(!model.canEdit).accessibilityIdentifier("journey-social.ranking-more")
      }
    }
  }
  private var blocks: some View {
    Section(text("Pessoas bloqueadas", "Blocked participants")) {
      if model.blocked.isEmpty && !model.isWorking {
        Text(text("Nenhum bloqueio nesta consulta.", "No blocks in this result."))
      }
      ForEach(model.blocked) { row in
        VStack(alignment: .leading, spacing: 8) {
          Text(row.nickname ?? text("Participante indisponível", "Unavailable participant"))
          Button(text("Desbloquear", "Unblock")) {
            Task { await model.unblock(memberID: row.memberID) }
          }
          .disabled(!model.canEdit)
        }
      }
      if model.blocksPage?.nextCursor != nil {
        Button(text("Ver mais bloqueios", "Load more blocks")) {
          Task { await model.loadMoreBlocks() }
        }.disabled(!model.canEdit)
      }
    }
  }
  private func civil(_ value: String) -> String {
    let parts = value.split(separator: "-")
    guard parts.count == 3 else { return value }
    return locale.language.languageCode?.identifier == "en"
      ? "\(parts[1])/\(parts[2])/\(parts[0])" : "\(parts[2])/\(parts[1])/\(parts[0])"
  }
  private func text(_ pt: String, _ en: String) -> String {
    locale.language.languageCode?.identifier == "en" ? en : pt
  }
}

@MainActor struct JourneySocialReportSheet: View {
  let model: JourneySocialModel
  let member: JourneySocialRankingPage.Entry
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var reason = JourneySocialReportReason.spam
  var body: some View {
    NavigationStack {
      Group {
        if model.isClosed {
          Text(text("Esta sessão foi encerrada.", "This session has ended."))
        } else {
          Form {
            Section { Text(member.nickname) }
            Section(text("Motivo", "Reason")) {
              Picker(text("Motivo", "Reason"), selection: $reason) {
                Text(text("Apelido inadequado", "Inappropriate nickname")).tag(
                  JourneySocialReportReason.nickname)
                Text(text("Assédio", "Harassment")).tag(JourneySocialReportReason.harassment)
                Text("Spam").tag(JourneySocialReportReason.spam)
                Text(text("Outro", "Other")).tag(JourneySocialReportReason.other)
              }
              Button(text("Enviar denúncia", "Submit report")) {
                Task {
                  let saved = await model.report(memberID: member.memberID, reason: reason)
                  if saved { dismiss() }
                }
              }
              .disabled(!model.canEdit).accessibilityIdentifier("journey-social.report-submit")
            }
          }
        }
      }
      .transaction {
        if model.isClosed {
          $0.animation = nil
          $0.disablesAnimations = true
        }
      }
      .navigationTitle(text("Denunciar participante", "Report participant"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(text("Fechar", "Close")) { dismiss() }
        }
      }
    }
  }
  private func text(_ pt: String, _ en: String) -> String {
    locale.language.languageCode?.identifier == "en" ? en : pt
  }
}
