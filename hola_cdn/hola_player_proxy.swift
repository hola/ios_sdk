//
//  hola_player_proxy.swift
//  HolaCDN SDK
//
//  Created by norlin on 09/06/16.
//  Copyright © 2016 hola. All rights reserved.
//

import Foundation
import AVFoundation
import JavaScriptCore

@objc protocol HolaPlayerExports: JSExport {
    var ready: Bool { get set }

    var version: String { get }

    func get_state() -> String

    func fetch(url: String, _ req_id: Int, _ rate: Bool) -> Int

    func fetch_remove(req_id: Int)

    func get_url() -> String

    func get_duration() -> Double

    func get_pos() -> Double

    func get_bitrate() -> Double

    func get_buffered() -> [AnyObject]

    func get_levels() -> [String: AnyObject]

    func get_bandwidth() -> Double

    func get_segment_info(url: String) -> [String: AnyObject]

    func wrapper_attached()

    func uninit()

    func settings(opt: [String: AnyObject]?) -> [String: AnyObject]

    func log(msg: String)
}

@objc class HolaPlayerProxy: NSObject {
    dynamic var ready = false
    var version = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as! String
    let cdn: HolaCDN
    
    private lazy var log = HolaCDNLog(module: "player")

    var attached = false
    var state = "IDLE" {
        didSet {
            dispatch_async(dispatch_get_main_queue()) {
                self.cdn.delegate?.cdnStateChanged?(self.cdn, state: self.state)
            }
        }
    }

    weak var player: AVPlayer!
    let videoUrl: NSURL

    var timeObserver: AnyObject!
    var originalItem: AVPlayerItem!
    var cdnItem: AVPlayerItem?

    var duration: Double

    var req_id = 1

    init(_ player: AVPlayer, cdn: HolaCDN) {
        self.cdn = cdn
        self.player = player

        duration = 0

        guard let playerItem = player.currentItem else {
            videoUrl = NSURL(string: "")!

            super.init()
            log.err("AVPlayer must have a playerItem!")
            return
        }

        self.originalItem = playerItem

        guard let asset = playerItem.asset as? AVURLAsset else {
            videoUrl = NSURL(string: "")!

            super.init()
            log.err("AVPlayer must be initialized with AVURLAsset or NSURL!")
            return
        }

        videoUrl = asset.URL

        super.init()

        player.addObserver(self, forKeyPath: "currentItem", options: NSKeyValueObservingOptions.New, context: nil)
        cdn.ctx.setObject(self, forKeyedSubscript: "hola_ios_proxy")
    }

    deinit {
        log.debug("proxy deinit!")
        uninit()
    }
}

extension HolaPlayerProxy: HolaPlayerExports {

    func log(msg: String) {
        log.debug("JS: \(msg)")
    }

    func wrapper_attached() {
        guard !attached else {
            return
        }

        attached = true

        if (cdn.get_mode() == "cdn") {
            // XXX alexeym: hack to count data correctly; need to fix cache for ios
            dispatch_async(dispatch_get_main_queue()) {
                self.cdn.ctx.evaluateScript("hola_cdn._get_bws().disable_cache()")
            }
            
            let asset = HolaCDNAsset(URL: videoUrl, cdn: cdn)
            cdnItem = AVPlayerItem(asset: asset)
            replacePlayerItem(cdnItem!)
        }

        addObservers()

        dispatch_async(dispatch_get_main_queue()) {
            self.cdn.delegate?.cdnDidAttached?(self.cdn)
        }
    }

    func uninit() {
        guard attached else {
            return
        }

        log.info("proxy uninit")
        attached = false

        removeObservers()
        player.removeObserver(self, forKeyPath: "currentItem")

        duration = 0
        state = "IDLE"
        execute("on_ended")
        cdn.ctx.setObject(nil, forKeyedSubscript: "hola_ios_proxy")

        if (cdnItem != nil) {
            dispatch_async(dispatch_get_main_queue()) {
                self.replacePlayerItem(self.originalItem)
                self.originalItem = nil
                self.player = nil
            }

            cdnItem = nil
        }

        dispatch_async(dispatch_get_main_queue()) {
            self.cdn.delegate?.cdnDidDetached?(self.cdn)
        }
    }

