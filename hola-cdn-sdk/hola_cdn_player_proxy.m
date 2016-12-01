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

@interface HolaCDNPlayerProxy()

@property NSString* state;
@property NSURL* videoUrl;
@property AVPlayerItem* cdnItem;
@property id timeObserver;
@property int req_id;

@end

@implementation HolaCDNPlayerProxy

static HolaCDNLog* _LOG;
static void * const kHolaCDNProxyContext = (void*)&kHolaCDNProxyContext;

@synthesize state = _state;
@synthesize ready = _ready;
@synthesize proxy_id = _proxy_id;

BOOL registered;
BOOL attached;
BOOL cancelled;
BOOL cache_disabled;

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

-(instancetype)initWithPlayer:(AVPlayer*)player andCDN:(HolaCDN *)cdn {
    self = [super init];
    if (self) {
        _LOG = [HolaCDNLog logWithModule:@"player"];

        _ready = NO;
        attached = NO;
        cancelled = NO;
        cache_disabled = NO;
        registered = NO;
        _duration = 0;
        _req_id = 1;
        _state = @"IDLE";

        _cdn = cdn;
        _player = player;

        [self updateItem];

        _proxy_id = [[NSUUID new] UUIDString];

        registered = YES;
        [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
        [[_cdn getContext][@"hola_ios_proxy"] setObject:self forKeyedSubscript:_proxy_id];
    }
    return self;
}

-(void)updateItem {
    if (_player == nil || _player.currentItem == nil) {
        _videoUrl = nil;
    }

    AVURLAsset* asset = (AVURLAsset*)_player.currentItem.asset;
    _videoUrl = asset.URL;
}

-(void)dealloc {
    [_LOG info:@"proxy dealloc"];

    [self proxyUninit];
}

-(void)proxyUninit {

}

-(HolaCDNAsset*)getAsset {
    if (_cdnItem != nil) {
        return (HolaCDNAsset*)_cdnItem.asset;
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
    if (_player == nil) {
        return 0;
    }

    return [NSNumber numberWithFloat:CMTimeGetSeconds([_player currentTime])];
}

-(NSNumber*)get_bitrate {
    AVPlayerItemAccessLogEvent* event = _player != nil ? [[[[_player currentItem] accessLog] events] lastObject] : nil;

    if (event != nil) {
        return [NSNumber numberWithFloat:[event indicatedBitrate]];
    }

    return 0;
}

-(NSArray*)get_buffered {
    NSArray<NSValue*>* timeRanges = _player != nil ? [[_player currentItem] loadedTimeRanges] : nil;

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
    [_LOG debug:@"not implemented"];
    return [NSDictionary new];
}

-(NSNumber*)get_bandwidth {
    AVPlayerItemAccessLogEvent* event = _player != nil ? [[[[_player currentItem] accessLog] events] lastObject] : nil;

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
    [_cdn onAttached];
}

-(void)wrapper_attached {
    if (attached) {
        [_LOG debug:@"wrapper_attached: already attached, do nothing"];
        return;
    }

    [_LOG debug:@"wrapper_attached: attaching..."];
    attached = YES;

    [_cdn get_mode:^(NSString* mode) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            if ([mode isEqual:@"cdn"]) {
                [_LOG debug:@"mode: cdn, doing attach"];
                // XXX alexeym: hack to count data correctly; need to fix cache for ios
                [[_cdn getContext] evaluateScript:@"hola_cdn._get_bws().disable_cache()"];
                [_LOG debug:@"cache disabled"];
                cache_disabled = YES;

                _cdnItem = _player.currentItem;
                HolaCDNAsset* asset = _cdnItem.asset;

                if ([asset attachTimeoutTriggered]) {
                    // XXX alexeym: TODO skip
                    [_LOG debug:@"Skip on attach (by asset timeout)"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self didAttached];
                        [self uninit];
                    });
                    return;
                }

                [_LOG debug:@"wait for asset duration"];
                __block BOOL assetTimeout = NO;
                [asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
                    if (assetTimeout) {
                        return;
                    }
                    assetTimeout = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_LOG debug:@"asset playable, main thread"];
                        [self removeObservers];
                        if (cancelled) {
                            [self didAttached];
                            return;
                        }

                        [self addObservers];
                        [self didAttached];
                    });
                }];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([_cdn loaderTimeout] * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    if (assetTimeout) {
                        return;
                    }
                    assetTimeout = YES;
                    [self didAttached];
                    [_cdn uninit];
                });

                [asset onAttached];
            } else {
                HolaCDNAsset* asset = _player.currentItem.asset;
                [asset onDetached];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self didAttached];
                });
            }
        });
    }];
}

