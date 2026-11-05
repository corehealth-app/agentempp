import SwiftUI

/// Day/week consumes one complete server window; plans never count as consumed.
@MainActor
struct NutritionWindowRootView: View {
  @Bindable var model: NutritionWindowModel
  let revision: Int
  let isSelected: Bool
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  private var portuguese: Bool { BodyFlowPresentationLanguage.resolve(locale) == .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { portuguese ? pt : en }
  private struct LoadKey: Hashable {
    let revision: Int
    let selected: Bool
  }

  var body: some View {
    ScrollView {
      NutritionWindowContentView(model: model, revision: revision)
    }
    .background(BodyFlowColor.background)
    .navigationTitle(text("Alimentação", "Nutrition"))
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("screen.alimentacao")
    .task(id: LoadKey(revision: revision, selected: isSelected)) {
      guard isSelected else { return }
      await model.load(revision: revision)
    }
    .refreshable {
      guard isSelected else { return }
      await model.load(revision: revision)
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, isSelected else { return }
      Task { await model.load(revision: revision) }
    }
  }
}