    func get_state() -> String {
        return state
    }

    private func getLoader() -> HolaCDNLoaderDelegate? {
        return getAsset()?.resourceLoader.delegate as? HolaCDNLoaderDelegate
    }

    private func getAsset() -> AVURLAsset? {
        return cdnItem?.asset as? AVURLAsset
    }

    func fetch(url: String, _ req_id: Int, _ rate: Bool = false) -> Int {
        guard let loader = getLoader() else {
            return 0
        }

        let currentId = self.req_id

        loader.processRequest(url, frag_id: req_id, req_id: currentId, rate: rate)

        self.req_id += 1
        return currentId
    }

    func fetch_remove(req_id: Int) {
        guard let loader = getLoader() else {
            return
        }

        loader.remove(req_id)
    }

    func get_url() -> String {
        return videoUrl.absoluteString
    }

    func get_duration() -> Double {
        return duration
    }

    func get_pos() -> Double {
        guard let player = self.player else {
            return 0
        }
        
        return player.currentTime().seconds
    }

    func get_bitrate() -> Double {
        guard let event = player?.currentItem?.accessLog()?.events.last else {
            return 0
        }

        return event.indicatedBitrate
    }

    func get_buffered() -> [AnyObject] {
        guard let timeRanges = player?.currentItem?.loadedTimeRanges else {
            return []
        }

        let ranges = timeRanges.map { val -> AnyObject in
            let range = val.CMTimeRangeValue

            return ["start": range.start.seconds, "end": range.end.seconds]
        }

        return ranges
    }

    func get_levels() -> [String: AnyObject] {
        log.debug("debug: get_levels")

        return [:]
    }

    func get_bandwidth() -> Double {
        guard let event = player?.currentItem?.accessLog()?.events.last else {
            return 0
        }

        return event.observedBitrate
    }

    func get_segment_info(url: String) -> [String: AnyObject]  {
        guard let loader = getLoader() else {
            return [:]
        }

        return loader.getSegmentInfo(url)
    }

    func settings(opt: [String : AnyObject]?) -> [String : AnyObject] {
        return ["player_id": NSUUID().UUIDString]
    }
}

extension HolaPlayerProxy {

    func replacePlayerItem(newItem: AVPlayerItem) {
        let rate = player.rate
        player.rate = 0
        let position = player.currentTime()

        player.replaceCurrentItemWithPlayerItem(newItem)

        player.seekToTime(position)
        player.rate = rate
    }

    func addObservers() {
        timeObserver = player.addPeriodicTimeObserverForInterval(CMTimeMakeWithSeconds(0.5, 600), queue: nil, usingBlock: onTimeupdate)

        player.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.New, context: nil)
        player.addObserver(self, forKeyPath: "rate", options: NSKeyValueObservingOptions.New, context: nil)

