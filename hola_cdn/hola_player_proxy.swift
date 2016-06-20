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

    func fetch()

    func fetch_remove()

    func get_url() -> String

    func is_prepared()

    func get_duration() -> Double

    func get_pos() -> Double

    func get_bitrate() -> Double

    func get_buffered() -> [AnyObject]

    func get_levels()

    func get_bandwidth() -> Double

    func get_segment_info()

    func wrapper_attached()

    func uninit()
}

@objc class HolaPlayerProxy: NSObject, HolaPlayerExports {
    dynamic var ready = false
    var version = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as! String
    let cdn: HolaCDN

    var attached = false
    var state = "IDLE" {
        didSet {
            dispatch_async(dispatch_get_main_queue()) {
                self.cdn.delegate?.cdnStateChanged?(self.cdn, state: self.state)
            }
        }
    }

    var videoUrl = ""
    var timeObserver: AnyObject?

    var player: AVPlayer? {
        willSet {
            if timeObserver != nil {
                removeObservers()
            }
        }
        didSet {
            guard let player = self.player else {
                videoUrl = ""
                return
            }

            guard let asset = player.currentItem?.asset as? AVURLAsset else {
                print("ERR: AVPlayer must be initialized with NSURL!")
                self.player = nil
                return
            }

            videoUrl = asset.URL.absoluteString

            playerAdded()
        }
    }

    init(cdn: HolaCDN) {
        self.cdn = cdn
    }

    func wrapper_attached() {
        print("wrapper attached!!!")
        attached = true

        dispatch_async(dispatch_get_main_queue()) {
            self.cdn.delegate?.cdnDidAttached?(self.cdn)
        }
    }

    func uninit() {
        print("proxy.uninit")
        if (player == nil) {
            return
        }
        
        print("cdn.uninit execute")
        execute("on_ended")

        attached = false
        state = "IDLE"

        player = nil
        dispatch_async(dispatch_get_main_queue()) {
            self.cdn.delegate?.cdnDidDetached?(self.cdn)
        }
    }

    func get_state() -> String {
        NSLog("state: \(state)")
        return state
    }

    func fetch() {
        print("debug: fetch")
    }

    func fetch_remove() {
        print("debug: fetch_remove")
    }

    func get_url() -> String {
        return videoUrl
    }

    func is_prepared() {
        print("debug: is_prepared")
    }

    func get_duration() -> Double {
        guard let duration = player?.currentItem?.asset.duration else {
            return 0
        }

        return duration.seconds
    }

    func get_pos() -> Double {
        guard let currentTime = player?.currentTime() else {
            return 0
        }

        return currentTime.seconds
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

    func get_levels() {
        print("debug: get_levels")
    }

    func get_bandwidth() -> Double {
        guard let event = player?.currentItem?.accessLog()?.events.last else {
            return 0
        }

        return event.observedBitrate
    }

    func get_segment_info() {
        print("debug: get_segment_info")
    }
}

extension HolaPlayerProxy {

    func playerAdded() {
        guard let player = self.player else {
            return
        }
        
        cdn.ctx.setObject(self, forKeyedSubscript: "hola_ios_proxy")

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
        guard let player = self.player else {
            return
        }

        if let timeObserver = self.timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        player.removeObserver(self, forKeyPath: "status", context: nil)
        player.removeObserver(self, forKeyPath: "rate", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.status", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.duration", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.loadedTimeRanges", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.playbackBufferFull", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.playbackBufferEmpty", context: nil)
        player.removeObserver(self, forKeyPath: "currentItem.error", context: nil)

        NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemDidPlayToEndTimeNotification, object: player.currentItem)
        
        cdn.ctx.setObject(nil, forKeyedSubscript: "hola_ios_proxy")
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
        print("itemDidFinishPlaying")
        state = "IDLE"
        execute("on_ended")
    }

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard let player = self.player else {
            return
        }

        guard let keyPath = keyPath else {
            print("player: null keyPath")
            return
        }

        switch keyPath {
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
            execute("on_loaded")
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
        default:
            print("player: \(keyPath)")
        }
    }
    
    private func execute_seeking() {
        state = "SEEKING"
        execute("on_seeking", value: JSValue(double: get_pos(), inContext: self.cdn.ctx))
    }

    func delegateAvailable() -> Bool {
        return cdn.ctx.evaluateScript("!!(window.hola_ios_proxy && window.hola_ios_proxy.delegate)").toBool()
    }

    func execute(method: String, value: JSValue? = nil) {
        guard delegateAvailable() else {
            NSLog("execute '\(method)', no delegate")
            return
        }

        let jsMethod = "window.hola_ios_proxy.delegate.\(method)"
        let callback = cdn.ctx.evaluateScript("typeof \(jsMethod)=='function' && \(jsMethod)")
        if (callback.isUndefined || !callback.toBool()) {
            NSLog("execute '\(method)', undefined")
            return
        }

        if let value = value {
            callback.callWithArguments([value])
        } else {
            callback.callWithArguments([])
        }
    }

}
