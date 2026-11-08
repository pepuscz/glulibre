// Copyright © 2024 Johan Degraeve. All rights reserved.
import WatchKit
import SwiftUI
import UserNotifications

class NotificationController: WKUserNotificationHostingController<NotificationView> {
    var presentation = AlertNotificationPresentation(title: "", body: "", userInfo: [:])

    override var body: NotificationView { NotificationView(presentation: presentation) }

    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        presentation = AlertNotificationPresentation(title: content.title, body: content.body,
                                                       userInfo: content.userInfo)
    }
}
