//
//  NotificationViewController.swift
//  spark-notification
//
//  Created by volodymyr on 02/02/2018.
//  Copyright © 2018 holaspark. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    var looper: AVPlayerLooper!
    var observable: NSKeyValueObservation!
    var attachment: UNNotificationAttachment!
    
    deinit {
        if let attachment = self.attachment {
            attachment.url.stopAccessingSecurityScopedResource()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func didReceive(_ notification: UNNotification) {
        print("notification received", ObjectIdentifier(self))
        guard let attachment = notification.request.content.attachments.first else { return }
        guard attachment.url.startAccessingSecurityScopedResource() else { return }
        let asset = AVAsset(url: attachment.url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        // assume 16:9 by default, will resize if different ratio
        layer.frame = CGRect(x: 0, y: 0, width: self.view.frame.size.width,
            height: self.view.frame.size.width/16*9)
        let observable = layer.observe(\.videoRect, options: [.new]) { (model, change) in
            if (layer.videoRect.size.width==0 ||
                layer.videoRect.size.width==layer.frame.size.width &&
                layer.videoRect.size.height==layer.frame.size.height)
            {
                return
            }
            let width = layer.frame.size.width
            let height = layer.frame.size.width/layer.videoRect.size.width*layer.videoRect.size.height
            layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            self.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            self.preferredContentSize = CGSize(width: width, height: height)
        }
        self.view.layer.addSublayer(layer)
        player.play()
        self.looper = looper // keep the reference, otherwise looping won't work
        self.observable = observable // keep the reference for proper dealloc
        self.attachment = attachment // keep the resource until deinit
    }
}
