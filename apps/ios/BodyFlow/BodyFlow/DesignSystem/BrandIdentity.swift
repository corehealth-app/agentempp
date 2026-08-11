import Foundation

struct BrandCopy: Equatable, Sendable {
    let slogan: String
    let descriptor: String
    let flowRoleLine: String
}

enum BrandIdentity {
    static let productName = "Better Ahead"
    static let agentName = "Flow"

    static func copy(
        for language: SupportedAppLanguage,
        bundle: Bundle = .main
    ) -> BrandCopy {
        do {
            return BrandCopy(
                slogan: try AppLocalization.string(
                    "brand.slogan",
                    for: language,
                    in: bundle
                ),
                descriptor: try AppLocalization.string(
                    "brand.descriptor",
                    for: language,
                    in: bundle
                ),
                flowRoleLine: try AppLocalization.string(
                    "brand.flow.role-line",
                    for: language,
                    in: bundle
                )
            )
        } catch {
            return approvedPortugueseCopy
        }
    }

    private static let approvedPortugueseCopy = BrandCopy(
        slogan: "Melhor a cada dia.",
        descriptor: "Sua jornada personalizada para uma vida mais saudável.",
        flowRoleLine: "Flow, seu guia em cada etapa."
    )
}