-(void)log:(NSString*)msg {
    [_LOG debug:[NSString stringWithFormat:@"JS: %@", msg]];
}

-(NSDictionary*)settings:(NSDictionary*)opt {
    return @{
        @"player_id": [[NSUUID new] UUIDString]
    };
}

-(void)didDetached {
    _cdnItem = nil;
    _player = nil;

    [_cdn onDetached];
    
    _cdn = nil;
}

-(void)uninit {
    if (registered) {
        [_player removeObserver:self forKeyPath:@"currentItem" context:kHolaCDNProxyContext];
        registered = NO;
    }
    
    if (!attached) {
        [_LOG debug:@"proxy not attached on uninit"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didDetached];
        });
        return;
    }

    [_LOG info:[NSString stringWithFormat:@"Proxy uninit, id: %@", _proxy_id]];
    attached = NO;

    [self removeObservers];

    _duration = 0;
    [self setState:@"IDLE"];

    [self execute:@"on_ended"];
    if (cache_disabled) {
        [[_cdn getContext] evaluateScript:@"hola_cdn._get_bws().enable_cache()"];
        cache_disabled = NO;
    }
    [[_cdn getContext] setObject:nil forKeyedSubscript:@"hola_ios_proxy"];
    [self detachAsset];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self didDetached];
    });
}

-(void)detachAsset {
    if (_cdnItem != nil) {
        [(HolaCDNAsset*)_cdnItem.asset onDetached];
    }
}

-(void)addObservers {
    [_LOG debug:[NSString stringWithFormat:@"Add observers 1, id: %@", _proxy_id]];
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, 600) queue:nil usingBlock:^(CMTime time) {
        [self onTimeupdate:time];
    }];

    [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"currentItem.status" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"currentItem.duration" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"currentItem.loadedTimeRanges" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"currentItem.playbackBufferFull" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"currentItem.playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [_player addObserver:self forKeyPath:@"currentItem.error" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying) name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];

    _ready = YES;
}

-(void)removeObservers {
    [_LOG debug:[NSString stringWithFormat:@"Remove observers 1, id: %@", _proxy_id]];
    if (_timeObserver == nil) {
        [_LOG debug:@"Remove observers: not found"];
        return;
    }

    [_LOG debug:@"Remove observers 2"];
    [_player removeTimeObserver:_timeObserver];

    [_player removeObserver:self forKeyPath:@"status" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"rate" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"currentItem.status" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"currentItem.duration" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"currentItem.loadedTimeRanges" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"currentItem.playbackBufferFull" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"currentItem.playbackBufferEmpty" context:kHolaCDNProxyContext];
    [_player removeObserver:self forKeyPath:@"currentItem.error" context:kHolaCDNProxyContext];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];

    _timeObserver = nil;
}

-(void)onTimeupdate:(CMTime)time {
    if ([_state  isEqual: @"SEEKED"]) {
        [self setState:@"PLAYING"];
    }

    NSNumber* sec = [NSNumber numberWithFloat:CMTimeGetSeconds(time)];

    [self execute:@"on_timeupdate" withValue:sec];
}

