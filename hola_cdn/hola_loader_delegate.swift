//
//  hola_loader_delegate.swift
//  hola_cdn
//
//  Created by norlin on 22/06/16.
//  Copyright © 2016 hola. All rights reserved.
//

import Foundation
import AVFoundation
import JavaScriptCore
import GCDWebServers

enum HolaScheme {
    case HTTP
    case HTTPS
}

enum HolaCDNScheme {
    case Redirect
    case Fetch
    case Key
}

struct HolaCDNErrorCodes {
    static let Missing = 404
    static let Unprocessable = 422
    static let BadRequest = 400
    static let Cancelled = 410
}

struct HolaProxyRequest {
    let uuid: String
    let id: Int
    let target: NSURL
    var timer: NSDate? = nil
    var statusCode: Int
    var contentType: String
    var data: NSMutableData
    var size: Int = 0
}

@objc class HolaCDNLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    /* Class methods */
    static func getOriginSchemeName(scheme: HolaScheme) -> String {
        switch scheme {
        case .HTTP: return "http"
        case .HTTPS: return "https"
        }
    }

    static func getCDNSchemeName(scheme: HolaScheme, type: HolaCDNScheme) -> String {
        switch (scheme, type) {
        case (.HTTP, .Redirect):
            return "hcdnr"
        case (.HTTP, .Fetch):
            return "hcdnf"
        case (.HTTP, .Key):
            return "hcdnk"
        case (.HTTPS, .Redirect):
            return "hcdnrs"
        case (.HTTPS, .Fetch):
            return "hcdnfs"
        case (.HTTPS, .Key):
            return "hcdnks"
        }
    }

    static func mapScheme(scheme: String) -> HolaScheme {
        switch scheme {
        case "http", "hcdnf", "hcdnr", "hcdnk": return .HTTP
        case "https", "hcdnfs", "hcdnrs", "hcdnks": return .HTTPS
        default: return .HTTP
        }
    }

    static func mapCDNScheme(url: NSURL) -> HolaCDNScheme {
        let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: true)!

        switch components.scheme! {
        case "http", "https", "hcdnf": return .Fetch
        case "hcdnr", "hcdnrs": return .Redirect
        case "hcdnk", "hcdnks": return .Key
        default: return .Fetch
        }
    }

    static func applyCDNScheme(url: NSURL, type: HolaCDNScheme) -> NSURL {
        let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: true)!
        let scheme = mapScheme(components.scheme!)

        components.scheme = getCDNSchemeName(scheme, type: type)

        return components.URL!
    }

    static func applyOriginScheme(url: NSURL) -> NSURL {
        let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: true)!
        let scheme = mapScheme(components.scheme!)

        components.scheme = getOriginSchemeName(scheme)

        return components.URL!
    }

    static let domain = "org.hola.hola-cdn-sdk.loader"
    private var req_id = 1

    private var pending: [Int: AVAssetResourceLoadingRequest?] = [:]
    private var proxyRequests: [String: HolaProxyRequest] = [:]
    private var taskTimers: [Int: String] = [:]
    private var taskClients: [Int: GCDWebServerCompletionBlock] = [:]
    
    private var server: GCDWebServer!

    /* Instance methods */
    private let cdn: HolaCDN

    private let parser: HolaHLSParser
    private var session: NSURLSession!
    
    private lazy var log = HolaCDNLog(module: "loader")

    let queue: dispatch_queue_t

    init(_ cdn: HolaCDN) {
        self.cdn = cdn
        queue = dispatch_queue_create("org.hola.hola-cdn-sdk.loader", nil)
        parser = HolaHLSParser()
        
        GCDWebServer.setLogLevel(5)
        server = GCDWebServer()

        super.init()

        session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration(), delegate: self, delegateQueue: nil)
        
        server.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self) { self.processRequest($0, completionBlock: $1) }
        try! server.startWithOptions([
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_Port: HolaCDN.serverPort,
            GCDWebServerOption_BonjourName: "HolaCDN"
        ])
    }
    
    func uninit() {
        session.invalidateAndCancel()
        session = nil
        server.stop()
        server = nil
    }

    private func getRequest(req_id: Int) -> AVAssetResourceLoadingRequest? {
        guard let req = pending[req_id] else {
            return nil
        }

        pending[req_id] = nil
        return req
    }

    func resourceLoader(resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        return makeRequest(loadingRequest)
    }

    func resourceLoader(resourceLoader: AVAssetResourceLoader, didCancelLoadingRequest loadingRequest: AVAssetResourceLoadingRequest) {
        log.debug("didCancelLoadingRequest")
    }

    func resourceLoader(resourceLoader: AVAssetResourceLoader, didCancelAuthenticationChallenge authenticationChallenge: NSURLAuthenticationChallenge) {
        log.debug("didCancelAuthenticationChallenge")
    }

    func resourceLoader(resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        log.debug("shouldWaitForRenewalOfRequestedResource")

        return true
    }

    func resourceLoader(resourceLoader: AVAssetResourceLoader, shouldWaitForResponseToAuthenticationChallenge authenticationChallenge: NSURLAuthenticationChallenge) -> Bool {
        log.debug("shouldWaitForResponseToAuthenticationChallenge")

        return true
    }

    private func makeRequest(req: AVAssetResourceLoadingRequest) -> Bool {
        guard let proxy = cdn.playerProxy else {
            log.err("Trying to make request, but no player attached!")
            return false
        }

        guard let reqUrl = req.request.URL else {
            return false
        }

        let req_id = self.req_id
        pending[req_id] = req

        let originUrl = HolaCDNLoaderDelegate.applyOriginScheme(reqUrl)

        dispatch_async(dispatch_get_main_queue()) {
            let request = JSValue(object: ["url": originUrl.absoluteString, "req_id": req_id], inContext: self.cdn.ctx)
            proxy.execute("req", value: request)
        }

        self.req_id += 1

        return true
    }

    func processRequest(url: String, frag_id: Int, req_id: Int, rate: Bool) {
        if (pending[frag_id] == nil) {
            log.warn("Unknown req_id \(frag_id)")
            return
        }

        sendOpen(req_id)

        if (rate) {
            processExternalRequest(url, req_id: req_id)
            return
        }

        guard let req = getRequest(frag_id) else {
            processExternalRequest(url, req_id: req_id)
            return
        }

        processInternalRequest(url, req: req, req_id: req_id)
    }

    private func processExternalRequest(url: String, req_id: Int) {
        let url = HolaCDNLoaderDelegate.applyOriginScheme(NSURL(string: url)!)

        do {
            let date = NSDate()
            let data = try NSData(contentsOfURL: url, options: .DataReadingUncached)
            let interval = NSDate().timeIntervalSinceDate(date)

            sendResponse(req_id, ms: Int(interval * 1000), statusCode: 200)
            sendProgress(req_id, loaded: data.length, total: data.length)
            sendComplete(req_id)
        } catch {
            log.err("external fetch error \(error)")
            sendError(req_id)
        }
    }

    private func processInternalRequest(url: String, req: AVAssetResourceLoadingRequest, req_id: Int) {
        let reqUrl = req.request.URL!

        let scheme = HolaCDNLoaderDelegate.mapCDNScheme(reqUrl)

        switch scheme {
        case .Redirect:
            redirect(url, req: req, req_id: req_id)
        case .Fetch:
            fetch(req, req_id: req_id)
        case .Key:
            fetch(req, req_id: req_id, key: true)
        }
    }

    private func sendError(req: AVAssetResourceLoadingRequest, msg: String = "") {
        log.err(msg)
        
        dispatch_async(queue) {
            req.finishLoadingWithError(NSError(domain: HolaCDNLoaderDelegate.domain, code: HolaCDNErrorCodes.BadRequest, userInfo: [
                NSLocalizedFailureReasonErrorKey: msg
            ]))
        }
    }

    private func fetch(req: AVAssetResourceLoadingRequest, req_id: Int, key: Bool = false) {
        let url = HolaCDNLoaderDelegate.applyOriginScheme(req.request.URL!)

        do {
            let date = NSDate()
            let nsData: NSData
            if (key) {
                nsData = NSData(contentsOfURL: url)!
            } else {
                let data = try String(contentsOfURL: url)
                let manifest = try parser.parse(url.absoluteString, data: data)
                nsData = NSData(data: manifest.dataUsingEncoding(NSUTF8StringEncoding)!)
            }
            let interval = NSDate().timeIntervalSinceDate(date)

            dispatch_async(queue) {
                req.dataRequest?.respondWithData(nsData)
                req.finishLoading()
            }

            sendResponse(req_id, ms: Int(interval * 1000), statusCode: 200)
            sendProgress(req_id, loaded: nsData.length, total: nsData.length)
            sendComplete(req_id)
        } catch is HolaHLSError {
            sendError(req, msg: "Can't parse data!")
            sendError(req_id)
        } catch {
            sendError(req, msg: "Can't fetch data!")
            sendError(req_id)
        }
    }

    private func redirect(url: String, req: AVAssetResourceLoadingRequest, req_id: Int) {
        let url = NSURL(string: url)!
        let proxyRec = HolaProxyRequest(uuid: NSUUID().UUIDString, id: req_id, target: url, timer: nil, statusCode: 0, contentType: "", data: NSMutableData(), size: 0)
        self.proxyRequests[proxyRec.uuid] = proxyRec

        dispatch_async(self.queue) {
            let redirect = NSURLRequest(URL: NSURL(string: "http://127.0.0.1:\(HolaCDN.serverPort)/\(proxyRec.uuid)")!)
            
            req.redirect = redirect
            req.response = NSHTTPURLResponse(URL: url, statusCode: 302, HTTPVersion: nil, headerFields: nil)
            req.finishLoading()
        }
    }

    func remove(req_id: Int) {
        guard let req = getRequest(req_id) else {
            return
        }

        dispatch_async(queue) {
            req.finishLoadingWithError(NSError(domain: HolaCDNLoaderDelegate.domain, code: HolaCDNErrorCodes.Cancelled, userInfo: [
                NSLocalizedFailureReasonErrorKey: "Request cancelled"
            ]))
        }
    }

    func getSegmentInfo(url: String) -> [String: AnyObject] {
        return parser.getSegmentInfo(url)
    }

    private func sendMessage(message: String, data: AnyObject) {
        guard let proxy = cdn.playerProxy else {
            log.err("Trying to send message, but no player attached!")
            return
        }

        dispatch_async(dispatch_get_main_queue()) {
            let request = JSValue(object: data, inContext: self.cdn.ctx)
            proxy.execute(message, value: request)
        }
    }

    private func sendOpen(req_id: Int) {
        let response: [String: AnyObject] = ["req_id": req_id]
        sendMessage("stream_open", data: response)
    }

    private func sendResponse(req_id: Int, ms: Int, statusCode: Int) {
        let response: [String: AnyObject] = [
            "req_id": req_id,
            "ms": ms,
            "status": statusCode
        ]

        sendMessage("stream_response", data: response)
    }

    private func sendProgress(req_id: Int, loaded: Int, total: Int) {
        let response: [String: AnyObject] = [
            "req_id": req_id,
            "loaded": loaded,
            "total": total
        ]

        sendMessage("stream_progress", data: response)
    }

    private func sendComplete(req_id: Int) {
        let response: [String: AnyObject] = ["req_id": req_id]
        sendMessage("stream_complete", data: response)
    }

    private func sendError(req_id: Int) {
        let response: [String: AnyObject] = ["req_id": req_id]
        sendMessage("stream_error", data: response)
    }
}

