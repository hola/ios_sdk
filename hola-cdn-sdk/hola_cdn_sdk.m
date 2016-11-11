//
//  hola_cdn_sdk.m
//  hola-cdn-sdk
//
//  Created by alexeym on 27/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_sdk.h"
#import "hola_log.h"
#import "XMLHttpRequest.h"
#import "window_timers.h"

@interface HolaCDN()
{
NSString* _zone;
NSString* _mode;

AVPlayer* _player;

}
@end

@implementation HolaCDN

static HolaCDNLog* _log;
BOOL ready;
HolaCDNBusy inProgress;
HolaCDNAction nextAction;

AVPlayer* nextAttach;

NSString* domain = @"https://player.h-cdn.com";
NSString* webviewUrl = @"%@/webview?customer=%@";
NSString* basicJS = @"window.hola_cdn_sdk = {version:'%@'};";
NSString* loaderUrl = @"%@/loader_%@.js";

NSString* hola_cdn = @"window.hola_cdn";

+(void)setLogLevel:(HolaCDNLogLevel)level {
    [HolaCDNLog setVerboseLevel:level];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverPort = 8199;
        _playerProxy = nil;
        ready = NO;
        nextAction = HolaCDNActionNone;
        inProgress = HolaCDNBusyNone;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:UIApplicationWillTerminateNotification object:nil];

        _log = [HolaCDNLog new];
        [GCDWebServer setLogLevel:5];
    }

    return self;
}

-(BOOL)isBusy {
    NSString* msg;
    switch (inProgress) {
    case HolaCDNBusyNone:
        return NO;
    case HolaCDNBusyLoading:
        msg = @"loading";
    break;
    case HolaCDNBusyAttaching:
        msg = @"attaching";
    break;
    case HolaCDNBusyDetaching:
        msg = @"detaching";
    break;
    case HolaCDNBusyUnloading:
        msg = @"unloading";
    break;
    }

    [_log warn:[NSString stringWithFormat:@"HolaCDN is busy with %@", msg]];
    return YES;
}

-(void)configWithCustomer:(NSString*)customer usingZone:(NSString*)zone andMode:(NSString*)mode {
    if ([self isBusy]) {
        return;
    }
    _customer = customer;
    _zone = zone;
    _mode = mode;

    if (ready) {
        [self unload];
    }
}

-(BOOL)load:(NSError**)error {
    if ([self isBusy]) {
        [_log warn:@"Can't perform load, CDN is busy"];
        nextAction = HolaCDNActionLoad;
        return NO;
    }

    if (nextAttach == nil) {
        nextAction = HolaCDNActionNone;
    } else {
        nextAction = HolaCDNActionAttach;
    }

    if (_customer == nil) {
        *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:1 userInfo:nil];
        return NO;
    }

    if (ready) {
        [_log info:@"already loaded"];
        [self didFinishLoading];
        return YES;
    }

    [_log info:@"load"];

    inProgress = HolaCDNBusyLoading;

    _ctx = [JSContext new];
    XMLHttpRequest* xmlHttpRequest = [XMLHttpRequest new];
    [xmlHttpRequest extend:_ctx];

    WTWindowTimers *timers = [WTWindowTimers new];
    [timers extend:_ctx];

    __weak typeof(self) weakSelf = self;
    _ctx.exceptionHandler = ^(JSContext* context, JSValue* exception) {
        [weakSelf onException:context value:exception];
    };

    NSBundle* bundle = [NSBundle bundleForClass:NSClassFromString(@"HolaCDN")];
    NSString* bundlePath = [bundle pathForResource:@"HolaCDNAssets" ofType:@"bundle"];

    NSBundle* assets;
    if (bundlePath == nil) {
        assets = bundle;
    } else {
        assets = [NSBundle bundleWithPath:bundlePath];
    }

    NSString* locationJS = [NSString stringWithFormat:@"_hola_location = '%@'", [self makeWebviewUrl]];
    [_ctx evaluateScript:locationJS withSourceURL:[NSURL URLWithString:@"location.js"]];

    // assets order evaluating is important
    NSArray<NSString*>* assetList = @[@"proxy", @"dom", @"localStorage"];
    for (NSString* name in assetList) {
        NSString* jsPath = [assets pathForResource:name ofType:@"js"];
        if (jsPath == nil) {
            *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:4 userInfo:@{
                @"description": @"asset_not_found",
                @"asset": name
            }];
            return NO;
        }

        NSError* err = nil;
        NSString* jsCode = [NSString stringWithContentsOfFile:jsPath encoding:NSUTF8StringEncoding error:&err];

        if (err != nil) {
            *error = err;
            return NO;
        }

        [_ctx evaluateScript:jsCode withSourceURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@.js", name]]];
    }

    NSString* version = bundle.infoDictionary[@"CFBundleShortVersionString"];
    NSString* basic = [NSString stringWithFormat:basicJS, version];
    [_ctx evaluateScript:basic withSourceURL:[NSURL URLWithString:@"basic.js"]];

    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:loaderUrl, domain, _customer]];

    dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(backgroundQueue, ^{
        NSError* err = nil;
        NSString* loaderJS = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
        if (err != nil) {
            [self didFailWithError:err];
            return;
        }

        [_ctx evaluateScript:loaderJS withSourceURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didFinishLoading];
        });
    });

    return YES;
}

