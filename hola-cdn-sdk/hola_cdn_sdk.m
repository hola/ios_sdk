//
//  hola_cdn_sdk.m
//  hola-cdn-sdk
//
//  Created by alexeym on 27/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_sdk.h"
#import "hola_log.h"

@interface HolaCDN()
{
NSString* _zone;
NSString* _mode;

UIWebView* webview;

AVPlayer* _player;

}
@end

@implementation HolaCDN

static HolaCDNLog* _log;
BOOL ready = NO;

NSString* domain = @"https://player.h-cdn.com";
NSString* webviewUrl = @"%@/webview?customer=%@";
NSString* webviewHTML = @"<script>window.hola_cdn_sdk = {version:'%@'}</script><script src=\"%@/loader_%@.js\"></script>";

NSString* hola_cdn = @"window.hola_cdn";

+(void)setLogLevel:(HolaCDNLogLevel)level {
    [HolaCDNLog setVerboseLevel:level];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverPort = 8199;
        webview = [UIWebView new];
        webview.delegate = self;
        _playerProxy = nil;

        _log = [HolaCDNLog new];
    }

    return self;
}

-(void)configWithCustomer:(NSString*)customer usingZone:(NSString*)zone andMode:(NSString*)mode {
    _customer = customer;
    _zone = zone;
    _mode = mode;

    if (ready) {
        [self unload];
    }
}

-(BOOL)load:(NSError**)error {
    if (_customer == nil) {
        *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:1 userInfo:nil];
        return NO;
    }

    [_log info:@"load"];
    if (ready) {
        if (_delegate != nil) {
            if ([_delegate respondsToSelector:@selector(cdnDidLoaded:)]) {
                [_delegate cdnDidLoaded:self];
            }
        }
        return YES;
    }

    JSContext* ctx = [webview valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
    if (ctx == nil) {
        [_log err:@"No context on initContext"];
        return NO;
    }

    ctx.exceptionHandler = ^(JSContext* context, JSValue* exception) {
        [self onException:context value:exception];
    };

    _ctx = ctx;

    NSBundle* bundle = [NSBundle bundleForClass:NSClassFromString(@"HolaCDN")];
    NSString* version = bundle.infoDictionary[@"CFBundleShortVersionString"];
    NSString* htmlString = [NSString stringWithFormat:webviewHTML, version, domain, _customer];

    [webview loadHTMLString:htmlString baseURL:[self makeWebviewUrl]];

    return YES;
}

-(void)set_cdn_enabled:(NSString*)name enabled:(BOOL)enabled {
    if (_playerProxy == nil) {
        return;
    }

    NSString* jsString = [NSString stringWithFormat:@"_get_bws().cdns.arr.forEach(function(cdn){ if (cdn.name=='%@') { cdn.enabled = %d; } })", name, enabled ? 1 : 0];
    [_ctx evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, jsString]];
}

-(void)webViewDidStartLoad:(UIWebView *)webView {
    [_log debug:@"page loading..."];
}

-(void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (error != nil && [error code] != NSURLErrorCancelled) {
        [_log err:[NSString stringWithFormat:@"webview: %@", error]];

        if (_delegate != nil) {
            if ([_delegate respondsToSelector:@selector(cdnExceptionOccured:withError:)]) {
                [_delegate cdnExceptionOccured:self withError:[NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:2 userInfo:nil]];
            }
        }

        [self unload];
    }
}

-(void)webViewDidFinishLoad:(UIWebView *)webView {
    if (_ctx == nil) {
        return;
    }

    [_log debug:@"page loaded!"];

    ready = YES;
    if (_delegate != nil) {
        if ([_delegate respondsToSelector:@selector(cdnDidLoaded:)]) {
            [_delegate cdnDidLoaded:self];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (ready && _player != nil && _playerProxy == nil) {
            dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
            dispatch_async(backgroundQueue, ^{
                [_log info:@"player autoinit"];
                [self attach:_player];
            });
        }
    });
}

-(void)attach:(AVPlayer*)player {
    if (_playerProxy != nil) {
        [_log warn:@"CDN is already attached!"];
        return;
    }

    _player = player;

    if (!ready) {
        [_log info:@"not ready on attach: wait for player autoinit"];
        return;
    }

    [_log info:@"attach"];

    _playerProxy = [[HolaCDNPlayerProxy alloc] initWithPlayer:_player andCDN:self];

    JSValue* ios_ready = [_ctx evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"api.ios_ready"]];
    if (ios_ready.isUndefined) {
        _playerProxy = nil;
        [_log err:@"No ios_ready: something is wrong with cdn js"];
        return;
    }

    [ios_ready callWithArguments:[NSArray new]];
}

-(void)uninit {
    [_log info:@"cdn uninit"];

    [_playerProxy uninit];
    _playerProxy = nil;
    _player = nil;
}

-(void)unload {
    [self uninit];

    _ctx = nil;

    ready = NO;
}

-(NSDictionary*)get_stats {
    if (_playerProxy == nil) {
        return nil;
    }

    @try {
        JSValue* stats = [_ctx evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"get_stats({silent: true})"]];
        return [stats toDictionary];
    } @catch (NSException *exception) {
        [_log warn:[NSString stringWithFormat:@"get_stats err: %@", exception]];
        return nil;
    }
}

-(NSString*)get_mode {
    if (_playerProxy == nil) {
        return ready ? @"detached" : @"loading";
    }

    @try {
        JSValue* mode = [_ctx evaluateScript:[NSString stringWithFormat:@"%@.%@", hola_cdn, @"get_mode()"]];
        return [mode toString];
    } @catch (NSException *exception) {
        [_log warn:[NSString stringWithFormat:@"get_mode err: %@", exception]];
        return nil;
    }
}

-(NSDictionary*)get_timeline {
    if (_playerProxy == nil || !_graphEnabled) {
        return nil;
    }

    NSString* timelineString = @"window.cdn_graph.timeline";

    @try {
        JSValue* timeline = [_ctx evaluateScript:[NSString stringWithFormat:@"window.cdn_graph && %1$@ ? {cdns: %1$@.cdns, requests: %1$@.requests} : undefined", timelineString]];

        if (timeline.isUndefined) {
            return nil;
        }

        NSMutableDictionary* result = [[timeline toDictionary] mutableCopy];
        [result setObject:[_playerProxy get_duration] forKey:@"duration"];

        return result;
    } @catch (NSException *exception) {
        [_log warn:[NSString stringWithFormat:@"get_timeline err: %@", exception]];
        return nil;
    }
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