// data fetching
extension HolaCDNLoaderDelegate: NSURLSessionDataDelegate {

    func processRequest(request: GCDWebServerRequest, completionBlock: GCDWebServerCompletionBlock) {
        guard let path = request.URL.pathComponents else {
            completionBlock(GCDWebServerDataResponse(statusCode: 400))
            return
        }
        
        let uuid = path[1]
        
        guard let task = processRequest(uuid, completion: completionBlock) else {
            completionBlock(GCDWebServerDataResponse(statusCode: 400))
            return
        }
        
        task.resume()
    }

    func processRequest(uuid: String, completion: GCDWebServerCompletionBlock) -> NSURLSessionDataTask? {
        guard let proxyReq = proxyRequests[uuid] else {
            log.warn("process request: no proxy request found!")
            completion(GCDWebServerDataResponse(statusCode: 400))
            return nil
        }

        let url = HolaCDNLoaderDelegate.applyOriginScheme(proxyReq.target)
        let request = NSURLRequest(URL: url)

        let task = session.dataTaskWithRequest(request)
        taskClients[task.taskIdentifier] = completion

        proxyRequests[uuid]!.timer = NSDate()
        taskTimers[task.taskIdentifier] = proxyReq.uuid
        
        return task
    }

    private func handleResponse(req: HolaProxyRequest, resp: NSHTTPURLResponse) {
        let ms: Int
        if let timer = req.timer {
            let interval = NSDate().timeIntervalSinceDate(timer)

            ms = Int(interval * 1000)
        } else {
            ms = 100
        }
        
        let size: Int
        if let length = resp.allHeaderFields["Content-Length"] as? String {
            size = Int(length)!
        } else {
            size = 0
        }
        
        proxyRequests[req.uuid]?.size = size
        proxyRequests[req.uuid]?.statusCode = resp.statusCode
        proxyRequests[req.uuid]?.contentType = resp.MIMEType!
        
        sendResponse(req.id, ms: ms, statusCode: resp.statusCode)
    }