-(JSContext*)getContext {
    JSContext* current = [JSContext currentContext];
    if (current != nil) {
        return current;
    }

    return _ctx;
}

-(void)set_cdn_enabled:(NSString*)name enabled:(BOOL)enabled {
    if (_playerProxy == nil) {
        return;
    }

    NSString* jsString = [NSString stringWithFormat:@"_get_bws().cdns.arr.forEach(function(cdn){ if (cdn.name=='%@') { cdn.enabled = %d; } })", name, enabled ? 1 : 0];
    [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, jsString]];
}

-(void)didFailWithError:(NSError*)error {
    inProgress = HolaCDNBusyNone;

    if (error != nil && [error code] != NSURLErrorCancelled) {
        [_log err:[NSString stringWithFormat:@"loading fail: %@", error]];

        if (_delegate != nil) {
            if ([_delegate respondsToSelector:@selector(cdnExceptionOccured:withError:)]) {
                [_delegate cdnExceptionOccured:self withError:error];
            }
        }

        [self unload];
    }
}

-(void)didFinishLoading {
    if (_ctx == nil) {
        [_log err:@"Can't find JSContext on didFinishLoading"];
        return;
    }

    inProgress = HolaCDNBusyNone;
    [_log debug:@"page loaded!"];

    ready = YES;
    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidLoaded:)]) {
            [_delegate cdnDidLoaded:self];
        }
    }

    [self processNextAction];
}

-(BOOL)processNextAction {
    switch (nextAction) {
    case HolaCDNActionNone:
        return NO;
    case HolaCDNActionLoad:
        [_log info:@"next action call: load"];
        [self load:nil];
        break;
    case HolaCDNActionAttach:
        if (nextAttach) {
            [_log info:@"next action call: attach"];
            [self attach:nextAttach];
        } else {
            [_log info:@"next action call: attach, no player found; do nothing"];
        }
        break;
    case HolaCDNActionUninit:
        [_log info:@"next action call: uninit"];
        [self uninit];
        break;
    case HolaCDNActionUnload:
        [_log info:@"next action call: unload"];
        [self unload];
        break;
    }

    return YES;
}

-(void)attach:(AVPlayer*)player {
    if (player == nil) {
        [_log err:@"Player can't be nil on attach"];
        return;
    }

    if ([self isBusy] || _playerProxy != nil) {
        [_log warn:@"CDN is busy or already attached!"];
        nextAttach = player;
        if (inProgress == HolaCDNActionAttach) {
            nextAction = HolaCDNActionUninit;
            return;
        }
        nextAction = HolaCDNActionAttach;
        return;
    }

    if (!ready) {
        [_log info:@"not ready on attach: perform load"];
        nextAttach = player;
        nextAction = HolaCDNActionLoad;
        [self processNextAction];
        return;
    }

    inProgress = HolaCDNBusyAttaching;

    _player = player;
    nextAttach = nil;
    nextAction = HolaCDNActionNone;

    [_log info:@"attach"];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_server != nil) {
            if ([_server isRunning]) {
                [_server stop];
            }
            [_server removeAllHandlers];
            _server = nil;
        }
        _server = [GCDWebServer new];
        
        dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_async(backgroundQueue, ^{
            _playerProxy = [[HolaCDNPlayerProxy alloc] initWithPlayer:_player andCDN:self];

            JSValue* ios_ready = [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"api.ios_ready"]];
            if (ios_ready.isUndefined) {
                [self didFailWithError:[NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:5 userInfo:@{@"description": @"No ios_ready: something is wrong with cdn js"}]];
                return;
            }

            [ios_ready callWithArguments:[NSArray new]];
        });
    });
}

