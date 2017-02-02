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

}
@end

@implementation HolaCDN

static void * const kHolaCDNContext = (void*)&kHolaCDNContext;

NSString* domain = @"https://player.h-cdn.com";
NSString* webviewUrl = @"%@/webview?customer=%@";
NSString* basicJS = @"window.hola_cdn_sdk = {version:'%@'};window.hola_ios_proxy = {};";
NSString* loaderUrl = @"%@/loader_%@.js";

NSString* loaderFilename = @"hola_cdn_library.js";

NSString* hola_cdn = @"window.hola_cdn";

+(void)setLogLevel:(HolaCDNLogLevel)level {
    [HolaCDNLog setVerboseLevel:level];
}

+(void)setLogModules:(NSArray*)modules {
    [HolaCDNLog setVerboseModules:modules];
}

+(instancetype)cdnWithCustomer:(NSString*)customer usingZone:(NSString*)zone andMode:(NSString*)mode {
    return [[HolaCDN alloc] initWithCustomer:customer usingZone:zone andMode:mode];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverPort = 8199;
        _player = nil;
        _ready = NO;
        _nextAction = HolaCDNActionNone;
        _inProgress = HolaCDNBusyNone;
        _loaderTimeout = 2; // seconds

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:UIApplicationWillTerminateNotification object:nil];

        _log = [HolaCDNLog logWithModule:nil];

        [GCDWebServer setLogLevel:5];
        _server = [[HolaCDNServer alloc] initWithCDN:self];

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
    switch (_inProgress) {
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

    _mode = [self convert_old_mode:mode];

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

    if (_nextAttach == nil) {
        _nextAction = HolaCDNActionNone;
    } else {
        _nextAction = HolaCDNActionAttach;
    }

    if (_customer == nil) {
        [_log err:@"Need to call `configWithCustomer:` method first!"];
        return;
    }

    if (_ready) {
        [_log info:@"already loaded"];
        [self didFinishLoading];
        return;
    }

    [_log info:@"Loading..."];

    _inProgress = HolaCDNBusyLoading;

    [_server start];

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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_loaderTimeout * NSEC_PER_SEC)), backgroundQueue, ^{
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
    if (![_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        return;
    }

    NSString* jsString = [NSString stringWithFormat:@"_get_bws().cdns.arr.forEach(function(cdn){ if (cdn.name=='%@') { cdn.enabled = %d; } })", name, enabled ? 1 : 0];
    [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, jsString]];
}

-(void)didFailWithError:(NSError*)error {
    _inProgress = HolaCDNBusyNone;

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

-(void)refreshJS {
    if (!_ready) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* ios_ready = [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"api.ios_ready"]];
        if (ios_ready.isUndefined) {
            [_log err:@"No ios_ready found: something is wrong with HolaCDN Library"];
            return;
        }

        [_log info:@"Wait for HolaCDN Library"];
        [ios_ready callWithArguments:[NSArray new]];
    });

    return;
}

-(void)didFinishLoading {
    if (_ctx == nil) {
        [_log err:@"Can't find JSContext on didFinishLoading"];
        return;
    }

    _inProgress = HolaCDNBusyNone;
    [_log info:@"Loaded"];

    _ready = YES;

    [self refreshJS];

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidLoaded:)]) {
            [_delegate cdnDidLoaded:self];
        }
    }

    [self processNextAction];
}

