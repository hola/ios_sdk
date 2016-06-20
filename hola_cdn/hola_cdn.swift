//
//  hola_cdn.swift
//  HolaCDN SDK
//
//  Created by alexeym on 09/06/16.
//  Copyright © 2016 hola. All rights reserved.
//

import UIKit
import JavaScriptCore
import AVFoundation
import AVKit

@objc public protocol HolaCDNDelegate: NSObjectProtocol {
    optional func cdnDidLoaded(cdn: HolaCDN) -> Void
    optional func cdnDidAttached(cdn: HolaCDN) -> Void
    optional func cdnDidDetached(cdn: HolaCDN) -> Void
    optional func cdnStateChanged(cdn: HolaCDN, state: String) -> Void
    optional func cdnExceptionOccured(cdn: HolaCDN, error: JSValue) -> Void
}

@objc(HolaCDN) public class HolaCDN: NSObject, UIWebViewDelegate {
    public let customer: String

    static let domain = "https://player.h-cdn.com"
    static let webviewHTML = "<script src=\"\(domain)/loader_%@.js?https=1\"></script>"
    static let webviewUrl = "\(domain)/webview?customer=%@"
    
    let hola_cdn = "window.hola_cdn"
    
    let webview: UIWebView
    var ctx: JSContext!
    private var playerProxy: HolaPlayerProxy!
    public var delegate: HolaCDNDelegate?

    var ready = false
    var attached = false
    private var player: AVPlayer?

    public init(customer: String) {
        self.customer = customer
        webview = UIWebView()
        super.init()

        playerProxy = HolaPlayerProxy(cdn: self)
        webview.delegate = self
    }

    public func load() {
        NSLog("cdn.load")
        if (ready) {
            print("loaded, just call a delegate")
            self.delegate?.cdnDidLoaded?(self)
            return
        }

        guard let ctx = webview.valueForKeyPath("documentView.webView.mainFrame.javaScriptContext") as? JSContext else {
            NSLog("ERR: no context on initContext")
            return
        }

        ctx.exceptionHandler = onException

        self.ctx = ctx

        let urlString = String(format: HolaCDN.webviewUrl, customer)
        let url = NSURL(string: urlString)!
        
        let htmlString = String(format: HolaCDN.webviewHTML, customer)
        webview.loadHTMLString(htmlString, baseURL: url)
    }

    public func webViewDidStartLoad(webView: UIWebView) {
        NSLog("webview loading...")
    }

    public func webView(webView: UIWebView, didFailLoadWithError error: NSError?) {
        NSLog("page failed \(error)")
    }

    public func webViewDidFinishLoad(webView: UIWebView) {
        NSLog("page loaded!")

        ready = true
        self.delegate?.cdnDidLoaded?(self)

        dispatch_async(dispatch_get_main_queue()){
            if (self.player != nil && !self.attached) {
                // attach cdn automatically
                NSLog("webview ready player autoinit")
                self.attach(self.player!)
            }
        }
    }

    public func attach(player: AVPlayer) {
        NSLog("attach")
        if (!ready) {
            NSLog("not ready on attach: set player")
            self.player = player
            return
        }

        if (attached) {
            NSLog("CDN is already attached!")
            return
        }
        
        NSLog("cdn attach")

        playerProxy.player = player
        let ios_ready = ctx.evaluateScript("\(hola_cdn).api.ios_ready")
        if (ios_ready.isUndefined) {
            NSLog("No ios_ready: something is wrong with cdn loader")
            return
        }
        
        ios_ready.callWithArguments([])
        
        attached = true
    }

    public func get_mode() -> String {
        if (!attached) {
            return "detached"
        }
        
        let mode = ctx.evaluateScript("\(hola_cdn).get_mode()")
        
        return mode.toString()
    }

    public func uninit() {
        print("cdn.uninit")
        playerProxy.uninit()
        attached = false
        player = nil
    }
    
    public func unload() {
        uninit()
        ready = false
    }

    func onException(context: JSContext!, value: JSValue!) -> Void {
        NSLog("JS Exception:  \(value)")
        delegate?.cdnExceptionOccured?(self, error: value)
    }
}
