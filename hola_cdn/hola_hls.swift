//
//  hola_hls.swift
//  hola_cdn
//
//  Created by norlin on 23/06/16.
//  Copyright © 2016 hola. All rights reserved.
//

import Foundation

class HolaSegmentInfo: NSObject {
    var url: String!
    var duration: Double!
    var bitrate: Int { return level.bitrate }
    var size: Double { return Double(bitrate) * duration }
    
    weak var level: HolaLevelInfo!
    
    func getInfo() -> [String: AnyObject] {
        return [
            "playlist_url": level.url,
            "bitrate": bitrate,
            "url": url,
            "duration": duration,
            "media_index": level.segments.indexOf(self)!
        ]
    }
}

class HolaLevelInfo: NSObject {
    var bitrate: Int!
    var url: String!
    var segments: [HolaSegmentInfo] = []
    
    func getInfo() -> [String: AnyObject] {
        var segmentsInfo:[[String: AnyObject]] = []
        for segment in segments {
            segmentsInfo.append(segment.getInfo())
        }
        
        return [
            "url": url,
            "bitrate": bitrate,
            "segments": segmentsInfo
        ]
    }
}

enum HolaLevelState {
    case Top
    case Inner
}

enum HolaHLSError: ErrorType {
    case Header
    case Bandwidth
    case Duration
    case Obvious(String)
}

enum HolaHLSEntry {
    case Header
    case Playlist
    case Segment
    case Key
    case Url
    case Other
}

class HolaHLSParser {
    var levels: [HolaLevelInfo] = []
    var master: NSURL?
    
    private lazy var log = HolaCDNLog(module: "parser")

    func parse(url: String, data: String) throws -> String {
        var level: HolaLevelInfo
        var segment = HolaSegmentInfo()
        
        var state = getUrlState(url)
        switch state {
        case .Top:
            master = NSURL(string: url)
            level = HolaLevelInfo()
        case .Inner:
            level = getUrlLevel(url)
        }
    
        guard data.hasPrefix("#EXTM3U") else {
            throw HolaHLSError.Header
        }
        
        var lines = data.componentsSeparatedByString("\n")
        
        for (index, line) in lines.enumerate() {
            switch self.getEntryType(line) {
            case .Playlist:
                guard let bwPos = line.rangeOfString("BANDWIDTH") else {
                    throw HolaHLSError.Bandwidth
                }

                if let bwEnd = line.rangeOfString(",", options: [], range: bwPos.endIndex..<line.endIndex) {
                    level.bitrate = Int(line.substringWithRange(bwPos.endIndex.successor()..<bwEnd.startIndex))!
                } else {
                    level.bitrate = Int(line.substringFromIndex(bwPos.endIndex))
                }
            case .Segment:
                if (state == .Top) {
                    state = .Inner
                    
                    level.bitrate = 1
                    level.url = url
                    
                    master = NSURL(string: url)
                    levels.append(level)
                }
                
                let durStart = line.startIndex.advancedBy(8)
                guard let durEnd = line.rangeOfString(",", options: [], range: durStart..<line.endIndex) else {
                    throw HolaHLSError.Duration
                }
                
                segment.duration = Double(line.substringWithRange(durStart..<durEnd.startIndex))
            case .Url:
                let levelUrl = NSURL(string: line, relativeToURL: master!)!
                let urlString = levelUrl.absoluteString
                
                let cdnLevelUrl: NSURL
                switch state {
                case .Top:
                    level.url = urlString
                    levels.append(level)
                    level = HolaLevelInfo()
                    cdnLevelUrl = HolaCDNLoaderDelegate.applyCDNScheme(levelUrl, type: HolaCDNScheme.Fetch)
                case .Inner:
                    segment.url = urlString
                    level.segments.append(segment)
                    segment.level = level
                    segment = HolaSegmentInfo()
                    cdnLevelUrl = HolaCDNLoaderDelegate.applyCDNScheme(levelUrl, type: HolaCDNScheme.Redirect)
                }
                
                lines[index] = cdnLevelUrl.absoluteString
            case .Key:
                guard let keyPos = line.rangeOfString("URI=") else {
                    break
                }
                
                guard let keyEnd = line.rangeOfString("\"", options: [], range: keyPos.endIndex.successor()..<line.endIndex) else {
                    break
                }
                
                let keyRange = keyPos.endIndex.successor()..<keyEnd.startIndex
                let keyUrlString = line.substringWithRange(keyRange)
                let keyUrl = NSURL(string: keyUrlString, relativeToURL: master)!
                
                let customKeyUrl = HolaCDNLoaderDelegate.applyCDNScheme(keyUrl, type: HolaCDNScheme.Key)
                lines[index] = line.stringByReplacingCharactersInRange(keyRange, withString: customKeyUrl.absoluteString)
            default: break
            }
        }
        
        return lines.joinWithSeparator("\n")
    }
    
    func getSegmentInfo(url: String) -> [String: AnyObject]  {
        for level in levels {
            for segment in level.segments {
                if (segment.url.hasSuffix(url)) {
                    return segment.getInfo()
                }
            }
        }
        
        return [:]
    }
    
    func getSegmentSize(url: String) -> Double  {
        for level in levels {
            for segment in level.segments {
                if (segment.url.hasSuffix(url)) {
                    return segment.size
                }
            }
        }
        
        return 0
    }
    
    func getLevels() -> [String: AnyObject] {
        var response:[String: AnyObject] = [:]
        
        for level in levels {
            if (level.segments.isEmpty) {
                continue
            }
            
            response[level.url] = level.getInfo()
        }
        
        return response
    }
    
    private func getUrlState(url: String) -> HolaLevelState {
        for level in levels {
            if (url.hasSuffix(level.url)) {
                return .Inner
            }
        }
        
        return .Top
    }
    
    private func getUrlLevel(url: String) -> HolaLevelInfo {
        for level in levels {
            if (url.hasSuffix(level.url)) {
                return level
            }
            
            for segment in level.segments {
                if (url.hasSuffix(segment.url)) {
                    return level
                }
            }
        }
        
        return HolaLevelInfo()
    }
    
    private func getEntryType(entry: String) -> HolaHLSEntry {
        if (entry.hasPrefix("#EXTM3U")) {
            return .Header
        }
        
        if (entry.hasPrefix("#EXT-X-STREAM-INF")) {
            return .Playlist
        }
        
        if (entry.hasPrefix("#EXTINF")) {
            return .Segment
        }
        
        if (entry.hasPrefix("#EXT-X-KEY")) {
            return .Key
        }
        
        if (entry.isEmpty) {
            return .Other
        }
        
        if (!entry.hasPrefix("#")) {
            return .Url
        }
        
        return .Other
    }
}
