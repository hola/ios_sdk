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

-(instancetype)initWithURL:(NSURL*)url andCDN:(HolaCDN*)cdn {
    NSURL* cdnURL = [HolaCDNLoaderDelegate applyCDNScheme:url andType:HolaCDNSchemeFetch];

    self = [super initWithURL:cdnURL options:nil];
    if (self) {
        _log = [HolaCDNLog logWithModule:@"Asset"];

        _isAttached = NO;
        _attachTimeoutSet = NO;
        _attachTimeoutTriggered = NO;
        _keysToLoad = [NSMutableArray new];

        _loader = [[HolaCDNLoaderDelegate alloc] initWithCDN:cdn];

        [self.resourceLoader setDelegate:_loader queue:_loader.queue];
    }

    return self;
}

-(void)loadValuesAsynchronouslyForKeys:(NSArray<NSString *> *)keys completionHandler:(void (^)(void))handler {
    if (_isAttached || _attachTimeoutTriggered) {
        return [super loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
    }

    [_keysToLoad addObject:@{
        @"keys": keys,
        @"handler": handler
    }];

    if (_attachTimeoutSet) {
        return;
    }

    [_log debug:@"Timeout: set"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [_log debug:@"Timeout: skip"];
        [self skip];
    });

    _attachTimeoutSet = YES;
}

-(void)skip {
    if (_attachTimeoutTriggered) {
        [_log debug:@"Skip: already triggered"];
        return;
    }

    if (_isAttached) {
        [_log debug:@"Skip: already attached"];
        return;
    }

    [_log debug:@"Load asset without cdn"];

    _attachTimeoutTriggered = YES;
    [self loadPendingKeys];

    [self onDetached];
}

-(void)loadPendingKeys {
    for (NSDictionary* item in _keysToLoad) {
        NSArray* keys = item[@"keys"];
        id handler = item[@"handler"];

        [super loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
    }

    [_keysToLoad removeAllObjects];
}

-(void)onAttached {
    if (_attachTimeoutTriggered) {
        return;
    }

    [_log debug:@"Attached"];

    _isAttached = YES;
    [_loader attach];
    [self loadPendingKeys];
}

-(void)onDetached {
    [_log info:@"Detached"];

    [self skip];

    if (_isAttached) {
        _isAttached = NO;
        [_loader uninit];
    }
}

-(void)dealloc {
    [_log info:@"Dealloc"];
    [self onDetached];
}

@end
