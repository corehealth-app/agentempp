import SwiftUI
import UIKit

/// Tells its host, once, that the sheet it sits in has finished arriving.
///
/// The keyboard is only asked for on a sheet that has stopped moving: a
/// field focused while the sheet is still sliding in makes the sheet and the
/// keyboard move against each other. UIKit says when that is (the
/// appearance transition ended); no timer is involved.
struct MealSheetSettledProbe: UIViewControllerRepresentable {
    let settled: @MainActor () -> Void

    func makeUIViewController(context: Context) -> MealSheetSettledProbeController {
        MealSheetSettledProbeController(settled: settled)
    }

    func updateUIViewController(_ controller: MealSheetSettledProbeController, context: Context) {}
}

final class MealSheetSettledProbeController: UIViewController {
    private var settled: (@MainActor () -> Void)?

    init(settled: @escaping @MainActor () -> Void) {
        self.settled = settled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Once per sheet: coming back from a full-screen cover (the camera)
        // appears again and must not ask for the keyboard a second time.
        guard let report = settled else { return }
        settled = nil
        if let coordinator = transitionCoordinator {
            // Still inside a transition: wait for it to end.
            coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated { report() }
            }
        } else {
            report()
        }
    }
}
