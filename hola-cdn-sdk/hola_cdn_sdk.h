//
//  hola_cdn_sdk.h
//  hola-cdn-sdk
//
//  Created by alexeym on 27/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
@import UIKit;
@import JavaScriptCore;
@import AVFoundation;
#import "hola_log.h"
#import "hola_cdn_player_proxy.h"
#import "GCDWebServer/GCDWebServer.h"

@class HolaCDN;
@class HolaCDNPlayerProxy;

@protocol HolaCDNDelegate <NSObject>

@optional
-(void)cdnDidLoaded:(nonnull HolaCDN*)cdn;

@optional
-(void)cdnDidAttached:(nonnull HolaCDN*)cdn;

@optional
-(void)cdnDidDetached:(nonnull HolaCDN*)cdn;

@optional
-(void)cdnStateChanged:(nonnull HolaCDN*)cdn toState:(nonnull NSString*)state;

@optional
-(void)cdnExceptionOccured:(nonnull HolaCDN*)cdn withError:(nullable NSError*)error;

@end

@interface HolaCDN : NSObject

+(void)setLogLevel:(HolaCDNLogLevel)level;
@property(readonly) int serverPort;

@property(nonnull, nonatomic, assign) id<HolaCDNDelegate> delegate;
@property(nonnull, readonly) NSString* customer;
@property(nullable, readonly) JSContext* ctx;
@property(nullable, readonly) GCDWebServer* server;
@property(nullable, readonly) HolaCDNPlayerProxy* playerProxy;
@property BOOL graphEnabled;

/*-(void)configWithCustomer:(NSString*)customer;
-(void)configWithCustomer:(NSString*)customer usingZone:(NSString*)zone;*/
-(void)configWithCustomer:(nonnull NSString*)customer usingZone:(nullable NSString*)zone andMode:(nullable NSString*)mode;

// public func config(customer: String, zone: String? = nil, mode: String? = nil) {

-(BOOL)load:(NSError * _Nullable * _Nullable)error;
-(void)attach:(nonnull AVPlayer*)player;

-(nullable JSContext*)getContext;
-(void)set_cdn_enabled:(nonnull NSString*)name enabled:(BOOL)enabled;

-(void)uninit;
-(void)unload;

-(void)get_stats:(nonnull void (^)(NSDictionary* _Nullable data))completionBlock;
-(void)get_timeline:(nonnull void (^)(NSDictionary* _Nullable data))completionBlock;
-(void)get_mode:(nonnull void (^)(NSString* _Nonnull mode))completionBlock;

@end
