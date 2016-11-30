//
//  hola_cdn_server.h
//  hola-cdn-sdk
//
//  Created by alexeym on 30/11/2016.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "hola_cdn_sdk.h"
#import "GCDWebServer/GCDWebServer.h"
#import "GCDWebServer/GCDWebServerRequest.h"
#import "GCDWebServer/GCDWebServerDataResponse.h"

@interface HolaCDNServer : NSObject

@property(nullable, weak) HolaCDN* cdn;
@property(nonnull, readonly) GCDWebServer* server;

@property (nonnull) NSMutableDictionary<NSString*, HolaCDNLoaderDelegate*>* loaders;

-(nonnull instancetype)initWithCDN:(nonnull HolaCDN*)cdn;
-(void)start;
-(void)stop;
-(void)bindLoader:(nonnull HolaCDNLoaderDelegate*)loader;
-(void)unbindLoader:(nonnull HolaCDNLoaderDelegate*)loader;

@end