    private func redirectProgress(req: HolaProxyRequest) {
        sendProgress(req.id, loaded: req.data.length, total: req.size)
    }

    private func redirectComplete(req: HolaProxyRequest) {
        sendComplete(req.id)
    }

    private func redirectError(req: HolaProxyRequest, err: NSError) {
        sendError(req.id)
    }

    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
        guard let client = taskClients[dataTask.taskIdentifier] else {
            completionHandler(.Cancel)
            return
        }
        
        guard let uuid = taskTimers[dataTask.taskIdentifier] else {
            completionHandler(.Cancel)
            client(GCDWebServerDataResponse(statusCode: 400))
            return
        }

        guard let proxyReq = proxyRequests[uuid] else {
            completionHandler(.Cancel)
            client(GCDWebServerDataResponse(statusCode: 400))
            return
        }

        handleResponse(proxyReq, resp: response as! NSHTTPURLResponse)
        completionHandler(.Allow)
    }

    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        guard let uuid = taskTimers[dataTask.taskIdentifier] else {
            return
        }

        guard let proxyReq = proxyRequests[uuid] else {
            return
        }

        proxyReq.data.appendData(data)
    }

    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        guard let client = taskClients[task.taskIdentifier] else {
            return
        }

        taskClients[task.taskIdentifier] = nil

        if let err = error {
            log.err("\(err)")
            client(GCDWebServerDataResponse(statusCode: 502))
        }

        guard let uuid = taskTimers[task.taskIdentifier] else {
            return
        }

        taskTimers[task.taskIdentifier] = nil

        guard let proxyReq = proxyRequests[uuid] else {
            return
        }

        proxyRequests[uuid] = nil
        
        self.redirectProgress(proxyReq)
        
        if let err = error {
            self.redirectError(proxyReq, err: err)
        } else {
            client(GCDWebServerDataResponse(data: proxyReq.data, contentType: proxyReq.contentType))
            self.redirectComplete(proxyReq)
        }
    }
}
