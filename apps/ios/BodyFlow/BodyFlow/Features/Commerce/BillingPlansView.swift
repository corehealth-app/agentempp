import SwiftUI

@MainActor
struct BillingPlansDestination: View {
    let owner: Prompt14SessionOwner
    @Environment(\.locale) private var locale
    var body: some View {
        if let context = owner.billingContext {
            BillingPlansView(model: context.plansModel()).id(ObjectIdentifier(context))
        } else {
            VStack(spacing: BodyFlowSpacing.lg) {
                if owner.isResolvingBilling { ProgressView() }
                Text(copy(owner.isResolvingBilling ? "billing.session-loading" : "billing.session-unavailable"))
                    .multilineTextAlignment(.center)
                if let binding = owner.billingBinding, binding.canRetryMe {
                    Button(copy("billing.refresh")) {
                        Task { await owner.resolveBilling(binding, retrying: true) }
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("billing.session-retry")
                }
            }
            .padding(BodyFlowSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BodyFlowColor.background)
            .bodyFlowScreenChrome(title: copy("billing.title"))
            .accessibilityIdentifier("screen.billing-plans")
        }
    }
    private func copy(_ key: String.LocalizationValue) -> String {
        ProfileCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}

@MainActor
struct BillingPlansView: View {
    let model: BillingPlansModel
    @Environment(\.locale) private var locale
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text(copy(model.accessError != nil || model.access == nil ? "billing.access-unavailable"
                                  : model.hasActiveAccess ? "billing.access-active" : "billing.access-inactive"))
                            .font(BodyFlowTypography.sectionTitle)
                            .accessibilityIdentifier("billing.access-status")
                        if let access = model.access, model.accessError == nil {
                            if let plan = access.plan {
                                Text(copy(plan == .annual ? "billing.plan-annual" : plan == .monthly ? "billing.plan-monthly" : "billing.plan-trial"))
                            }
                            if let end = access.accessExpiresAt ?? access.graceExpiresAt {
                                Text(copy("billing.access-until"))
                                Text(end.value, format: .dateTime.day().month().year())
                            }
                            if access.cancelAtPeriodEnd { Text(copy("billing.renewal-cancelled")) }
                        }
                        if model.isBusy { ProgressView().accessibilityLabel(copy("billing.loading")) }
                        if let error = model.accessError {
                            Text(copy(error == .offline ? "billing.offline" : "billing.read-error"))
                                .accessibilityIdentifier("billing.read-error")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let messageKey {
                    BodyFlowCard {
                        Text(copy(messageKey)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("billing.operation-message")
                    }
                }

                Button(copy(model.operationState.isPending ? "billing.check-status" : "billing.refresh")) {
                    Task { await model.retry() }
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .disabled(model.isBusy)
                .accessibilityIdentifier("billing.refresh")

                if model.access != nil, model.checkoutUnavailable {
                    Text(copy("billing.checkout-unavailable"))
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityIdentifier("billing.checkout-unavailable")
                } else if let catalog = model.catalog {
                    if catalog.products.isEmpty { Text(copy("billing.no-products")) }
                    ForEach(catalog.products) { product in
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                                Text(verbatim: product.title).font(BodyFlowTypography.sectionTitle)
                                Text(verbatim: product.localizedPrice)
                                    .accessibilityIdentifier("billing.price.\(product.id)")
                                if let period = product.period, period.value > 0 {
                                    Text(verbatim: BillingPlansCopy.period(period, language: language))
                                }
                                Button(copy("billing.subscribe")) { Task { await model.purchase(productID: product.id) } }
                                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                                    .disabled(!model.canPurchase(productID: product.id))
                                    .accessibilityIdentifier("billing.purchase.\(product.id)")
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if model.catalogError != nil, !model.operationState.isPending {
                    Text(copy("billing.catalog-error"))
                        .accessibilityIdentifier("billing.catalog-error")
                }

                Button(copy("billing.restore")) { Task { await model.restore() } }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .disabled(!model.canRestore)
                    .accessibilityIdentifier("billing.restore")
                Text(copy("billing.store-details"))
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BodyFlowSpacing.md)
        }
        .background(BodyFlowColor.background)
        .bodyFlowScreenChrome(title: copy("billing.title"))
        .accessibilityIdentifier("screen.billing-plans")
        .task { await model.load() }
        .onDisappear { model.cancelRead() }
    }

    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue) -> String { ProfileCopy.string(key, language: language) }
    private var messageKey: String.LocalizationValue? {
        switch model.operationState {
        case .idle: nil
        case .purchasing: "billing.purchasing"
        case .restoring: "billing.restoring"
        case .syncPending: "billing.sync-pending"
        case .storePending: "billing.store-pending"
        case .cancelled: "billing.cancelled"
        case .failed: "billing.store-error"
        }
    }
}

enum BillingPlansCopy {
    static func period(_ period: BillingSubscriptionPeriod, language: SupportedAppLanguage) -> String {
        let unit = switch period.unit { case .day: "day"; case .week: "week"; case .month: "month"; case .year: "year" }
        let rawKey = "billing.period.\(unit).\(period.value == 1 ? "one" : "many")"
        let key = String.LocalizationValue(rawKey)
        let format = ProfileCopy.string(key, language: language)
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        let count = formatter.string(from: NSNumber(value: period.value)) ?? String(period.value)
        return String(format: format, locale: language.formattingLocale, count)
    }
}
