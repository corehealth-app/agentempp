import Foundation

/// Public provenance fixed in the signed app's Info.plist by the QA build
/// producer after checking the official deployment receipt. Runtime validation
/// checks its shape and exact origin; it does not authenticate that receipt.
/// No launch argument, server response or user setting can supply this binding.
enum CurrentClinicalQABinding: Equatable, Sendable {
    case absent
    case invalid
    case candidate(CurrentClinicalQACandidate)

    static let infoKey = "PERFORME_CURRENT_CLINICAL_QA_BINDING"
    static let projectID = "prj_NTrnUNFXfmddMuci3VWjalfAoejW"

    static func load(from raw: Any?) -> Self {
        guard let raw else { return .absent }
        guard let values = raw as? [String: String], Set(values.keys) == Set([
            "origin", "deployment_id", "project_id", "source_manifest_sha256", "receipt_sha256", "region",
        ]), let originText = values["origin"], let origin = URL(string: originText),
              origin.scheme == "https", let host = origin.host?.lowercased(),
              host.hasSuffix(".vercel.app"), host != CurrentClinicalRuntimeComposition.bffHost,
              (origin.port == nil || origin.port == 443),
              origin.path.isEmpty || origin.path == "/",
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              values["project_id"] == projectID, values["region"] == "gru1",
              let deploymentID = values["deployment_id"],
              deploymentID.range(of: "^dpl_[A-Za-z0-9]+$", options: .regularExpression) != nil,
              let sourceDigest = values["source_manifest_sha256"], isDigest(sourceDigest),
              let receiptDigest = values["receipt_sha256"], isDigest(receiptDigest)
        else { return .invalid }
        return .candidate(CurrentClinicalQACandidate(origin: origin, deploymentID: deploymentID,
            sourceManifestSHA256: sourceDigest, receiptSHA256: receiptDigest))
    }

    private static func isDigest(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }
}

struct CurrentClinicalQACandidate: Equatable, Sendable {
    let origin: URL
    let deploymentID: String
    let sourceManifestSHA256: String
    let receiptSHA256: String

    fileprivate init(origin: URL, deploymentID: String, sourceManifestSHA256: String, receiptSHA256: String) {
        self.origin = origin
        self.deploymentID = deploymentID
        self.sourceManifestSHA256 = sourceManifestSHA256
        self.receiptSHA256 = receiptSHA256
    }
}
