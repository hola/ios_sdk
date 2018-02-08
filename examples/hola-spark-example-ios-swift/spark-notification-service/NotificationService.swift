//
//  NotificationService.swift
//  spark-notification-service
//
//  Created by volodymyr on 06/02/2018.
//  Copyright © 2018 holaspark. All rights reserved.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        if let bestAttemptContent = self.bestAttemptContent {
            guard let surl = bestAttemptContent.userInfo["attachment-url"] as? String else { return }
            bestAttemptContent.addRemoteAttachment(URL(string: surl)!) {
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = self.contentHandler, let bestAttemptContent = self.bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
