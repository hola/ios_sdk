//
//  hola_cdn_protocol.swift
//  hola_cdn
//
//  Created by norlin on 01/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

import Foundation

class HolaCDNProtocol: NSURLProtocol {
    static let domain = "org.hola.hola-cdn-sdk.protocol"
    
    static let scheme = "hcdnp"
    static var delegate: HolaCDNLoaderDelegate?
    
    var cdnTask: NSURLSessionTask?
    
    override class func canInitWithRequest(request: NSURLRequest) -> Bool {
        return request.URL?.scheme == "hcdnp"
    }
    
    override class func canonicalRequestForRequest(request: NSURLRequest) -> NSURLRequest {
        return request
    }
    
    override func startLoading() {
        guard let delegate = HolaCDNProtocol.delegate else {
            NSLog("no delegate found")
            return
        }
        
        guard let task = delegate.processRequest(request, client: self) else {
            client?.URLProtocol(self, didFailWithError: NSError(domain: HolaCDNProtocol.domain, code: HolaCDNErrorCodes.Missing, userInfo: [
                NSLocalizedFailureReasonErrorKey: "Can't create a data task"
            ]))
            
            return
        }
        
        cdnTask = task
        cdnTask!.resume()
    }
    
    override func stopLoading() {
        if let task = cdnTask {
            task.cancel()
            cdnTask = nil
        }
    }
    
    func didReceiveResponse(resp: NSURLResponse) {
        self.client!.URLProtocol(self, didReceiveResponse: resp, cacheStoragePolicy: .Allowed)
    }
    
    func didLoadData(data: NSData) {
        self.client!.URLProtocol(self, didLoadData: data)
        self.client!.URLProtocolDidFinishLoading(self)
    }
    
    func didFailWithError(err: NSError) {
        self.client!.URLProtocol(self, didFailWithError: err)
    }
}
