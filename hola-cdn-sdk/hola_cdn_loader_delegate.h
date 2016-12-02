//
//  hola_cdn_loader_delegate.h
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "GCDWebServer/GCDWebServer.h"
#import "GCDWebServer/GCDWebServerDataResponse.h"
#import "hola_cdn_sdk.h"
#import "hola_cdn_player_proxy.h"
#import "hola_hls_parser.h"

@class HolaCDN;
@class HolaCDNPlayerProxy;

typedef NS_ENUM(int, HolaCDNScheme) {
   HolaCDNSchemeRedirect = 0,
   HolaCDNSchemeFetch,
   HolaCDNSchemeKey
};

typedef NS_ENUM(int, HolaScheme) {
   HolaSchemeHTTP = 0,
   HolaSchemeHTTPS
};

typedef NS_ENUM(int, HolaCDNErrorCode) {
   HolaCDNErrorCodeMissing = 0,
   HolaCDNErrorCodeUnprocessable = 0,
   HolaCDNErrorCodeBadRequest = 0,
   HolaCDNErrorCodeCancelled = 0
};

@interface HolaCDNLoaderDelegate: NSObject <AVAssetResourceLoaderDelegate, NSURLSessionDataDelegate>

+(NSURL*)applyCDNScheme:(NSURL*)url andType:(HolaCDNScheme)type;

@property(readonly) NSString* loaderUUID;
@property(readonly) dispatch_queue_t queue;
@property(nonatomic, assign) BOOL isAttached;
@property(weak) HolaCDNPlayerProxy* proxy;

@property(weak, readonly) HolaCDN* cdn;
@property(readonly) HolaHLSParser* parser;
@property(readonly) NSURLSession* session;

@property(readonly) NSMutableDictionary<NSNumber*, AVAssetResourceLoadingRequest*>* pending;
@property(readonly) NSMutableDictionary<NSString*, NSMutableDictionary*>* proxyRequests;
@property(readonly) NSMutableDictionary<NSNumber*, GCDWebServerCompletionBlock>* taskClients;
@property(readonly) NSMutableDictionary<NSNumber*, NSString*>* taskTimers;
@property(readonly) HolaCDNLog* log;
@property(readonly) HolaCDNLog* logNetwork;

-(instancetype)initWithCDN:(HolaCDN*)cdn;
-(void)attach;
-(void)uninit;

-(void)processRequest:(NSString*)url forFrag:(int)frag_id withReq:(int)arg_req_id isRate:(BOOL)rate;
-(void)remove:(int)arg_req_id;
-(NSDictionary*)getSegmentInfo:(NSString*)url;

-(void)processRequestWithUUID:(NSString*)uuid completionBlock:(GCDWebServerCompletionBlock)completion;

@end
