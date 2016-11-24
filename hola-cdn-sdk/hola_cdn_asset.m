//
//  hola_cdn_asset.m
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_asset.h"
#import "hola_log.h"

@implementation HolaCDNAsset

static HolaCDNLog* _log;

-(instancetype)initWithURL:(NSURL*)url andCDN:(HolaCDN*)cdn {
    NSURL* cdnURL = [HolaCDNLoaderDelegate applyCDNScheme:url andType:HolaCDNSchemeFetch];

    self = [super initWithURL:cdnURL options:nil];
    if (self) {
        _log = [HolaCDNLog new];
        [_log setModule:@"asset"];

        _cdn = cdn;
        _isAttached = NO;
        _attachTimeoutSet = NO;
        _attachTimeoutTriggered = NO;
        _keysToLoad = [NSMutableArray new];

        [self.resourceLoader setDelegate:_cdn.loader queue:_cdn.loader.queue];
    }

    return self;
}

-(void)loadValuesAsynchronouslyForKeys:(NSArray<NSString *> *)keys completionHandler:(void (^)(void))handler {
    if (_isAttached || _attachTimeoutTriggered) {
        //[_log debug:[NSString stringWithFormat:@"Load values async for %@", keys]];
        return [super loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
    }

    //[_log debug:[NSString stringWithFormat:@"Save pending async keys: %@", keys]];

    [_keysToLoad addObject:@{
        @"keys": keys,
        @"handler": handler
    }];

    if (_attachTimeoutSet) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([_cdn loaderTimeout] * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (_isAttached) {
            [_log debug:@"Timeout: already attached"];
            return;
        }

        [_log debug:@"Load asset without cdn"];

        [self onDetached];

        _attachTimeoutTriggered = YES;
        [self loadPendingKeys];
    });

    _attachTimeoutSet = YES;
}

-(void)loadPendingKeys {
    for (NSDictionary* item in _keysToLoad) {
        NSArray* keys = item[@"keys"];
        id handler = item[@"handler"];

        //[_log debug:[NSString stringWithFormat:@"Load pending keys %@", keys]];
        [super loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
    }
}

-(void)onAttached {
    if (_attachTimeoutTriggered) {
        return;
    }

    [_log debug:@"Attached"];

    _isAttached = YES;
    [_cdn.loader attach];
    [self loadPendingKeys];
}

-(void)onDetached {
    [_log info:@"Detached"];
    if (_isAttached) {
        _isAttached = NO;
        [_cdn.loader uninit];
    }
}

-(void)dealloc {
    [_log debug:@"Dealloc"];
    [self onDetached];
}

@end
