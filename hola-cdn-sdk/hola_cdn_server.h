//
//  hola_cdn_server.h
//  hola-cdn-sdk
//
//  Created by alexeym on 30/11/2016.
//  Copyright © 2017 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "hola_cdn_sdk.h"
#import "GCDWebServer/GCDWebServer.h"
#import "GCDWebServer/GCDWebServerRequest.h"
#import "GCDWebServer/GCDWebServerDataResponse.h"

@interface HolaCDNServer : NSObject

@property(readonly) HolaCDNLog* log;
@property(weak) HolaCDN* cdn;
@property(readonly) GCDWebServer* server;

@property NSMutableDictionary<NSString*, HolaCDNLoaderDelegate*>* loaders;

-(instancetype)initWithCDN:(HolaCDN*)cdn;
-(void)start;
-(void)stop;
-(void)bindLoader:(HolaCDNLoaderDelegate*)loader;
-(void)unbindLoader:(HolaCDNLoaderDelegate*)loader;

@end