-(BOOL)processNextAction {
    switch (_nextAction) {
    case HolaCDNActionNone:
        return NO;
    case HolaCDNActionLoad:
        [_log debug:@"next action call: load"];
        [self load:nil];
        break;
    case HolaCDNActionAttach:
        if (_nextAttach) {
            [_log debug:@"next action call: attach"];
            [self attach:_nextAttach];
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

// player creation methods

-(BOOL)canMakePlayer {
    if (_player != nil) {
        [_log warn:@"HolaCDN already attached, make `uninit` before attaching to a new player. Continue without HolaCDN."];
        return NO;
    }

    return YES;
}

-(AVPlayerItem*)playerItemWithURL:(NSURL*)url {
    return [[HolaCDNPlayerItem alloc] initWithURL:url andCDN:self];
}

-(AVPlayerItem*)playerItemFromItem:(AVPlayerItem*)item {
    if ([item isKindOfClass:[HolaCDNPlayerItem class]]) {
        return item;
    }

    AVURLAsset* asset = (AVURLAsset*)item.asset;

    if (![asset isKindOfClass:[AVURLAsset class]]) {
        [_log err:@"AVPlayerItem must be initialized with AVURLAsset or NSURL!"];
        return item;
    }

    return [self playerItemWithURL:[asset URL]];
}

// AVPlayer methods

-(AVPlayer*)playerWithPlayerItem:(AVPlayerItem*)playerItem {
    AVPlayer* player = [self makePlayerWithPlayerItem:playerItem];
    return player;
}

-(AVPlayer*)playerWithURL:(NSURL*)url {
    AVPlayerItem* item = [self playerItemWithURL:url];
    return [self playerWithPlayerItem:item];
}

-(AVPlayer*)makePlayerWithPlayerItem:(AVPlayerItem*)playerItem {
    AVPlayerItem* item = [self playerItemFromItem:playerItem];
    return [AVPlayer playerWithPlayerItem:item];
}

// AVQueuePlayer methods

-(AVQueuePlayer*)queuePlayerWithURL:(NSURL*)url {
    AVPlayerItem* item = [self playerItemWithURL:url];
    return [self queuePlayerWithItems:@[item]];
}

-(AVQueuePlayer*)queuePlayerWithPlayerItem:(AVPlayerItem*)playerItem {
    AVURLAsset* asset = (AVURLAsset*)playerItem.asset;
    return [self queuePlayerWithURL:asset.URL];
}

-(AVQueuePlayer*)queuePlayerWithItems:(NSArray<AVPlayerItem*>*)items {
    AVQueuePlayer* player = [self makeQueuePlayerWithItems:items];
    return player;
}

-(AVQueuePlayer*)makeQueuePlayerWithItems:(NSArray<AVPlayerItem*>*)items {
    NSMutableArray<AVPlayerItem*>* cdnItems = [NSMutableArray new];

    for (AVPlayerItem* item in items) {
        [cdnItems addObject:[self playerItemFromItem:item]];
    }

    return [AVQueuePlayer queuePlayerWithItems:cdnItems];
}

// Wrap player
-(AVPlayer*)wrapPlayer:(AVPlayer*)player {
    AVPlayerItem* item = player.currentItem;

    if ([item isKindOfClass:[HolaCDNPlayerItem class]]) {
        return player;
    }

    return [self makePlayerWithPlayerItem:player.currentItem];
}

-(AVQueuePlayer*)wrapQueuePlayer:(AVQueuePlayer*)player {
    AVPlayerItem* item = player.currentItem;

    if ([item isKindOfClass:[HolaCDNPlayerItem class]]) {
        return player;
    }

    return [self makeQueuePlayerWithItems:[player items]];
}

// HolaCDN methods
-(AVPlayer*)attach:(AVPlayer*)player {
    if (_player != nil) {
        [_log warn:@"HolaCDN is already attached to a different player, detaching..."];
        [self detach];
    }

    [_log info:@"Attach"];

    if ([player isKindOfClass:[AVQueuePlayer class]]) {
       _player = (AVPlayer*)[self wrapQueuePlayer:player];
    } else {
        _player = [self wrapPlayer:player];
    }

    [self attachItem:_player.currentItem];

    __weak HolaCDN* cdn = self;
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, 600) queue:nil usingBlock:^(CMTime time) {
        HolaCDNPlayerItem* item = [cdn currentItem];
        if (item == nil) {
            return;
        }

        [item onTimeupdate:time];
    }];

    [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionPrior context:kHolaCDNContext];
    [_player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:kHolaCDNContext];
    
    return _player;
}

-(void)detach {
    if (_player == nil) {
        [_log warn:@"HolaCDN is not attached to any player"];
        return;
    }

    [_log info:@"Detach"];
    if (_timeObserver != nil) {
        [_player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    [_player removeObserver:self forKeyPath:@"currentItem" context:kHolaCDNContext];
    [_player removeObserver:self forKeyPath:@"rate" context:kHolaCDNContext];
    [self detachItem];
    _player = nil;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString*,id> *)change context:(void *)context {
    if (context != kHolaCDNContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if (_player == nil || _player.currentItem == nil) {
        return;
    }

    BOOL isBefore = [change objectForKey:NSKeyValueChangeOldKey] != [NSNull null];
    BOOL isAfter = [change objectForKey:NSKeyValueChangeNewKey] != [NSNull null];
    BOOL sameItem = [change objectForKey:NSKeyValueChangeOldKey] == [change objectForKey:NSKeyValueChangeNewKey];

    if ([keyPath isEqualToString:@"currentItem"]) {
        if (isBefore && !sameItem) {
            [_log debug:@"detach item"];
            [self detachItem];
            if (isAfter) {
                [_log debug:@"Going to attach the same item!"];
            }
        }

        if (isAfter && !sameItem) {
            if (isBefore) {
                [_log debug:@"The same item, was detached!"];
            }

            [_log debug:@"attach item"];
            [self attachItem:[change objectForKey:NSKeyValueChangeNewKey]];
        }

        return;
    }

    HolaCDNPlayerItem* item = [self currentItem];
    if (item == nil || !isAfter) {
        return;
    }

    if ([keyPath isEqualToString:@"rate"]) {
        if (_player.rate == 0) {
            [item onPause:_player.rate];
        } else {
            [item onPlay:_player.rate];
        }
        return;
    }

    if ([keyPath isEqualToString:@"status"]) {
        switch (_player.status) {
        case AVPlayerStatusReadyToPlay:
            break;
        case AVPlayerStatusFailed:
            [item onPlayerError];
            break;
        case AVPlayerStatusUnknown:
            [item onIdle];
            break;
        }
        return;
    }
}

-(HolaCDNPlayerItem*)currentItem {
    if ([_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        return (HolaCDNPlayerItem*)_player.currentItem;
    }

    return nil;
}

-(void)detachItem {
    HolaCDNPlayerItem* currentItem = [self currentItem];
    if (currentItem != nil) {
        [currentItem detach];
    }
}

-(void)attachItem:(AVPlayerItem*)item {
    if ([item isKindOfClass:[HolaCDNPlayerItem class]]) {
        [(HolaCDNPlayerItem*)item attach:_player];
    }
}


-(void)onAttached {
    if (![_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        return;
    }
    _inProgress = HolaCDNBusyNone;

    [_log info:@"Attached"];

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidAttached:)]) {
            [_log debug:@"delegate cdnDidAttached"];
            [_delegate cdnDidAttached:self];
        }
    }

    [self processNextAction];
}

-(void)onDetached {
    if (![_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        return;
    }

    if (_inProgress == HolaCDNBusyDetaching) {
        _player = nil;
    }
    _inProgress = HolaCDNBusyNone;

    [_log info:@"onDetached"];

    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidDetached:)]) {
            [_delegate cdnDidDetached:self];
        }
    }

    if (_nextAttach != nil) {
        _nextAction = HolaCDNActionAttach;
    }
    [self processNextAction];
}

