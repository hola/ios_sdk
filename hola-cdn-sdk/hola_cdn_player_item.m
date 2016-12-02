//
//  hola_cdn_player_item.m
//  hola-cdn-sdk
//
//  Created by alexeym on 01/12/2016.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_player_item.h"

@implementation HolaCDNPlayerItem

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

-(NSString *)description {
    return [NSString stringWithFormat:@"%@:%@", [_log module], [_log instance]];
}

-(void)initHolaItem {
    [_log info:@"Init"];

    _proxy = [[HolaCDNPlayerProxy alloc] initWithItem:self andCDN:_cdn];
    HolaCDNAsset* asset = [self asset];
    [asset.loader setProxy:_proxy];

    [_cdn refreshJS];
}

-(void)attach:(AVPlayer *)player {
    [_log info:@"Attach"];
    _player = player;
    if (_attached) {
        [_cdn onAttached];
    }
}

-(void)detach {
    [_log info:@"Detach"];
    _player = nil;
}

-(void)dealloc {
    [_log info:@"Dealloc"];
    [_proxy uninit];
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
