//
//  HolaCDNPlayerProxy.m
//  hola-cdn-sdk
//
//  Created by alexeym on 28/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_player_proxy.h"
#import "hola_log.h"
#import "hola_cdn_asset.h"
#import "hola_cdn_loader_delegate.h"

@implementation HolaCDNPlayerProxy

@synthesize state = _state;
@synthesize ready = _ready;
@synthesize proxy_id = _proxy_id;

-(void)setState:(NSString*)state {
    _state = state;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_cdn.delegate != nil) {
            if ([_cdn.delegate respondsToSelector:@selector(cdnStateChanged:toState:)]) {
                [_cdn.delegate cdnStateChanged:_cdn toState:state];
            }
        }
    });
}
-(NSString*)state {
    return _state;
}

-(instancetype)initWithItem:(AVPlayerItem*)item andCDN:(HolaCDN*)cdn {
    self = [super init];
    if (self) {
        _log = [HolaCDNLog logWithModule:@"Proxy"];

        _ready = NO;
        _attached = NO;
        _cancelled = NO;
        _cache_disabled = NO;
        _duration = 0;
        _req_id = 1;
        _state = @"IDLE";

        _cdn = cdn;
        _item = item;

        [self updateItem];

        _proxy_id = [[NSUUID new] UUIDString];
        [[_cdn getContext][@"hola_ios_proxy"] setObject:self forKeyedSubscript:_proxy_id];
    }
    return self;
}

-(void)updateItem {
    if (_item == nil) {
        _videoUrl = nil;
        return;
    }

    AVURLAsset* asset = (AVURLAsset*)_item.asset;
    _videoUrl = [asset.URL copy];
}

-(void)dealloc {
    [_log info:@"proxy dealloc"];

    [self proxyUninit];
}

-(void)proxyUninit {

}

-(HolaCDNAsset*)getAsset {
    if (_item != nil) {
        return (HolaCDNAsset*)_item.asset;
    }

    return nil;
}

-(HolaCDNLoaderDelegate*)getLoader {
    HolaCDNAsset* asset = [self getAsset];
    if (asset != nil) {
        return (HolaCDNLoaderDelegate*)asset.resourceLoader.delegate;
    }

    return nil;
}

// JS Proxy methods

-(NSString*)get_state {
    return _state;
}

-(int)fetch:(NSString*)url :(int)arg_req_id :(BOOL)rate {
    HolaCDNLoaderDelegate* loader = [self getLoader];

    if (loader == nil) {
        return 0;
    }

    int currentId = _req_id;

    [loader processRequest:url forFrag:arg_req_id withReq:currentId isRate:rate];

    _req_id += 1;
    return currentId;
}

-(void)fetch_remove:(int)req_id {
    HolaCDNLoaderDelegate* loader = [self getLoader];

    if (loader == nil) {
        return;
    }

    [loader remove:req_id];
}

-(NSString*)get_url {
    return [_videoUrl absoluteString];
}

-(NSNumber*)get_duration {
    return [NSNumber numberWithFloat:_duration];
}

-(NSNumber*)get_pos {
    if (_item == nil) {
        return 0;
    }

    return [NSNumber numberWithFloat:CMTimeGetSeconds([_item currentTime])];
}

-(NSNumber*)get_bitrate {
    AVPlayerItemAccessLogEvent* event = _item != nil ? [[[_item accessLog] events] lastObject] : nil;

    if (event != nil) {
        return [NSNumber numberWithFloat:[event indicatedBitrate]];
    }

    return 0;
}

-(NSArray*)get_buffered {
    NSArray<NSValue*>* timeRanges = _item != nil ? [_item loadedTimeRanges] : nil;

    if (timeRanges == nil) {
        return [NSArray new];
    }

    NSMutableArray<NSDictionary*>* ranges = [NSMutableArray new];
    [timeRanges enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        CMTimeRange range = [obj CMTimeRangeValue];
        [ranges addObject:@{
            @"start": [NSNumber numberWithFloat:CMTimeGetSeconds(range.start)],
            @"end": [NSNumber numberWithFloat:CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)]
        }];
    }];

    return ranges.copy;
}

-(NSDictionary*)get_levels {
    [_log debug:@"not implemented"];
    return [NSDictionary new];
}

-(NSNumber*)get_bandwidth {
    AVPlayerItemAccessLogEvent* event = _item != nil ? [[[_item accessLog] events] lastObject] : nil;

    if (event != nil) {
        return [NSNumber numberWithFloat:[event observedBitrate]];
    }

    return 0;
}

-(NSDictionary*)get_segment_info:(NSString*)url {
    HolaCDNLoaderDelegate* loader = [self getLoader];

    if (loader == nil) {
        return @{};
    }

    return [loader getSegmentInfo:url];
}

-(void)didAttached {
    [(HolaCDNPlayerItem*)_item onAttached];
}

