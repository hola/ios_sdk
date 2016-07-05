//
//  hola_log.swift
//  hola_cdn
//
//  Created by norlin on 04/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

import Foundation

public enum HolaCDNLogLevel: Int {
    case None = 0
    case Debug = 1
    case Info = 2
    case Warning = 3
    case Error = 4
    case Critical = 5
}

class HolaCDNLog: NSObject {
    static var level: HolaCDNLogLevel = .Error
    static func setLevel(level: HolaCDNLogLevel) {
        HolaCDNLog.level = level
    }
    
    let module: String
    
    init(module: String) {
        self.module = module
    }
    
    private func prefix(level: HolaCDNLogLevel) -> String {
        let levelString: String
        
        switch level {
        case .Debug:
            levelString = "DEBUG"
            break
        case .Info:
            levelString = "INFO "
            break
        case .Warning:
            levelString = "WARN "
            break
        case .Error:
            levelString = "ERR  "
            break
        case .Critical:
            levelString = "CRIT "
            break
        case .None:
            return ""
        }
        
        return "[\(levelString)/\(module)] "
    }
    
    private func rawLog(level: HolaCDNLogLevel, msg: String) {
        if (level.rawValue < HolaCDNLog.level.rawValue) {
            return
        }
        
        let prefix = self.prefix(level)
        
        NSLog("\(prefix)\(msg)")
    }
    
    func debug(msg: String) {
        rawLog(.Debug, msg: msg)
    }
    
    func info(msg: String) {
        rawLog(.Info, msg: msg)
    }
    
    func warn(msg: String) {
        rawLog(.Warning, msg: msg)
    }
    
    func err(msg: String) {
        rawLog(.Error, msg: msg)
    }
    
    func crit(msg: String) {
        rawLog(.Critical, msg: msg)
    }
}
