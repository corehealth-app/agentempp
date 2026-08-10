import Observation
import SwiftUI

struct ContentCoverSessionToken: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ContentCoverPresentationRequest: Equatable, Hashable, Sendable {
    let publicationID: String
    let version: Int
    let cover: PublishedContentCover
    let target: ContentCoverTargetSize
    let session: ContentCoverSessionToken

    static func == (
        lhs: ContentCoverPresentationRequest,
        rhs: ContentCoverPresentationRequest
    ) -> Bool {
        lhs.publicationID == rhs.publicationID
            && lhs.version == rhs.version
            && lhs.cover == rhs.cover
            && lhs.target == rhs.target
            && lhs.session == rhs.session
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(publicationID)
        hasher.combine(version)
        hasher.combine(cover.url)
        hasher.combine(cover.expiresAt)
        hasher.combine(target.widthPixels)
        hasher.combine(target.heightPixels)
        hasher.combine(session)
    }
}

enum ContentCoverTargetSizing {
    static func target(
        widthPoints: CGFloat,
        heightPoints: CGFloat,
        displayScale: CGFloat
    ) -> ContentCoverTargetSize? {
        guard widthPoints.isFinite,
              heightPoints.isFinite,
              displayScale.isFinite,
              widthPoints > 0,
              heightPoints > 0,
              displayScale > 0
        else {
            return nil
        }

        let width = (widthPoints * displayScale).rounded(.up)
        let height = (heightPoints * displayScale).rounded(.up)
        guard width >= 1,
              height >= 1,
              width <= CGFloat(ContentCoverDimensionPolicy.maximumDimension),
              height <= CGFloat(ContentCoverDimensionPolicy.maximumDimension)
        else {
            return nil
        }

        return ContentCoverTargetSize(
            widthPixels: Int(width),
            heightPixels: Int(height)
        )
    }
}

enum ContentCoverPresentation: Sendable {
    case placeholder
    case image(ContentCoverImage)
}

enum ContentCoverPlaceholderDescriptor: Equatable, Sendable {
    case neutral
}

enum ContentCoverRenderingDescriptor: Equatable, Sendable {
    case neutralPlaceholder
    case image
}

struct ContentCoverTaskIdentity: Equatable, Hashable, Sendable {
    let request: ContentCoverPresentationRequest?
    let parentRevision: Int
    let authorizedParentRevision: Int?
}

struct ContentCoverViewDescriptor: Equatable, Sendable {
    let taskIdentity: ContentCoverTaskIdentity
    let cancelsOnDisappear = true
    let placeholder = ContentCoverPlaceholderDescriptor.neutral
    let isAccessibilityHidden = true

    init(
        request: ContentCoverPresentationRequest?,
        parentRevision: Int
    ) {
        self.init(
            request: request,
            parentRevision: parentRevision,
            authorizedParentRevision: parentRevision
        )
    }

    init(
        request: ContentCoverPresentationRequest?,
        parentRevision: Int,
        authorizedParentRevision: Int?
    ) {
        taskIdentity = ContentCoverTaskIdentity(
            request: request,
            parentRevision: parentRevision,
            authorizedParentRevision: authorizedParentRevision
        )
    }

    func rendering(
        for presentation: ContentCoverPresentation
    ) -> ContentCoverRenderingDescriptor {
        switch presentation {
        case .placeholder:
            .neutralPlaceholder
        case .image:
            .image
        }
    }
}

private struct ContentCoverRefreshLease: Equatable, Sendable {
    let publicationID: String
    let version: Int
    let sequence: UInt64
    let isCurrentVersion: Bool
}

private struct ContentCoverRefreshLineageState: Sendable {
    let version: Int
    let latestSequence: UInt64
    var hasRefreshedConsecutiveNotFound: Bool
}

@MainActor
final class ContentCoverRefreshBudget {
    let session: ContentCoverSessionToken
    private var statesByPublication: [
        String: ContentCoverRefreshLineageState
    ] = [:]
    private var nextSequence: UInt64 = 0

    init(session: ContentCoverSessionToken) {
        self.session = session
    }

    fileprivate func begin(
        for request: ContentCoverPresentationRequest
    ) -> ContentCoverRefreshLease {
        nextSequence &+= 1
        let sequence = nextSequence
        guard request.session == session else {
            return ContentCoverRefreshLease(
                publicationID: request.publicationID,
                version: request.version,
                sequence: sequence,
                isCurrentVersion: false
            )
        }
        let prior = statesByPublication[request.publicationID]
        let isCurrentVersion = prior.map {
            request.version >= $0.version
        } ?? true
        if isCurrentVersion {
            statesByPublication[request.publicationID] =
                ContentCoverRefreshLineageState(
                    version: request.version,
                    latestSequence: sequence,
                    hasRefreshedConsecutiveNotFound:
                        prior?.version == request.version
                            ? prior?.hasRefreshedConsecutiveNotFound ?? false
                            : false
                )
        }
        return ContentCoverRefreshLease(
            publicationID: request.publicationID,
            version: request.version,
            sequence: sequence,
            isCurrentVersion: isCurrentVersion
        )
    }

