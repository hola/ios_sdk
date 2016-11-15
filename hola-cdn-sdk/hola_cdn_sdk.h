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

typedef NS_ENUM(int, HolaCDNBusy) {
    HolaCDNBusyNone = 0,
    HolaCDNBusyLoading,
    HolaCDNBusyAttaching,
    HolaCDNBusyDetaching,
    HolaCDNBusyUnloading
};

typedef NS_ENUM(int, HolaCDNAction) {
    HolaCDNActionNone = 0,
    HolaCDNActionLoad,
    HolaCDNActionAttach,
    HolaCDNActionUninit,
    HolaCDNActionUnload
};

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

-(nonnull instancetype)init __deprecated_msg("Use `initWithCustomer:` method");
-(nonnull instancetype)initWithCustomer:(nonnull NSString*)customer usingZone:(nullable NSString*)zone andMode:(nullable NSString*)mode;

-(void)configWithCustomer:(nonnull NSString*)customer usingZone:(nullable NSString*)zone andMode:(nullable NSString*)mode __deprecated_msg("Use `initWithCustomer:` method");

// public func config(customer: String, zone: String? = nil, mode: String? = nil) {

-(BOOL)load:(NSError * _Nullable * _Nullable)error __deprecated_msg("No need to use this method anymore");
-(void)attach:(nonnull AVPlayer*)player;

-(nullable JSContext*)getContext;
-(void)set_cdn_enabled:(nonnull NSString*)name enabled:(BOOL)enabled;

-(void)uninit;
-(void)unload __deprecated_msg("Use `uninit` method");

-(void)onAttached;
-(void)onDetached;

-(void)get_stats:(nonnull void (^)(NSDictionary* _Nullable data))completionBlock;
-(void)get_timeline:(nonnull void (^)(NSDictionary* _Nullable data))completionBlock;
-(void)get_mode:(nonnull void (^)(NSString* _Nonnull mode))completionBlock;

@end
