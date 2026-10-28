import SwiftUI

@MainActor
struct ReevaluationPhotosView:View {
    let model:ReevaluationPhotoModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var presented:ReevaluationPhotoProducer?
    @State private var cameraPresentation = 0
    @State private var asksDiscard = false
    private var language:SupportedAppLanguage {
        model.consent?.document.flatMap { SupportedAppLanguage(rawValue:$0.locale) } ?? BodyFlowPresentationLanguage.resolve(locale)
    }
    var content:some View {
            VStack(alignment:.leading,spacing:BodyFlowSpacing.lg) {
                Text(copy("reeval.photos.instructions"))
                if let document = model.consent?.document, model.consent?.availability != .available {
                    BodyFlowCard {
                        VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
                            Text(copy("reeval.photos.consent.title")).font(BodyFlowTypography.sectionTitle)
                            Text(document.body).textSelection(.enabled).accessibilityIdentifier("reeval.photos.consent.body")
                            Toggle(copy("reeval.photos.consent.check"),isOn:Binding(get:{ model.consentChecked },set:{ model.setConsentChecked($0) }))
                                .disabled(model.hasBlockingWork).accessibilityIdentifier("reeval.photos.consent.check")
                            Button(copy("reeval.photos.consent.accept")) { Task { await model.acceptConsent() } }
                                .buttonStyle(BodyFlowButtonStyle(role:.primary)).disabled(!model.consentChecked || model.hasBlockingWork)
                                .accessibilityIdentifier("reeval.photos.consent.accept")
                        }
                    }
                } else if model.consent?.availability == .available {
                    let count = model.snapshot?.photos.filter { $0.asset?.status == .processed }.count ?? 0
                    Text(String(format:copy("reeval.photos.progress"),count)).font(BodyFlowTypography.headline)
                    ForEach(ReevaluationPhotoPose.allCases,id:\.rawValue) { pose in photoCard(pose) }
                    Text(copy("reeval.photos.quota")).font(BodyFlowTypography.callout).foregroundStyle(BodyFlowColor.secondaryText)
                } else if !model.isBusy { Text(copy("reeval.photos.policy-unavailable")) }
                if let receipt = model.lastDiscard {
                    Text(copy(receipt.deletion == .settled ? "reeval.photos.discard.settled":"reeval.photos.discard.pending"))
                        .accessibilityIdentifier("reeval.photos.discard.state")
                }
                if model.isBusy { ProgressView(copy("reeval.photos.working")) }
                if let error = model.error {
                    Text(copy(errorKey(error))).foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityIdentifier("reeval.photos.error")
                }
                Button(copy(model.hasPendingIntent ? "reeval.photos.retry":"reeval.photos.refresh")) { Task { await model.retry() } }
                    .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(model.isBusy || model.producer != nil)
                    .accessibilityIdentifier("reeval.photos.retry")
                if model.snapshot?.acceptanceID != nil {
                    Button(copy("reeval.photos.discard"),role:.destructive) { asksDiscard = true }
                        .disabled(model.isBusy || model.producer != nil).accessibilityIdentifier("reeval.photos.discard")
                }
                Button(copy(model.consent?.availability == .available ? "reeval.photos.back":"reeval.photos.consent.decline")) { dismiss() }
                    .buttonStyle(BodyFlowButtonStyle(role:.secondary))
                    .accessibilityIdentifier("reeval.photos.back")
            }.padding(BodyFlowSpacing.md)
    }
    var body:some View {
        ScrollView { content }
        .background(BodyFlowColor.background)
        .navigationTitle(copy("reeval.photos.title")).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.reevaluation-photos")
        .task { await model.load() }
        .onDisappear {
            // A system camera covers this screen too. Cancel only a producer
            // that has no presented system cover (e.g. pending permission).
            if presented == nil, let id = model.producer?.id { model.cancelProducer(id) }
        }
        .confirmationDialog(copy("reeval.photos.discard.question"),isPresented:$asksDiscard,titleVisibility:.visible) {
            Button(copy("reeval.photos.discard"),role:.destructive) { Task { await model.discard() } }
            Button(copy("reeval.photos.cancel"),role:.cancel) {}
        }
        .fullScreenCover(item:producerBinding) { request in
            if request.channel == .camera {
                MealCameraCover(camera:model.camera,presentation:cameraPresentation) { data in
                    guard claim(request.id) else { return }
                    if let data { Task { await model.receive(request,data:data) } }
                    else { model.cancelProducer(request.id) }
                }
            } else {
                ReevaluationPhotoLibraryPicker(requestID:request.id) { id,result in
                    guard claim(id) else { return }
                    switch result {
                    case .success(let image):
                        guard let image else { model.cancelProducer(id); return }
                        Task { await model.receivePicked(request) { try await image.load() } }
                    case .failure(let error): Task { await model.producerFailed(request,error:error) }
                    }
                }
            }
        }
    }
    private var producerBinding:Binding<ReevaluationPhotoProducer?> {
        let id = presented?.id
        return Binding(get:{ presented },set:{ value in
            guard value == nil, let id, presented?.id == id else { return }
            presented = nil; model.cancelProducer(id)
        })
    }
    private func claim(_ id:UUID) -> Bool {
        guard presented?.id == id else { return false }
        presented = nil; return true
    }
    private func start(_ pose:ReevaluationPhotoPose,_ channel:MealSourceChannel) {
        Task {
            guard let request = await model.beginProducer(pose:pose,channel:channel) else { return }
            if channel == .camera { cameraPresentation += 1 }; presented = request
        }
    }
    private func photoCard(_ pose:ReevaluationPhotoPose) -> some View {
        BodyFlowCard {
            VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
                Text(copy("reeval.photos.pose."+pose.rawValue)).font(BodyFlowTypography.sectionTitle)
                let asset = model.snapshot?.photos.first(where:{ $0.pose == pose })?.asset
                let status = asset?.status.rawValue ?? "missing"
                Text(copy("reeval.photos.status."+status)).accessibilityIdentifier("reeval.photos.status."+pose.rawValue)
                if let percent = asset?.estimatedBodyFatPercent {
                    Text(String(format:copy("reeval.photos.reading"),MealProposalNumberParser.format(percent,language:language)))
                        .accessibilityIdentifier("reeval.photos.reading."+pose.rawValue)
                }
                if model.camera.isAvailable() {
                    Button(copy("reeval.photos.camera")) { start(pose,.camera) }
                        .buttonStyle(BodyFlowButtonStyle(role:.primary)).disabled(!model.canCapture)
                        .accessibilityIdentifier("reeval.photos.camera."+pose.rawValue)
                }
                Button(copy("reeval.photos.library")) { start(pose,.gallery) }
                    .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(!model.canCapture)
                    .accessibilityIdentifier("reeval.photos.library."+pose.rawValue)
            }
        }
    }
    private func errorKey(_ value:ReevaluationPhotoFailure) -> String {
        if model.analysisFailure != nil { return "reeval.photos.analysis-failed" }
        switch value {
        case .quota: return "reeval.photos.limit"
        case .offline: return "reeval.photos.offline"
        case .busy: return "reeval.photos.processing"
        case .changed: return "reeval.photos.changed"
        default: return "reeval.photos.unavailable"
        }
    }
    private func copy(_ key:String) -> String { ProgressCopy.string(String.LocalizationValue(key),language:language) }
}
