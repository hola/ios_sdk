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
#import "hola_cdn_player_item.h"
#import "hola_cdn_asset.h"
#import "hola_cdn_loader_delegate.h"
#import "hola_cdn_server.h"

@class HolaCDN;
@class HolaCDNPlayerProxy;
@class HolaCDNPlayerItem;
@class HolaCDNAsset;
@class HolaCDNLoaderDelegate;
@class HolaCDNServer;

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
-(void)cdnDidLoaded:(HolaCDN*)cdn;

@optional
-(void)cdnDidAttached:(HolaCDN*)cdn;

@optional
-(void)cdnDidDetached:(HolaCDN*)cdn;

@optional
-(void)cdnStateChanged:(HolaCDN*)cdn toState:(NSString*)state;

@optional
-(void)cdnExceptionOccured:(HolaCDN*)cdn withError:(NSError*)error;

@end

@interface HolaCDN : NSObject

+(void)setLogLevel:(HolaCDNLogLevel)level;
+(void)setLogModules:(NSArray*)modules;
@property(readonly) int serverPort;

@property(readonly) HolaCDNLog* log;

@property id<HolaCDNDelegate> delegate;
@property(readonly) NSString* customer;
@property(readonly) JSContext* ctx;
@property(readonly) AVPlayer* player;
@property(readonly) id timeObserver;
@property HolaCDNServer* server;
@property BOOL graphEnabled;
@property double loaderTimeout; // Timeout in sec before using saved HolaCDN library

@property(readonly) BOOL ready;
@property(readonly) HolaCDNBusy inProgress;
@property(readonly) HolaCDNAction nextAction;

@property(readonly) AVPlayer* nextAttach;

-(instancetype)init __deprecated_msg("Use `initWithCustomer:` method");
-(instancetype)initWithCustomer:(NSString*)customer usingZone:(NSString*)zone andMode:(NSString*)mode;

-(void)configWithCustomer:(NSString*)customer usingZone:(NSString*)zone andMode:(NSString*)mode __deprecated_msg("Use `initWithCustomer:` method");

-(BOOL)load:(NSError**)error __deprecated_msg("No need to use this method anymore");
-(AVPlayer*)attach:(AVPlayer*)player;

-(AVPlayerItem*)playerItemWithURL:(NSURL*)url;
-(AVPlayerItem*)playerItemFromItem:(AVPlayerItem*)item;
-(AVPlayer*)playerWithPlayerItem:(AVPlayerItem*)playerItem;
-(AVPlayer*)playerWithURL:(NSURL*)url;
-(AVQueuePlayer*)queuePlayerWithURL:(NSURL*)url;
-(AVQueuePlayer*)queuePlayerWithPlayerItem:(AVPlayerItem*)playerItem;
-(AVQueuePlayer*)queuePlayerWithItems:(NSArray<AVPlayerItem*>*)items;

-(JSContext*)getContext;
-(void)set_cdn_enabled:(NSString*)name enabled:(BOOL)enabled;

-(void)uninit;
-(void)unload;

-(void)onAttached;
-(void)onDetached;

-(void)refreshJS;

-(void)get_stats:(void (^)(NSDictionary* data))completionBlock;
-(void)get_timeline:(void (^)(NSDictionary* data))completionBlock;
-(void)get_mode:(void (^)(NSString* mode))completionBlock;

@end
