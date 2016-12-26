//
//  hola_cdn_player_item.h
//  hola-cdn-sdk
//
//  Created by alexeym on 01/12/2016.
//  Copyright © 2016 hola. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "hola_cdn_sdk.h"
#import "hola_cdn_player_proxy.h"
#import "hola_cdn_asset.h"

@class HolaCDN;
@class HolaCDNPlayerProxy;

@interface HolaCDNPlayerItem: AVPlayerItem

@property(readonly) HolaCDNLog* log;
@property(weak, readonly) HolaCDN* cdn;
@property(readonly) HolaCDNPlayerProxy* proxy;
@property(weak, readonly) AVPlayer* player;
@property(readonly)BOOL registered;
@property(readonly) float rate;
@property(readonly) BOOL attached;

-(instancetype)initWithURL:(NSURL*)URL andCDN:(HolaCDN *)cdn;
-(void)dealloc;
-(void)attach:(AVPlayer*)player;
-(void)uninit;
-(void)detach;
-(void)onPlay:(float)rate;
-(void)onPause:(float)rate;
-(void)onIdle;
-(void)onPlayerError;
-(void)onTimeupdate:(CMTime)time;

-(void)onAttached;
-(void)onDetached;

@end
