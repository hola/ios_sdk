//
//  hola_cdn_player_item.m
//  hola-cdn-sdk
//
//  Created by alexeym on 01/12/2016.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_player_item.h"

@implementation HolaCDNPlayerItem

static void * const kHolaCDNProxyContext = (void*)&kHolaCDNProxyContext;

-(instancetype)initWithURL:(NSURL*)URL andCDN:(HolaCDN*)cdn {
    HolaCDNAsset* asset = [[HolaCDNAsset alloc] initWithURL:URL andCDN:cdn];

    self = [super initWithAsset:asset];

    if (self) {
        _log = [HolaCDNLog logWithModule:@"Item"];
        _cdn = cdn;
        _rate = 0;

        [self initHolaItem];
    }

    return self;
}

-(void)initHolaItem {
    [_log info:@"Init"];

    _proxy = [[HolaCDNPlayerProxy alloc] initWithItem:self andCDN:_cdn];
    [[_cdn ctx][@"hola_ios_proxy"] setObject:_proxy forKeyedSubscript:[_proxy proxy_id]];
    
    HolaCDNAsset* asset = (HolaCDNAsset*)[self asset];
    [asset.loader setProxy:_proxy];

    [self addObservers];

    [_cdn refreshJS];
}

-(void)attach:(AVPlayer *)player {
    [_log info:@"Attach"];
    _player = player;
    if (_attached) {
        [_cdn onAttached];
    }
}

-(void)addObservers {
    [_log debug:@"Add observers"];
    _registered = YES;

    [self addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [self addObserver:self forKeyPath:@"duration" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [self addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [self addObserver:self forKeyPath:@"playbackBufferFull" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [self addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];
    [self addObserver:self forKeyPath:@"error" options:NSKeyValueObservingOptionNew context:kHolaCDNProxyContext];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying) name:AVPlayerItemDidPlayToEndTimeNotification object:self];
}

-(void)removeObservers {
    if (!_registered) {
        [_log debug:@"Observers not registered"];
        return;
    }

    [_log debug:[NSString stringWithFormat:@"Remove observers: %p", self]];
    _registered = NO;

    [self removeObserver:self forKeyPath:@"status" context:kHolaCDNProxyContext];
    [self removeObserver:self forKeyPath:@"duration" context:kHolaCDNProxyContext];
    [self removeObserver:self forKeyPath:@"loadedTimeRanges" context:kHolaCDNProxyContext];
    [self removeObserver:self forKeyPath:@"playbackBufferFull" context:kHolaCDNProxyContext];
    [self removeObserver:self forKeyPath:@"playbackBufferEmpty" context:kHolaCDNProxyContext];
    [self removeObserver:self forKeyPath:@"error" context:kHolaCDNProxyContext];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if (context != kHolaCDNProxyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if (_proxy == nil) {
        [_log warn:@"No proxy found"];
        return;
    }

    if (keyPath == nil) {
        [_log warn:@"null keyPath"];
        return;
    }

    if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        // on data loaded
        return;
    }

    if ([keyPath isEqualToString:@"status"]) {
        if ([self status] == AVPlayerItemStatusReadyToPlay) {
            if (_rate == 0) {
                [_proxy onSeeked];
            }
        } else if ([self status] == AVPlayerItemStatusFailed) {
            [_proxy onItemError];
        }

        return;
    }

    if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
        if (_rate == 0) {
            [_proxy onSeeking];
        }

        return;
    }

    if ([keyPath isEqualToString:@"error"]) {
        [_log err:[NSString stringWithFormat:@"currentItem.error: %@", change]];

        AVPlayerItemErrorLog* log = [self errorLog];
        if (log != nil) {
            AVPlayerItemErrorLogEvent* event = [log events].firstObject;
            if (event != nil) {
                NSLog(@"%ld: %@, %@", (long)event.errorStatusCode, event.errorDomain, event.errorComment);
            }
        }

        [_proxy uninit];
        return;
    }

    if ([keyPath isEqualToString:@"duration"]) {
        [_proxy onDuration:[self duration]];
        return;
    }
}


-(void)detach {
    [_log info:@"Detach"];
    _player = nil;
}

-(void)dealloc {
    [_log info:[NSString stringWithFormat:@"Dealloc: %p", self]];
    [self removeObservers];
    [_proxy uninit];
    [[_cdn ctx][@"hola_ios_proxy"] setObject:nil forKeyedSubscript:_proxy.proxy_id];
    [_cdn.ctx evaluateScript:[NSString stringWithFormat:@"delete window.hola_ios_proxy['%@']", _proxy.proxy_id]];
}

-(void)onPlay:(float)rate {
    _rate = rate;
    [_proxy onPlay];
}

-(void)onPause:(float)rate {
    _rate = rate;
    [_proxy onPause];
}

-(void)onIdle {
    [_proxy onIdle];
}

-(void)itemDidFinishPlaying {
    [_proxy onEnded];
}

-(void)onTimeupdate:(CMTime)time {
    [_proxy onTimeupdate:time];
}

-(void)onPlayerError {
    [_proxy onPlayerError];
}

-(void)onAttached {
    [_log debug:@"Attached"];
    _attached = YES;
    if (_player) {
        [_cdn onAttached];
    }
}

-(void)onDetached {
    [_log debug:@"Detached"];
    if (_attached) {
        _attached = NO;

        if (_player) {
            [_cdn onDetached];
        }
    }
}

@end
