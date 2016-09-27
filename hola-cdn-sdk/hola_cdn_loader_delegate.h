//
//  hola_cdn_loader_delegate.h
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "hola_cdn_sdk.h"
#import "GCDWebServer/GCDWebServer.h"

typedef NS_ENUM(int, HolaCDNScheme) {
   HolaCDNSchemeRedirect = 0,
   HolaCDNSchemeFetch,
   HolaCDNSchemeKey,
   HolaCDNSchemeProgressive
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

@property(readonly) dispatch_queue_t queue;

-(instancetype)initWithCDN:(HolaCDN*)cdn;
-(void)uninit;

-(void)processRequest:(NSString*)url forFrag:(int)frag_id withReq:(int)arg_req_id isRate:(BOOL)rate;
-(void)remove:(int)arg_req_id;
-(NSDictionary*)getSegmentInfo:(NSString*)url;

@end
