//
//  hola_asset.swift
//  hola_cdn
//
//  Created by norlin on 21/06/16.
//  Copyright © 2016 hola. All rights reserved.
//

import Foundation
import AVFoundation

@objc class HolaCDNAsset: AVURLAsset {
    let loader: HolaCDNLoaderDelegate
    
    init(URL: NSURL, cdn: HolaCDN) {
        let url = HolaCDNLoaderDelegate.applyCDNScheme(URL, type: HolaCDNScheme.Fetch)
        loader = HolaCDNLoaderDelegate(cdn)
        
        super.init(URL: url, options: nil)
        
        self.resourceLoader.setDelegate(loader, queue: loader.queue)
    }
    
    deinit {
        loader.uninit()
    }
}