-(void)onAttached {
    inProgress = HolaCDNBusyNone;

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidAttached:)]) {
            [_log debug:@"call cdnDidAttached"];
            [_delegate cdnDidAttached:self];
        }
    }

    [self processNextAction];
}

-(void)onDetached {
    inProgress = HolaCDNBusyNone;

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidDetached:)]) {
            [_delegate cdnDidDetached:self];
        }
    }

    if (nextAttach != nil) {
        nextAction = HolaCDNActionAttach;
    }
    [self processNextAction];
}

-(void)uninit {
    if ([self isBusy] || _playerProxy == nil) {
        if (nextAction != HolaCDNActionAttach) {
            nextAttach = nil;
        }
        nextAction = HolaCDNActionUninit;
        return;
    }

    [_log info:@"cdn uninit"];

    nextAction = HolaCDNActionNone;
    inProgress = HolaCDNBusyDetaching;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];

    [_playerProxy uninit];
    _playerProxy = nil;
    _player = nil;
}

-(void)unload {
    if ([self isBusy] || !ready) {
        if (nextAction != HolaCDNActionAttach) {
            nextAttach = nil;
        }
        nextAction = HolaCDNActionUnload;
        return;
    }

    [_log info:@"cdn unload"];

    nextAction = HolaCDNActionNone;
    
    [self uninit];
    _ctx = nil;
    ready = NO;
}

-(void)appWillTerminate {
    [self unload];
}

-(void)get_stats:(void (^)(NSDictionary*))completionBlock {
    if (_playerProxy == nil) {
        completionBlock(nil);
        return;
    }


    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* stats = [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"get_stats({silent: true})"]];

        completionBlock([stats toDictionary]);
    });
}

-(void)get_mode:(void (^)(NSString*))completionBlock {
    if (_playerProxy == nil || _ctx == nil) {
        completionBlock(ready || _ctx == nil ? @"detached" : @"loading");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* mode = [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"get_mode()"]];
        completionBlock([mode toString]);
    });
}

-(void)get_timeline:(void (^)(NSDictionary*))completionBlock  {
    if (_playerProxy == nil) {
        completionBlock(nil);
        return;
    }

    NSString* timelineString = @"window.cdn_graph.timeline";

    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* timeline = [[self getContext] evaluateScript:[NSString stringWithFormat:@"window.cdn_graph && %1$@ ? {cdns: %1$@.cdns, requests: %1$@.requests} : undefined", timelineString]];

        if (timeline.isUndefined) {
            completionBlock(nil);
            return;
        }

        NSMutableDictionary* result = [[timeline toDictionary] mutableCopy];
        [result setObject:[_playerProxy get_duration] forKey:@"duration"];

        completionBlock(result);
    });
}

-(void)onException:(JSContext*)context value:(JSValue*)value {
    [_log err:[NSString stringWithFormat:@"JS Exception: %@", value]];

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnExceptionOccured:withError:)]) {
            [_delegate cdnExceptionOccured:self withError:[NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:3 userInfo:@{@"js": value}]];
        }
    }
}

-(NSURL*)makeWebviewUrl {
    NSMutableString* url = [NSMutableString stringWithFormat:webviewUrl, domain, _customer];

    if (_zone != nil) {
        [url appendFormat:@"&hola_zone=%@", _zone];
    }
    if (_mode != nil) {
        [url appendFormat:@"&hola_mode=%@", _mode];
    }

    if (_graphEnabled) {
        [url appendString:@"&hola_graph=1"];
    }

    return [NSURL URLWithString:url];
}

@end
