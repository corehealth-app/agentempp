import SwiftUI
import UIKit

@MainActor
struct TabBarAccessibilityConfigurator: UIViewControllerRepresentable {
    let identifiers: [String]

    func makeUIViewController(context: Context) -> Controller {
        Controller(identifiers: identifiers)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.identifiers = identifiers
        controller.applyIdentifiers()
    }

    final class Controller: UIViewController {
        var identifiers: [String]

        init(identifiers: [String]) {
            self.identifiers = identifiers
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyIdentifiers()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyIdentifiers()
        }

        func applyIdentifiers() {
            guard
                let root = view.window?.rootViewController,
                let tabBarController = findTabBarController(in: root),
                let items = tabBarController.tabBar.items,
                items.count == identifiers.count
            else {
                return
            }

            for (item, identifier) in zip(items, identifiers) {
                item.accessibilityIdentifier = identifier
            }
        }

        private func findTabBarController(
            in controller: UIViewController
        ) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            for child in controller.children {
                if let match = findTabBarController(in: child) {
                    return match
                }
            }

            if let presented = controller.presentedViewController {
                return findTabBarController(in: presented)
            }

            return nil
        }
    }
}
