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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any required interface initialization here.
    }
    
    func didReceive(_ notification: UNNotification) {
        print("notification received")
        if let attachment = notification.request.content.attachments.first {
            let asset = AVAsset(url: attachment.url)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer()
            let looper = AVPlayerLooper(player: player, templateItem: item)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            layer.frame = rect2vrect(self.view.frame)
            let observable = layer.observe(\.videoRect, options: [.new]) { (model, change) in
                if (layer.videoRect.size.width==0 ||
                    layer.videoRect.size.width==layer.frame.size.width &&
                    layer.videoRect.size.height==layer.frame.size.height)
                {
                    return
                }
                layer.frame = self.rect2vrect(layer.videoRect)
                self.view.frame = self.rect2vrect(layer.videoRect)
            }
            self.view.layer.addSublayer(layer)
            player.play()
            self.looper = looper // keep the reference, otherwise looping won't work
            self.observable = observable // keep the reference for proper dealloc
        }
    }
    
    func rect2vrect(_ from: CGRect) -> CGRect {
        return CGRect(x: 0, y: 0, width: from.size.width, height: from.size.height)
    }

}
