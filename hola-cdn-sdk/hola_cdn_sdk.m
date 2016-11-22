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
double loaderTimeout = 1.0; // Timeout in sec before using saved HolaCDN library

NSString* loaderFilename = @"hola_cdn_library.js";

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
        [_log info:@"New HolaCDN instance created"];
    }

    return self;
}

-(instancetype)initWithCustomer:(NSString*)customer usingZone:(NSString*)zone andMode:(NSString*)mode {
    self = [self init];

    if (self) {
        [self configWithCustomer:customer usingZone:zone andMode:mode];
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
    if (_customer != nil) {
        [_log err:@"Create a new HolaCDN instance in case if you want to change customer or zone"];
        return;
    }

    if (customer == nil) {
        [_log err:@"Customer must not be nil"];
        return;
    }

    _customer = customer;
    _zone = zone;
    _mode = mode;

    [self load];
}

-(NSString*)getLoaderPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return [documentsDirectory stringByAppendingPathComponent:loaderFilename];
}

-(BOOL)load:(NSError**)error {
    return YES;
}

-(void)load {
    if ([self isBusy]) {
        [_log err:@"Can't perform load when busy!"];
        return;
    }

    if (nextAttach == nil) {
        nextAction = HolaCDNActionNone;
    } else {
        nextAction = HolaCDNActionAttach;
    }

    if (_customer == nil) {
        [_log err:@"Need to call `configWithCustomer:` method first!"];
        return;
    }

    if (ready) {
        [_log info:@"already loaded"];
        [self didFinishLoading];
        return;
    }

    [_log info:@"Loading..."];

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
            [_log err:[NSString stringWithFormat:@"Can't find library asset: %@.js! Please re-integrate HolaCDN library into your project", name]];
            return;
        }

        NSString* jsCode = [NSString stringWithContentsOfFile:jsPath encoding:NSUTF8StringEncoding error:NULL];

        [_ctx evaluateScript:jsCode withSourceURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@.js", name]]];
    }

    NSString* version = bundle.infoDictionary[@"CFBundleShortVersionString"];
    NSString* basic = [NSString stringWithFormat:basicJS, version];
    [_ctx evaluateScript:basic withSourceURL:[NSURL URLWithString:@"basic.js"]];

    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:loaderUrl, domain, _customer]];

    NSString* loaderPath = [self getLoaderPath];
    __block BOOL contextReady = NO;
    __block BOOL loaderFetched = NO;

    dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(backgroundQueue, ^{
        NSError* err = nil;
        NSString* loaderJS = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
        loaderFetched = YES;
        if (err != nil) {
            [_log warn:@"Can't fetch fresh HolaCDN library"];
            if (!contextReady) {
                [self didFailWithError:err];
            }
            return;
        }

        if (!contextReady) {
            [_log info:@"Use fresh-loaded HolaCDN library"];
            contextReady = YES;
            [_ctx evaluateScript:loaderJS withSourceURL:url];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self didFinishLoading];
            });
        }

        [loaderJS writeToFile:loaderPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (err == nil) {
            [_log debug:@"HolaCDN library updated"];
        } else {
            [_log warn:[NSString stringWithFormat:@"Can't save HolaCDN library! Error: %@", err]];
        }
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(loaderTimeout * NSEC_PER_SEC)), backgroundQueue, ^{
        if (contextReady) {
            [_log debug:@"Fresh version was already loaded, stop looking for a saved library"];
            return;
        }
        NSError* err = nil;
        NSString* loaderJSSaved = [NSString stringWithContentsOfFile:loaderPath encoding:NSUTF8StringEncoding error:&err];
        if (err == nil) {
            if (!contextReady) {
                [_log info:@"Use saved HolaCDN library"];
                contextReady = YES;
                [_ctx evaluateScript:loaderJSSaved withSourceURL:url];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self didFinishLoading];
                });
            } else {
                [_log debug:@"Saved library found, but fresh version was already loaded"];
            }
        } else {
            [_log debug:[NSString stringWithFormat:@"Can't read HolaCDN library from file: %@", err]];
            if (loaderFetched) {
                [_log debug:@"Remote load also failed!"];
                [self didFailWithError:err];
            }
        }
    });
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
        [_log err:[NSString stringWithFormat:@"Loading fail: %@", error]];

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
    [_log info:@"Loaded"];

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
        [_log debug:@"next action call: load"];
        [self load:nil];
        break;
    case HolaCDNActionAttach:
        if (nextAttach) {
            [_log debug:@"next action call: attach"];
            [self attach:nextAttach];
        } else {
            [_log debug:@"next action call: attach, no player found; do nothing"];
        }
        break;
    case HolaCDNActionUninit:
        [_log debug:@"next action call: uninit"];
        [self uninit];
        break;
    case HolaCDNActionUnload:
        [_log debug:@"next action call: unload"];
        [self unload];
        break;
    }

    return YES;
}