    fileprivate func claimNotFound(
        lease: ContentCoverRefreshLease
    ) -> Bool {
        guard lease.isCurrentVersion,
              var state = statesByPublication[lease.publicationID],
              state.version == lease.version,
              state.latestSequence == lease.sequence,
              !state.hasRefreshedConsecutiveNotFound
        else {
            return false
        }
        state.hasRefreshedConsecutiveNotFound = true
        statesByPublication[lease.publicationID] = state
        return true
    }

    fileprivate func recordSuccess(
        lease: ContentCoverRefreshLease
    ) {
        guard lease.isCurrentVersion,
              var state = statesByPublication[lease.publicationID],
              state.version == lease.version,
              state.latestSequence == lease.sequence
        else {
            return
        }
        state.hasRefreshedConsecutiveNotFound = false
        statesByPublication[lease.publicationID] = state
    }
}

@MainActor
@Observable
final class ContentCoverViewModel {
    typealias InvalidationAction = @MainActor @Sendable () async -> Void

    private var loadController = FeatureKeyedLoadController<
        ContentCoverPresentationRequest,
        ContentCoverImage
    >()
    private var currentTaskIdentity: ContentCoverTaskIdentity?
    private var observedParentRevision: Int?

    private(set) var presentation: ContentCoverPresentation = .placeholder

    func load(
        descriptor: ContentCoverViewDescriptor,
        loader: any ContentCoverLoading,
        refreshBudget: ContentCoverRefreshBudget,
        onParentRevisionChanged: @escaping InvalidationAction,
        onCapabilityInvalidated: @escaping InvalidationAction
    ) async {
        guard !Task.isCancelled else { return }

        let taskIdentity = descriptor.taskIdentity
        let request = taskIdentity.request
        let parentRevisionChanged = observedParentRevision.map {
            $0 != taskIdentity.parentRevision
        } ?? false
        observedParentRevision = taskIdentity.parentRevision

        if currentTaskIdentity != taskIdentity {
            cancelActiveLoad()
            currentTaskIdentity = taskIdentity
            presentation = .placeholder
        }

        if parentRevisionChanged {
            cancelActiveLoad()
            currentTaskIdentity = taskIdentity
            presentation = .placeholder
            guard !Task.isCancelled else { return }
            await onParentRevisionChanged()
            guard !Task.isCancelled,
                  currentTaskIdentity == taskIdentity else { return }
        }

        guard taskIdentity.authorizedParentRevision
                == taskIdentity.parentRevision else {
            presentation = .placeholder
            return
        }

        guard let request else {
            presentation = .placeholder
            return
        }
        guard !Task.isCancelled else { return }

        let refreshLease = refreshBudget.begin(for: request)
        var shouldRefresh = false
        await loadController.load(
            key: request,
            operation: {
                try await loader.image(
                    publicationID: request.publicationID,
                    version: request.version,
                    cover: request.cover,
                    target: request.target
                )
            },
            publish: { [weak self] completion in
                guard let self,
                      self.currentTaskIdentity == taskIdentity,
                      taskIdentity.authorizedParentRevision
                        == taskIdentity.parentRevision else { return }
                switch completion {
                case let .value(image):
                    self.presentation = .image(image)
                    refreshBudget.recordSuccess(lease: refreshLease)
                case let .failure(error):
                    self.presentation = .placeholder
                    guard error as? BodyFlowCapabilityError
                            == .contentCoverNotFound
                    else {
                        return
                    }
                    shouldRefresh = refreshBudget.claimNotFound(
                        lease: refreshLease
                    )
                }
            }
        )

        guard shouldRefresh,
              !Task.isCancelled,
              currentTaskIdentity == taskIdentity,
              taskIdentity.authorizedParentRevision
                == taskIdentity.parentRevision else { return }
        await onCapabilityInvalidated()
    }

    func cancel() {
        cancelActiveLoad()
        currentTaskIdentity = nil
        observedParentRevision = nil
        presentation = .placeholder
    }

    private func cancelActiveLoad() {
        loadController.cancel()
        loadController = FeatureKeyedLoadController()
    }
}

@MainActor
struct ContentCoverEnvironment {
    let loader: any ContentCoverLoading
    let session: ContentCoverSessionToken
    let refreshBudget: ContentCoverRefreshBudget
    let invalidationCenter: FeatureInvalidationCenter

