//
//  HolaCDNPlayerProxy.h
//  hola-cdn-sdk
//
//  Created by alexeym on 28/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "hola_cdn_sdk.h"

@import JavaScriptCore;
@import AVFoundation;

@class HolaCDN;

@protocol HolaPlayerExports <JSExport>

@property(readonly) BOOL ready;
@property(readonly) NSString* proxy_id;

-(NSString*)get_state;

-(int)fetch:(NSString*)url :(int)req_id :(BOOL)rate;

-(void)fetch_remove:(int)req_id;

-(NSString*)get_url;

-(NSNumber*)get_duration;

-(NSNumber*)get_pos;

-(NSNumber*)get_bitrate;

-(NSArray*)get_buffered;

-(NSDictionary*)get_levels;

-(NSNumber*)get_bandwidth;

-(NSDictionary*)get_segment_info:(NSString*)url;

-(void)wrapper_attached;

-(void)uninit;

-(void)log:(NSString*)msg;

-(NSDictionary*)settings:(NSDictionary*)opt;

-(NSString*)get_app_label;
@end

@interface HolaCDNPlayerProxy : NSObject <HolaPlayerExports>

@property(readonly) HolaCDNLog* log;
@property(weak, readonly) HolaCDN* cdn;
@property(weak, readonly) AVPlayerItem* item;
@property(readonly) double duration;

@property(readonly)BOOL attached;
@property(readonly)BOOL cancelled;
@property(readonly)int bws_idx;
@property(readonly)BOOL cache_disabled;

@property(readonly) NSString* state;
@property(readonly) NSURL* videoUrl;
@property(readonly) int req_id;

-(instancetype)initWithItem:(AVPlayerItem*)item andCDN:(HolaCDN*)cdn;

-(void)onPlay;
-(void)onPause;
-(void)onSeeking;
-(void)onSeeked;
-(void)onIdle;
-(void)onEnded;
-(void)onDuration:(CMTime)duration;
-(void)onTimeupdate:(CMTime)time;
-(void)onPlayerError;
-(void)onItemError;

-(void)execute:(NSString*)method;
-(void)execute:(NSString*)method withValue:(id)value;

@end