-(void)wrapper_attached {
    if (_attached) {
        [_log debug:@"wrapper_attached: already attached, do nothing"];
        return;
    }

    [_log debug:@"wrapper_attached: attaching..."];
    _attached = YES;

    JSValue* delegate = [self getDelegate];
    if (delegate != nil) {
        _bws_idx = [[delegate[@"id"] toNumber] intValue];
    } else {
        _bws_idx = 0;
    }

    [_cdn get_mode:^(NSString* mode) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            if ([mode isEqual:@"cdn"]) {
                [_log debug:@"mode: cdn, doing attach"];
                // XXX alexeym: hack to count data correctly; need to fix cache for ios
                [self callBws:@"disable_cache"];
                [_log debug:@"cache disabled"];
                _cache_disabled = YES;

                HolaCDNAsset* asset = _item.asset;

                if ([asset attachTimeoutTriggered]) {
                    // XXX alexeym: TODO skip
                    [_log debug:@"Skip on attach (by asset timeout)"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self didAttached];
                        [self uninit];
                    });
                    return;
                }

                [_log debug:@"Wait for asset duration..."];
                __block BOOL assetTimeout = NO;
                [asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
                    if (assetTimeout) {
                        return;
                    }
                    assetTimeout = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_log debug:@"...asset playable"];
                        if (_cancelled) {
                            [self didAttached];
                            return;
                        }

                        [self didAttached];
                    });
                }];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    if (assetTimeout) {
                        return;
                    }
                    [_log debug:@"Uninit by timeout (waited for the asset duration)"];
                    assetTimeout = YES;
                    [self didAttached];
                    [self uninit];
                });

                [asset onAttached];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_log debug:[NSString stringWithFormat:@"Uninit by cdn mode: %@", mode]];
                    [self didAttached];
                    [self uninit];
                });
            }
        });
    }];
}

-(void)log:(NSString*)msg {
    [_log debug:[NSString stringWithFormat:@"JS: %@", msg]];
}

-(NSDictionary*)settings:(NSDictionary*)opt {
    return @{
        @"player_id": [[NSUUID new] UUIDString]
    };
}

-(void)didDetached {
    [_log debug:[NSString stringWithFormat:@"didDetached: %p", _item]];
    [(HolaCDNPlayerItem*)_item onDetached];
    _item = nil;
    _cdn = nil;
}

-(void)uninit {
    if (!_attached) {
        [_log debug:@"proxy not attached on uninit"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didDetached];
        });
        return;
    }

    [_log info:[NSString stringWithFormat:@"Proxy uninit%@", [JSContext currentContext] == nil ? @"" : @" from js"]];
    _attached = NO;

    _duration = 0;
    [self setState:@"IDLE"];

    [self execute:@"on_ended"];
    if (_cache_disabled) {
        [self callBws:@"enable_cache"];
        _cache_disabled = NO;
    }
    [[_cdn getContext][@"hola_ios_proxy"] setObject:nil forKeyedSubscript:_proxy_id];
    [self detachAsset];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self didDetached];
    });
}

-(void)detachAsset {
    if (_item != nil) {
        [(HolaCDNAsset*)_item.asset onDetached];
    }
}

-(void)onTimeupdate:(CMTime)time {
    if ([_state isEqual: @"SEEKED"]) {
        [self setState:@"PLAYING"];
    }

    NSNumber* sec = [NSNumber numberWithFloat:CMTimeGetSeconds(time)];

    [self execute:@"on_timeupdate" withValue:sec];
}

-(void)itemDidFinishPlaying {
    [self setState:@"IDLE"];
    [self execute:@"on_ended"];
}

-(void)onSeeking {
    [self executeSeeking];
}

-(void)onSeeked {
    if ([_state isEqual: @"SEEKING"]) {
        [self executeSeeking];
    }

    [self setState:@"SEEKED"];
    [self execute:@"on_seeked"];
}

-(void)onPlay {
    [self setState:@"PLAYING"];
    [self execute:@"on_play"];
}

-(void)onPause {
    if ([_state isEqual: @"IDLE"]) {
        [self setState:@"PAUSED"];
        [self execute:@"on_pause"];
    }
}

-(void)onIdle {
    [self setState:@"IDLE"];
    [self execute:@"on_idle"];
}

-(void)onDuration:(CMTime)duration {
    _duration = CMTimeGetSeconds(duration);
    if (isnan(_duration)) {
        _duration = -1;
    }

}

-(void)onItemError {
    [self execute:@"on_error" withValue:@"status == .Failed"];
}

-(void)onPlayerError {
    [_log err:@"Player error"];
    [self execute:@"on_error" withValue:@"player.status == .Failed"];
}

-(void)executeSeeking {
    [self setState:@"SEEKING"];
    [self execute:@"on_seeking" withValue:[self get_pos]];
}

-(JSValue*)getDelegate {
    JSValue* list = [_cdn getContext][@"hola_ios_proxy"];

    if ([list isUndefined]) {
        [_log warn:@"getDelegate: proxy list is undefined"];
        return nil;
    }

    JSValue* proxy = list[_proxy_id];

    if ([proxy isUndefined]) {
        [_log warn:@"getDelegate: proxy is undefined"];
        return nil;
    }

    JSValue* delegate = proxy[@"delegate"];
    if ([delegate isUndefined]) {
        [_log warn:@"getDelegate: delegate is undefined"];
        return nil;
    }

    return delegate;
}

-(void)callBws:(NSString*)method {
    NSString* bws = [NSString stringWithFormat:@"hola_cdn._get_bws({idx:%d})", _bws_idx];
    [[_cdn getContext] evaluateScript:[NSString stringWithFormat:@"%@ && %@.%@()", bws, bws, method]];
}

-(void)execute:(NSString*)method {
    [self execute:method withValue:nil];
}

-(void)execute:(NSString*)method withValue:(id)value {
    JSValue* delegate = [self getDelegate];

    if (delegate == nil) {
        [_log err:[NSString stringWithFormat:@"Trying to execute js: '%@'; no delegate found!", method]];
        return;
    }

    JSValue* callback = delegate[method];
    if ([callback isUndefined]) {
        [_log warn:[NSString stringWithFormat:@"Trying to execute js: '%@'; no callback found!", method]];
        return;
    }

    NSArray* args;
    if (value == nil) {
        args = @[callback, @0];
    } else {
        args = @[callback, @0, value];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [callback.context[@"setTimeout"] callWithArguments:args];
    });
}

@end