-(void)itemDidFinishPlaying {
    [self setState:@"IDLE"];
    [self removeObservers];
    [self execute:@"on_ended"];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if (context != kHolaCDNProxyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if (_player == nil) {
        [_LOG warn:@"no player found in observer!"];
        return;
    }

    if (keyPath == nil) {
        [_LOG warn:@"null keyPath"];
        return;
    }

    if ([keyPath isEqualToString:@"currentItem"]) {
        [_LOG info:@"player.currentItem changed, calling uninit"];
        [_cdn uninit];

        if ([change objectForKey:NSKeyValueChangeNewKey] != [NSNull null]) {
            [_LOG info:@"Trying to attach cdn to the new item"];
            [_cdn attach:_player];
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        if (_player.rate == 0) {
            if ([_state  isEqual: @"IDLE"]) {
                [self setState:@"PAUSED"];
                [self execute:@"on_pause"];
            }
        } else {
            [self setState:@"PLAYING"];
            [self execute:@"on_play"];
        }
    } else if ([keyPath isEqualToString:@"status"]) {
        if (_player.status == AVPlayerStatusReadyToPlay) {
        } else if (_player.status == AVPlayerStatusFailed) {
            [self execute:@"on_error" withValue:@"player.status == .Failed"];
        } else if (_player.status == AVPlayerStatusUnknown) {
            [self setState:@"IDLE"];
            [self execute:@"on_idle"];
        }
    } else if ([keyPath isEqualToString:@"currentItem.loadedTimeRanges"]) {
        // on data loaded
    } else if ([keyPath isEqualToString:@"currentItem.status"]) {
        if (_player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
            if (_player.rate == 0) {
                if ([_state  isEqual: @"SEEKING"]) {
                    [self executeSeeking];
                }

                [self setState:@"SEEKED"];
                [self execute:@"on_seeked"];
            }
        } else if (_player.status == AVPlayerItemStatusFailed) {
            [self execute:@"on_error" withValue:@"currentItem.status == .Failed"];
        }
    } else if ([keyPath isEqualToString:@"currentItem.playbackBufferEmpty"]) {
        if (_player.rate == 0) {
            [self executeSeeking];
        }
    } else if ([keyPath isEqualToString:@"currentItem.error"]) {
        [_LOG err:[NSString stringWithFormat:@"currentItem.error: %@", change]];
        [self removeObservers];

        AVPlayerItemErrorLog* log = [_player.currentItem errorLog];
        if (log != nil) {
            AVPlayerItemErrorLogEvent* event = [log events].firstObject;
            if (event != nil) {
                NSLog(@"%ld: %@, %@", (long)event.errorStatusCode, event.errorDomain, event.errorComment);
            }
        }

        [self uninit];
    } else if ([keyPath isEqualToString:@"currentItem.duration"]) {
        CMTime duration = [[_player currentItem] duration];

        _duration = CMTimeGetSeconds(duration);
        if (isnan(_duration)) {
            _duration = -1;
        }
    }
}

-(void)executeSeeking {
    [self setState:@"SEEKING"];
    [self execute:@"on_seeking" withValue:[self get_pos]];
}

-(JSValue*)getDelegate {
    JSValue* list = [_cdn getContext][@"hola_ios_proxy"];

    if ([list isUndefined]) {
        [_LOG warn:@"getDelegate: proxy list is undefined"];
        return nil;
    }

    JSValue* proxy = list[_proxy_id];

    if ([proxy isUndefined]) {
        [_LOG warn:@"getDelegate: proxy is undefined"];
        return nil;
    }

    JSValue* delegate = proxy[@"delegate"];
    if ([delegate isUndefined]) {
        [_LOG warn:@"getDelegate: delegate is undefined"];
        return nil;
    }

    return delegate;
}

-(void)execute:(NSString*)method {
    [self execute:method withValue:nil];
}

-(void)execute:(NSString*)method withValue:(id)value {
    JSValue* delegate = [self getDelegate];

    if (delegate == nil) {
        [_LOG err:[NSString stringWithFormat:@"Trying to execute js: '%@'; no delegate found!", method]];
        return;
    }

    JSValue* callback = delegate[method];
    if ([callback isUndefined]) {
        [_LOG warn:[NSString stringWithFormat:@"Trying to execute js: '%@'; no callback found!", method]];
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
