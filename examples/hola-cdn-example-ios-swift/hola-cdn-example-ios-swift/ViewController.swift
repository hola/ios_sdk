//
//  ViewController.swift
//  hola-cdn-example-ios-swift
//
//  Created by norlin on 24/01/2017.
//
//

import UIKit
import HolaCDN

class ViewController: UIViewController {

    var cdn: HolaCDN!
    var player: AVPlayer!
    var layer: AVPlayerLayer!

    override func viewDidLoad() {
        super.viewDidLoad()

        // turn on debug logging
        HolaCDN.setLogLevel(.debug)

        // create a HolaCDN instance for specific customer
        cdn = HolaCDN(customer: "demo", usingZone: nil, andMode: "cdn")

        // set timeout to 5 sec (default is 2 sec)
        // in case if HolaCDN JS Library is not downloaded in this timeout, the video will start to play without HolaCDN
        // in that case, you may see WARN log messages similar to this one:
        // [WARN/Proxy:1] Trying to execute js: 'on_timeupdate'; no delegate found!
        cdn.loaderTimeout = 5

        // init player for specific video
        let url = URL(string: "https://player.h-cdn.org/static/hls/cdn2/master.m3u8")!
        player = cdn.player(with: url)
        cdn.attach(player)

        // add player to the view
        layer = AVPlayerLayer(player: player)
        self.view.layer.addSublayer(layer)

        // start playback
        player.play()
    }

    override func viewWillLayoutSubviews() {
        // resize player layer to the view's bounds
        layer.frame = self.view.bounds
    }


}

