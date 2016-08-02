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
@property AVPlayerItem* originalItem;
@property AVPlayerItem* cdnItem;
@property id timeObserver;
@property int req_id;

@end

@implementation HolaCDNPlayerProxy

static HolaCDNLog* _LOG;

@synthesize state = _state;
@synthesize ready = _ready;

BOOL attached = false;

-(void)setState:(NSString*)state {
    _state = state;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_cdn.delegate != nil) {
            [_cdn.delegate cdnStateChanged:_cdn toState:state];
        }
    });
}
-(NSString*)state {
    return _state;
}

-(instancetype)initWithPlayer:(AVPlayer *)player andCDN:(HolaCDN *)cdn {
    self = [super init];
    if (self) {
        _LOG = [HolaCDNLog new];
        [_LOG setModule:@"player"];

        _ready = false;
        _duration = 0;
        _req_id = 1;
        _state = @"IDLE";

        _cdn = cdn;
        _player = player;

        if (player.currentItem == nil) {
            [_LOG err:@"AVPlayer must have a playerItem!"];
            return self;
        }

        _originalItem = player.currentItem;

        if (![player.currentItem.asset isKindOfClass:[AVURLAsset class]]) {
            [_LOG err:@"AVPlayer must be initialized with AVURLAsset or NSURL!"];
            return self;
        }

        AVURLAsset* asset = (AVURLAsset*)player.currentItem.asset;

        _videoUrl = asset.URL;

        [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionNew context:nil];
        [_cdn.ctx setObject:self forKeyedSubscript:@"hola_ios_proxy"];
    }
    return self;
}

-(void)dealloc {
    [_LOG debug:@"proxy dealloc"];

    [self proxyUninit];
}

-(void)proxyUninit {

}

-(AVURLAsset*)getAsset {
    if (_cdnItem != nil) {
        return (AVURLAsset*)_cdnItem.asset;
    }

    return nil;
}

-(HolaCDNLoaderDelegate*)getLoader {
    AVURLAsset* asset = [self getAsset];
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

    return timeRanges;
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

-(void)wrapper_attached {
    if (attached) {
        return;
    }

    [_LOG debug:@"wrapper_attached: attaching..."];
    attached = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[_cdn get_mode] isEqual:@"cdn"]) {
            // XXX alexeym: hack to count data correctly; need to fix cache for ios
            [_cdn.ctx evaluateScript:@"hola_cdn._get_bws().disable_cache()"];

            AVURLAsset* asset = (AVURLAsset*)[[HolaCDNAsset alloc] initWithURL:_videoUrl andCDN:_cdn];
            _cdnItem = [AVPlayerItem playerItemWithAsset:asset];
            [self replacePlayerItem:_cdnItem];
        }

        [self addObservers];

        if (_cdn.delegate != nil) {
            [_cdn.delegate cdnDidAttached:self.cdn];
        }
    });
}

-(void)log:(NSString*)msg {
    [_LOG debug:[NSString stringWithFormat:@"JS: %@", msg]];
}

-(NSDictionary*)settings:(NSDictionary*)opt {
    return @{
        @"player_id": [[NSUUID new] UUIDString]
    };
}

-(void)uninit {
    if (!attached) {
        return;
    }

    [_LOG info:@"proxy uninit"];
    attached = NO;

    [self removeObservers];
    [_player removeObserver:self forKeyPath:@"currentItem"];

    _duration = 0;
    [self setState:@"IDLE"];

    [self execute:@"on_ended"];
    [_cdn.ctx setObject:nil forKeyedSubscript:@"hola_ios_proxy"];

    if (_cdnItem != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self replacePlayerItem:_originalItem];
            _originalItem = nil;
            _player = nil;
        });

        _cdnItem = nil;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_cdn.delegate != nil) {
            [_cdn.delegate cdnDidDetached:self.cdn];
        }
    });
}

-(void)replacePlayerItem:(AVPlayerItem*)newItem {
    float rate = _player.rate;
    _player.rate = 0;
    CMTime position = [_player currentTime];

    [_player replaceCurrentItemWithPlayerItem:newItem];

    [_player seekToTime:position];
    _player.rate = rate;
}

-(void)addObservers {
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, 600) queue:nil usingBlock:^(CMTime time) {
        [self onTimeupdate:time];
    }];

    [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"currentItem.status" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"currentItem.duration" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"currentItem.loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"currentItem.playbackBufferFull" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"currentItem.playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [_player addObserver:self forKeyPath:@"currentItem.error" options:NSKeyValueObservingOptionNew context:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying) name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];

    [self observeValueForKeyPath:@"status" ofObject:self change:nil context:nil];
    [self observeValueForKeyPath:@"rate" ofObject:self change:nil context:nil];

    _ready = YES;
}

-(void)removeObservers {
    [_player removeTimeObserver:_timeObserver];

    [_player removeObserver:self forKeyPath:@"status"];
    [_player removeObserver:self forKeyPath:@"rate"];
    [_player removeObserver:self forKeyPath:@"currentItem.status"];
    [_player removeObserver:self forKeyPath:@"currentItem.duration"];
    [_player removeObserver:self forKeyPath:@"currentItem.loadedTimeRanges"];
    [_player removeObserver:self forKeyPath:@"currentItem.playbackBufferFull"];
    [_player removeObserver:self forKeyPath:@"currentItem.playbackBufferEmpty"];
    [_player removeObserver:self forKeyPath:@"currentItem.error"];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
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
    [self execute:@"on_ended"];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if (_player == nil) {
        [_LOG warn:@"no player found in observer!"];
    }

    if (keyPath == nil) {
        [_LOG warn:@"null keyPath"];
        return;
    }

    if ([keyPath isEqualToString:@"currentItem"]) {
        if (![[[_player currentItem] asset] isKindOfClass:[HolaCDNAsset class]]) {
            [_LOG warn:@"CurrentItem changed from outside, calling uninit"];
            [self uninit];
            return;
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
            [self execute:@"on_ready"];
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
    }
}

-(void)executeSeeking {
    [self setState:@"SEEKING"];
    [self execute:@"on_seeking" withValue:[self get_pos]];
}

-(JSValue*)getDelegate {
    JSValue* proxy = [_cdn.ctx objectForKeyedSubscript:@"hola_ios_proxy"];

    if ([proxy isUndefined]) {
        [_LOG warn:@"getDelegate: proxy is undefined"];
        return nil;
    }

    JSValue* delegate = [proxy objectForKeyedSubscript:@"delegate"];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* delegate = [self getDelegate];

        if (delegate == nil) {
            [_LOG err:[NSString stringWithFormat:@"Trying to execute js: '%@'; no delegate found!", method]];
            return;
        }

        JSValue* callback = [delegate objectForKeyedSubscript:method];
        if ([callback isUndefined]) {
            [_LOG warn:[NSString stringWithFormat:@"Trying to execute js: '%@'; no callback found!", method]];
            return;
        }

        if (value != nil) {
            JSValue* jsValue = [JSValue valueWithObject:value inContext:_cdn.ctx];
            [callback callWithArguments:[NSArray arrayWithObject:jsValue]];
        } else {
            [callback callWithArguments:[NSArray new]];
        }
    });
}

@end