-(void)uninit {
    if ([self isBusy]) {
        if (_nextAction != HolaCDNActionAttach) {
            _nextAttach = nil;
        }
        [_log warn:@"Will perform uninit when ready"];
        _nextAction = HolaCDNActionUninit;
        return;
    }

    if (![_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        [_log err:@"HolaCDN not attached!"];
        return;
    }

    HolaCDNPlayerItem* item = [self currentItem];
    if (item != nil) {
        [item detach];
    }

    [_log info:@"Uninit..."];

    _nextAction = HolaCDNActionNone;
    _inProgress = HolaCDNBusyDetaching;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
}

-(void)unload {
    if ([self isBusy] || !_ready) {
        if (_nextAction != HolaCDNActionAttach) {
            _nextAttach = nil;
        }
        [_log warn:@"Will perform unload when ready"];
        _nextAction = HolaCDNActionUnload;
        return;
    }

    [_log info:@"Unload..."];

    _nextAction = HolaCDNActionNone;

    [_server stop];
    [self uninit];
    _ctx = nil;
    _server = nil;
    _ready = NO;
}

-(void)dealloc {
    [_log info:@"Dealloc"];
    [self unload];
}

-(void)appWillTerminate {
    [self unload];
}

-(void)get_stats:(void (^)(NSDictionary*))completionBlock {
    if (![_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        completionBlock(nil);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* stats = [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"get_stats({silent: true})"]];

        completionBlock([stats toDictionary]);
    });
}

// XXX alexeym: backward compatibility, remove someday
-(NSString*)convert_old_mode:(NSString*)mode {
    [_log debug:mode];
    
    if ([mode isEqual:@"cdn"]) {
        [_log warn:@"Please use \"hola_cdn\" instead of \"cdn\"!"];
        return @"hola_cdn";
    }

    if ([mode isEqual:@"stats"]) {
        [_log warn:@"Please use \"origin_cdn\" instead of \"stats\"!"];
        return @"origin_cdn";
    }

    return mode;
}

-(void)get_mode:(void (^)(NSString*))completionBlock {
    HolaCDNPlayerItem* item = nil;
    if ([_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        item = (HolaCDNPlayerItem*)_player.currentItem;
    }

    if (item == nil || _ctx == nil) {
        completionBlock(_ready || _ctx == nil ? @"detached" : @"loading");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [_log debug:@"get mode from JS"];
        JSValue* mode = [[self getContext] evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"get_mode()"]];
        NSString* mode_s = [self convert_old_mode:[mode toString]];
        completionBlock(mode_s);
    });
}

-(void)get_timeline:(void (^)(NSDictionary*))completionBlock  {
    if (![_player.currentItem isKindOfClass:[HolaCDNPlayerItem class]]) {
        completionBlock(nil);
        return;
    }

    HolaCDNPlayerItem* item = (HolaCDNPlayerItem*)_player.currentItem;

    NSString* timelineString = @"window.cdn_graph.timeline";

    dispatch_async(dispatch_get_main_queue(), ^{
        JSValue* timeline = [[self getContext] evaluateScript:[NSString stringWithFormat:@"window.cdn_graph && %1$@ ? {cdns: %1$@.cdns, requests: %1$@.requests} : undefined", timelineString]];

        if (timeline.isUndefined) {
            completionBlock(nil);
            return;
        }

        NSMutableDictionary* result = [[timeline toDictionary] mutableCopy];
        [result setObject:[item.proxy get_duration] forKey:@"duration"];

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
