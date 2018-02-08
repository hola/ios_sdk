//
//  UNMutableNotificationContent.swift
//  demo
//
//  Created by volodymyr on 07/02/2018.
//  Copyright © 2018 holaspark. All rights reserved.
//

import Foundation
import UserNotifications

extension UNMutableNotificationContent {
    func addRemoteAttachment(_ url: URL, oncomplete: @escaping ()->()) {
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let request = URLRequest(url: url)
        let task = session.downloadTask(with: request){ (location, response, error) in
            if let location = location, error==nil {
                if (response as? HTTPURLResponse)?.statusCode==200 {
                    let locationWithExt = location.deletingPathExtension().appendingPathExtension(url.pathExtension)
                    do {
                        try FileManager.default.moveItem(at: location, to: locationWithExt)
                        if let attachment = try? UNNotificationAttachment(identifier: "preview", url: locationWithExt) {
                            self.attachments = [attachment]
                            oncomplete()
                            return
                        }
                    }
                    catch (_){}
                }
            }
            oncomplete()
        }
        task.resume()
    }
}
