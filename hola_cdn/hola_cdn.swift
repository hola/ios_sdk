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

enum HolaCDNError: String, ErrorType {
    case NotEnoughOptions = "Not enough options"
    case SomethingWrong = "Something goes wrong"
}

@objc(HolaCDN) public class HolaCDN: NSObject, UIWebViewDelegate {
    public var customer: String!
    public var customerZone: String!
    public var mode: String?

    static let domain = "https://player.h-cdn.com"
    
    static let bundle = NSBundle(identifier: "org.hola.hola-cdn-sdk")!
    static let build = bundle.infoDictionary!["CFBundleShortVersionString"] as! String
    
    static let webviewHTML = "<script>window.hola_cdn_sdk = {version:'\(build)'}</script><script src=\"\(domain)/loader_%@.js\"></script>"
    static let webviewUrl = "\(domain)/webview?customer=%@"
    
    static let serverPort: UInt = 8199
    
    static public func setLogLevel(level: HolaCDNLogLevel) {
        HolaCDNLog.setLevel(level)
    }
    
    let hola_cdn = "window.hola_cdn"
    
    let webview: UIWebView
    var ctx: JSContext!
    var playerProxy: HolaPlayerProxy?
    public var delegate: HolaCDNDelegate?

    var ready = false
    private var player: AVPlayer?
    
    private lazy var log = HolaCDNLog(module: "cdn")

    public override init() {
        webview = UIWebView()
        super.init()
    
        webview.delegate = self
    }
    
    public func config(customer: String, zone: String? = nil, mode: String? = nil) {
        self.customer = customer
        customerZone = zone
        self.mode = mode
        
        if (ready) {
            unload()
        }
    }

    public func load() throws {
        log.debug("load called")
        guard customer != nil else {
            throw HolaCDNError.NotEnoughOptions
        }
        
        log.info("load")
        if (ready) {
            self.delegate?.cdnDidLoaded?(self)
            return
        }

        guard let ctx = webview.valueForKeyPath("documentView.webView.mainFrame.javaScriptContext") as? JSContext else {
            log.err("No context on initContext")
            return
        }

        ctx.exceptionHandler = onException
        self.ctx = ctx
        
        let htmlString = String(format: HolaCDN.webviewHTML, customer)
        webview.loadHTMLString(htmlString, baseURL: makeWebviewUrl())
    }
    
    func makeWebviewUrl() -> NSURL {
        var url = String(format: HolaCDN.webviewUrl, customer)
        
        if let zone = customerZone {
            url += "&hola_zone="+zone
        }
        
        if let mode = self.mode {
            url += "&hola_mode="+mode
        }
        
        return NSURL(string: url)!
    }
    
    func getConfigArgs() -> [CVarArgType] {
        var configArgs = [CVarArgType]()
        
        if let zone = customerZone {
            configArgs.append("'\(zone)'")
        } else {
            configArgs.append("undefined")
        }
        
        if let mode = self.mode {
            configArgs.append("'\(mode)'")
        } else {
            configArgs.append("undefined")
        }
        
        return configArgs
    }

    public func webViewDidStartLoad(webView: UIWebView) {
        log.debug("webview loading...")
    }

    public func webView(webView: UIWebView, didFailLoadWithError error: NSError?) {
        log.err("page failed \(error)")
    }

    public func webViewDidFinishLoad(webView: UIWebView) {
        log.debug("page loaded!")

        ready = true
        self.delegate?.cdnDidLoaded?(self)

        dispatch_async(dispatch_get_main_queue()){
            if (self.ready && self.player != nil && self.playerProxy == nil) {
                // attach cdn automatically
                let backgroundQueue = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)
                dispatch_async(backgroundQueue) {
                    self.log.info("player autoinit")
                    self.attach(self.player!)
                }
            }
        }
    }

    public func attach(player: AVPlayer) {
        guard playerProxy == nil else {
            log.warn("CDN is already attached!")
            return
        }
        
        self.player = player
        
        guard ready else {
            log.info("not ready on attach: wait for player autoinit")
            return
        }

        log.info("attach")

        playerProxy = HolaPlayerProxy(player, cdn: self)

        let ios_ready = ctx.evaluateScript("\(hola_cdn).api.ios_ready")
        guard !ios_ready.isUndefined else {
            playerProxy = nil
            log.err("No ios_ready: something is wrong with cdn js")
            return
        }
        
        ios_ready.callWithArguments([])
    }

    public func get_mode() -> String {
        guard self.playerProxy != nil else {
            return ready ? "detached" : "loading"
        }
        
        let mode = ctx.evaluateScript("\(hola_cdn).get_mode()")
        
        return mode.toString()
    }
    
    public func get_stats() -> [NSObject: AnyObject]? {
        guard self.playerProxy != nil else {
            return nil
        }
        
        let stats = ctx.evaluateScript("\(hola_cdn).get_stats()")
        
        return stats.toDictionary()
    }

    public func uninit() {
        log.info("cdn uninit")
        
        playerProxy?.uninit()
        playerProxy = nil
        player = nil
    }
    
    public func unload() {
        uninit()
        ready = false
    }

    func onException(context: JSContext!, value: JSValue!) -> Void {
        log.err("JS Exception: \(value)")
        delegate?.cdnExceptionOccured?(self, error: value)
    }
}