    static func make(
        loader: any ContentCoverLoading,
        session: ContentCoverSessionToken,
        invalidationCenter: FeatureInvalidationCenter
    ) -> Self {
        Self(
            loader: loader,
            session: session,
            refreshBudget: ContentCoverRefreshBudget(session: session),
            invalidationCenter: invalidationCenter
        )
    }
}

private struct ContentCoverEnvironmentKey: @MainActor EnvironmentKey {
    static let defaultValue: ContentCoverEnvironment? = nil
}

@MainActor
extension EnvironmentValues {
    var contentCoverEnvironment: ContentCoverEnvironment? {
        get { self[ContentCoverEnvironmentKey.self] }
        set { self[ContentCoverEnvironmentKey.self] = newValue }
    }
}

@MainActor
struct ContentCoverView: View {
    @Environment(\.contentCoverEnvironment) private var environment
    @Environment(\.displayScale) private var displayScale
    @State private var model = ContentCoverViewModel()

    let publicationID: String
    let version: Int
    let cover: PublishedContentCover?
    let parentRevision: Int
    let authorizedParentRevision: Int?
    let onParentRevisionChanged: ContentCoverViewModel.InvalidationAction
    let onCapabilityInvalidated: ContentCoverViewModel.InvalidationAction

    init(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover?,
        parentRevision: Int,
        onParentRevisionChanged: @escaping
            ContentCoverViewModel.InvalidationAction,
        onCapabilityInvalidated: @escaping
            ContentCoverViewModel.InvalidationAction
    ) {
        self.init(
            publicationID: publicationID,
            version: version,
            cover: cover,
            parentRevision: parentRevision,
            authorizedParentRevision: parentRevision,
            onParentRevisionChanged: onParentRevisionChanged,
            onCapabilityInvalidated: onCapabilityInvalidated
        )
    }

    init(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover?,
        parentRevision: Int,
        authorizedParentRevision: Int?,
        onParentRevisionChanged: @escaping
            ContentCoverViewModel.InvalidationAction,
        onCapabilityInvalidated: @escaping
            ContentCoverViewModel.InvalidationAction
    ) {
        self.publicationID = publicationID
        self.version = version
        self.cover = cover
        self.parentRevision = parentRevision
        self.authorizedParentRevision = authorizedParentRevision
        self.onParentRevisionChanged = onParentRevisionChanged
        self.onCapabilityInvalidated = onCapabilityInvalidated
    }

    var body: some View {
        GeometryReader { geometry in
            let descriptor = ContentCoverViewDescriptor(
                request: request(for: geometry.size),
                parentRevision: parentRevision,
                authorizedParentRevision: authorizedParentRevision
            )
            coverPresentation(descriptor: descriptor)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .task(id: descriptor.taskIdentity) {
                    guard let environment else {
                        model.cancel()
                        return
                    }
                    await model.load(
                        descriptor: descriptor,
                        loader: environment.loader,
                        refreshBudget: environment.refreshBudget,
                        onParentRevisionChanged: onParentRevisionChanged,
                        onCapabilityInvalidated: onCapabilityInvalidated
                    )
                }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(
            ContentCoverViewDescriptor(
                request: nil,
                parentRevision: parentRevision
            ).isAccessibilityHidden
        )
        .onDisappear {
            let descriptor = ContentCoverViewDescriptor(
                request: nil,
                parentRevision: parentRevision
            )
            if descriptor.cancelsOnDisappear {
                model.cancel()
            }
        }
    }

    @ViewBuilder
    private func coverPresentation(
        descriptor: ContentCoverViewDescriptor
    ) -> some View {
        switch descriptor.rendering(for: model.presentation) {
        case .neutralPlaceholder:
            ContentCoverPlaceholder(descriptor: descriptor.placeholder)
        case .image:
            if case let .image(image) = model.presentation {
                Image(
                    decorative: image.cgImage,
                    scale: displayScale,
                    orientation: .up
                )
                .resizable()
                .scaledToFill()
            } else {
                ContentCoverPlaceholder(descriptor: descriptor.placeholder)
            }
        }
    }

    private func request(
        for size: CGSize
    ) -> ContentCoverPresentationRequest? {
        guard let environment,
              let cover,
              let target = ContentCoverTargetSizing.target(
                  widthPoints: size.width,
                  heightPoints: size.height,
                  displayScale: displayScale
              )
        else {
            return nil
        }

        return ContentCoverPresentationRequest(
            publicationID: publicationID,
            version: version,
            cover: cover,
            target: target,
            session: environment.session
        )
    }
}

private struct ContentCoverPlaceholder: View {
    let descriptor: ContentCoverPlaceholderDescriptor

    var body: some View {
        switch descriptor {
        case .neutral:
            ZStack {
                BodyFlowColor.accent.opacity(0.12)
                Image(systemName: "book.closed")
                    .font(BodyFlowTypography.largeTitle)
                    .foregroundStyle(BodyFlowColor.accent)
            }
        }
    }
}
