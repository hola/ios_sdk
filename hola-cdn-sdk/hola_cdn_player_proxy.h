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
@end

@interface HolaCDNPlayerProxy : NSObject <HolaPlayerExports>

@property(weak, readonly) HolaCDN* cdn;
@property(weak, readonly) AVPlayer* player;
@property(readonly) double duration;

-(instancetype)initWithPlayer:(AVPlayer*)player andCDN:(HolaCDN*)cdn;

-(void)proxyUninit;
-(void)execute:(NSString*)method;
-(void)execute:(NSString*)method withValue:(id)value;

@end
