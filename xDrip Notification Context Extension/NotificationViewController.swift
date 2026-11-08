// Copyright © 2024 Johan Degraeve. All rights reserved.
import UIKit
import UserNotifications
import UserNotificationsUI
import SwiftUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    @IBOutlet weak var notificationViewContainer: UIView!
    private var host: UIHostingController<NotificationView>?

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let presentation = AlertNotificationPresentation(title: content.title, body: content.body,
                                                         userInfo: content.userInfo)
        if let host {
            host.rootView = NotificationView(presentation: presentation)
        } else {
            let controller = UIHostingController(rootView: NotificationView(presentation: presentation))
            addChild(controller)
            controller.view.backgroundColor = .clear
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: view.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            controller.didMove(toParent: self)
            host = controller
        }
        updateSize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSize()
    }

    private func updateSize() {
        guard let host, view.bounds.width > 0 else { return }
        let size = host.sizeThatFits(in: CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude))
        if preferredContentSize != size { preferredContentSize = size }
    }
}