        player.addObserver(self, forKeyPath: "currentItem.status", options: NSKeyValueObservingOptions.New, context: nil)
        player.addObserver(self, forKeyPath: "currentItem.duration", options: NSKeyValueObservingOptions.New, context: nil)
        player.addObserver(self, forKeyPath: "currentItem.loadedTimeRanges", options: NSKeyValueObservingOptions.New, context: nil)
        player.addObserver(self, forKeyPath: "currentItem.playbackBufferFull", options: NSKeyValueObservingOptions.New, context: nil)
        player.addObserver(self, forKeyPath: "currentItem.playbackBufferEmpty", options: NSKeyValueObservingOptions.New, context: nil)
        player.addObserver(self, forKeyPath: "currentItem.error", options: NSKeyValueObservingOptions.New, context: nil)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.itemDidFinishPlaying), name: AVPlayerItemDidPlayToEndTimeNotification, object: player.currentItem)

        observeValueForKeyPath("status", ofObject: self, change: nil, context: nil)
        observeValueForKeyPath("rate", ofObject: self, change: nil, context: nil)

        ready = true
    }

    func removeObservers() {
        player.removeTimeObserver(timeObserver)

        player.removeObserver(self, forKeyPath: "status", context: nil)
        player.removeObserver(self, forKeyPath: "rate", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.status", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.duration", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.loadedTimeRanges", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.playbackBufferFull", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.playbackBufferEmpty", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.error", context: nil)

        NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemDidPlayToEndTimeNotification, object: player.currentItem)
    }

    private func onTimeupdate(time: CMTime) {
        let value = Double(time.value)
        let scale = Double(time.timescale)

        let sec:Double = value / scale
        let js_sec = JSValue(double: sec, inContext: self.cdn.ctx)

        if (state == "SEEKED") {
            state = "PLAYING"
        }

        execute("on_timeupdate", value: js_sec)
    }

    @objc private func itemDidFinishPlaying() {
        state = "IDLE"
        execute("on_ended")
    }

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard let keyPath = keyPath else {
            log.warn("null keyPath")
            return
        }

        switch keyPath {
        case "currentItem":
            if (player.currentItem?.asset as? HolaCDNAsset == nil) {
                log.warn("CurrentItem changed from outside, calling uninit")
                uninit()
                return
            }
        case "rate":
            if (player.rate == 0) {
                if (state != "IDLE") {
                    state = "PAUSED"
                    execute("on_pause")
                }
            } else {
                state = "PLAYING"
                execute("on_play")
            }
        case "status":
            switch player.status {
            case .ReadyToPlay:
                execute("on_ready")
            case .Failed:
                execute("on_error", value: JSValue(newErrorFromMessage: "player.status == .Failed", inContext: self.cdn.ctx))
            case .Unknown:
                state = "IDLE"
                execute("on_idle")
            }
        case "currentItem.loadedTimeRanges":
            //execute("on_loaded")
            break
        case "currentItem.status":
            switch player.currentItem?.status {
            case .Some(.ReadyToPlay):
                if (player.rate == 0) {
                    if (state != "SEEKING") {
                        execute_seeking()
                    }

                    state = "SEEKED"
                    execute("on_seeked");
                }
            case .Some(.Failed):
                execute("on_error", value: JSValue(newErrorFromMessage: "currentItem.status == .Failed", inContext: self.cdn.ctx))
            default:
                break
            }
        case "currentItem.playbackBufferEmpty":
            if (player.rate == 0) {
                execute_seeking()
            }
        case "currentItem.error":
            log.err("currentItem.error: \(change)")
            if let events = player.currentItem?.errorLog()?.events {
                let e = events[0]
                print("\(e.errorStatusCode): \(e.errorDomain), \(e.errorComment)")
            }
            uninit()
        case "currentItem.duration":
            if let seconds = player.currentItem?.duration.seconds {
                duration = seconds
            }
        default: break
        }
    }

    private func execute_seeking() {
        state = "SEEKING"
        execute("on_seeking", value: JSValue(double: get_pos(), inContext: self.cdn.ctx))
    }

    func getDelegate() -> JSValue? {
        let proxy = cdn.ctx.objectForKeyedSubscript("hola_ios_proxy")
        if (proxy.isUndefined) {
            return nil
        }

        let delegate = proxy.objectForKeyedSubscript("delegate")

        if (delegate.isUndefined) {
            return nil
        }

        return delegate
    }

    func execute(method: String, value: JSValue? = nil) {
        dispatch_async(dispatch_get_main_queue()){
            guard let delegate = self.getDelegate() else {
                self.log.err("Trying to execute js: '\(method)'; no delegate found!")
                return
            }

            let callback = delegate.objectForKeyedSubscript(method)
            if (callback.isUndefined || !callback.toBool()) {
                self.log.warn("execute '\(method)")
                return
            }

            if let value = value {
                callback.callWithArguments([value])
            } else {
                callback.callWithArguments([])
            }
        }
    }

}
