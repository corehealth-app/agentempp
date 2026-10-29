import Foundation
import RevenueCat

extension BillingSDKCoordinator {
    /// One process-wide coordinator is the only production owner of the SDK.
    /// Merely constructing it performs no SDK or store operation.
    static let live = BillingSDKCoordinator(
        configuration: BillingConfiguration(publicAPIKey: Bundle.main.infoDictionary?["PERFORME_REVENUECAT_PUBLIC_KEY"] as? String),
        driver: RevenueCatBillingDriver()
    )
}

/// Private to the singleton factory above: another production coordinator
/// cannot accidentally create a second driver for RevenueCat's shared SDK.
private actor RevenueCatBillingDriver: BillingSDKDriving {
    private var purchases: Purchases?
    private var packages: [String: Package] = [:]

    func configure(publicAPIKey: String, patientID: UUID) async throws {
        guard purchases == nil, !Purchases.isConfigured else {
            throw BillingStoreError.configurationUnavailable
        }
        purchases = Purchases.configure(withAPIKey: publicAPIKey, appUserID: patientID.uuidString.lowercased())
    }

    func logIn(patientID: UUID) async throws {
        packages = [:]
        guard let purchases else { throw BillingStoreError.configurationUnavailable }
        do { _ = try await purchases.logIn(patientID.uuidString.lowercased()) }
        catch { throw BillingStoreError.storeUnavailable }
    }

    func logOut() async throws {
        packages = [:]
        guard let purchases else { return }
        do { _ = try await purchases.logOut() }
        catch { throw BillingStoreError.storeUnavailable }
    }

    func offers() async throws -> [BillingProduct] {
        packages = [:]
        guard let purchases else { throw BillingStoreError.configurationUnavailable }
        let available: [Package]
        do { available = try await purchases.offerings().current?.availablePackages ?? [] }
        catch { throw BillingStoreError.storeUnavailable }
        var mapped: [BillingProduct] = []
        var retained: [String: Package] = [:]
        for package in available {
            guard retained[package.identifier] == nil else { throw BillingStoreError.storeUnavailable }
            retained[package.identifier] = package
            mapped.append(BillingProduct(id: package.identifier,
                title: package.storeProduct.localizedTitle,
                localizedPrice: package.storeProduct.localizedPriceString,
                period: Self.period(package.storeProduct.subscriptionPeriod)))
        }
        packages = retained
        return mapped
    }

    func purchase(productID: String) async throws -> BillingStoreOutcome {
        guard let purchases, let package = packages[productID] else { throw BillingStoreError.invalidSelection }
        // Keep the actual Package selected from the current Offering. Do not
        // reconstruct a store product from an arbitrary caller-supplied ID.
        do {
            let result = try await purchases.purchase(package: package)
            return result.userCancelled ? .cancelled : .completed
        } catch {
            if let outcome = Self.outcome(error) { return outcome }
            throw BillingStoreError.storeUnavailable
        }
    }

    func restore() async throws -> BillingStoreOutcome {
        guard let purchases else { throw BillingStoreError.configurationUnavailable }
        do {
            _ = try await purchases.restorePurchases()
            return .completed
        } catch {
            if let outcome = Self.outcome(error) { return outcome }
            throw BillingStoreError.storeUnavailable
        }
    }

    private static func outcome(_ error: any Error) -> BillingStoreOutcome? {
        switch (error as NSError).asErrorCode {
        case .purchaseCancelledError: .cancelled
        case .paymentPendingError: .pending
        default: nil
        }
    }

    private static func period(_ period: SubscriptionPeriod?) -> BillingSubscriptionPeriod? {
        guard let period else { return nil }
        let unit: BillingSubscriptionPeriod.Unit
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        return BillingSubscriptionPeriod(value: period.value, unit: unit)
    }
}