-(BOOL)canMakePlayer {
    if (_player != nil) {
        [_log warn:@"HolaCDN already attached, make `uninit` before attaching to a new player. Continue without HolaCDN."];
        return NO;
    }

    return YES;
}

-(AVPlayer*)attachToNewPlayer:(AVPlayer*)player {
    if ([self canMakePlayer]) {
        [self attach:player];
    }

    return player;
}

-(AVPlayer*)makeAVPlayerWithURL:(NSURL*)url {
    return [self attachToNewPlayer:[[AVPlayer alloc] initWithURL:url]];
}

-(AVPlayer*)makeAVPlayerWithPlayerItem:(AVPlayerItem*)playerItem {
    return [self attachToNewPlayer:[[AVPlayer alloc] initWithPlayerItem:playerItem]];
}

-(AVQueuePlayer*)makeAVQueuePlayerWithURL:(NSURL*)url {
    return [self attachToNewPlayer:[[AVQueuePlayer alloc] initWithURL:url]];
}

-(AVQueuePlayer*)makeAVQueuePlayerWithPlayerItem:(AVPlayerItem*)playerItem {
    return [self attachToNewPlayer:[[AVQueuePlayer alloc] initWithPlayerItem:playerItem]];
}

-(AVQueuePlayer*)makeAVQueuePlayerWithItems:(NSArray<AVPlayerItem*>*)items {
    return [self attachToNewPlayer:[[AVQueuePlayer alloc] initWithItems:items]];
}

-(void)attach:(AVPlayer*)player {
    if (player == nil) {
        [_log err:@"Player can't be nil on attach"];
        return;
    }

    if ([self isBusy]) {
        if (inProgress == HolaCDNBusyAttaching && nextAction != HolaCDNActionUninit) {
            [_log err:@"Call `uninit` before new attach!"];
            return;
        }
        [_log warn:@"Will make attach automatically when ready"];
        nextAttach = player;
        if (inProgress == HolaCDNBusyAttaching) {
            nextAction = HolaCDNActionUninit;
            return;
        }
        nextAction = HolaCDNActionAttach;
        return;
    }

    if (_playerProxy != nil) {
        [_log err:@"HolaCDN is already attached!"];
        return;
    }

    if (!ready) {
        [_log err:@"HolaCDN is not ready on attach!"];
        return;
    }

    inProgress = HolaCDNBusyAttaching;

    _player = player;
    nextAttach = nil;
    nextAction = HolaCDNActionNone;

    [_log info:@"Attach..."];

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
                [self didFailWithError:[NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:5 userInfo:@{@"description": @"No ios_ready found: something is wrong with HolaCDN Library"}]];
                return;
            }

            [_log info:@"Wait for HolaCDN Library"];
            [ios_ready callWithArguments:[NSArray new]];
        });
    });
}

-(void)onAttached {
    if (_playerProxy == nil) {
        return;
    }
    inProgress = HolaCDNBusyNone;

    [_log info:@"Attached"];

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidAttached:)]) {
            [_log debug:@"delegate cdnDidAttached"];
            [_delegate cdnDidAttached:self];
        }

        if ([_delegate respondsToSelector:@selector(cdnDidAttached:toPlayer:)]) {
            [_log debug:@"delegate cdnDidAttached:toPlayer:"];
            [_delegate cdnDidAttached:self toPlayer:_player];
        }
    }

    [self processNextAction];
}

-(void)onDetached {
    if (_playerProxy == nil) {
        return;
    }

    if (inProgress == HolaCDNBusyDetaching) {
        _playerProxy = nil;
        _player = nil;
    }
    inProgress = HolaCDNBusyNone;

    [_log info:@"Detached"];

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
    if ([self isBusy]) {
        if (nextAction != HolaCDNActionAttach) {
            nextAttach = nil;
        }
        [_log warn:@"Will perform uninit when ready"];
        nextAction = HolaCDNActionUninit;
        return;
    }

    if (_playerProxy == nil) {
        [_log err:@"HolaCDN not attached!"];
        return;
    }

    [_log info:@"Uninit..."];

    nextAction = HolaCDNActionNone;
    inProgress = HolaCDNBusyDetaching;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];

    [_playerProxy uninit];
}

-(void)unload {
    if ([self isBusy] || !ready) {
        if (nextAction != HolaCDNActionAttach) {
            nextAttach = nil;
        }
        [_log warn:@"Will perform unload when ready"];
        nextAction = HolaCDNActionUnload;
        return;
    }

    [_log info:@"Unload..."];

    nextAction = HolaCDNActionNone;
    
    [self uninit];
    _ctx = nil;
    ready = NO;
}

-(void)dealloc {
    [_log info:@"Dealloc"];
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
