//
//  hola_cdn_server.h
//  hola-cdn-sdk
//
//  Created by alexeym on 30/11/2016.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_server.h"

@implementation HolaCDNServer

static HolaCDNLog* _log;

-(instancetype)initWithCDN:(HolaCDN*)cdn {
    self = [super init];
    if (self) {
        _log = [HolaCDNLog new];
        [_log setModule:@"Server"];

        _loaders = [NSMutableDictionary new];

        _cdn = cdn;

        _server = [GCDWebServer new];
    }

    return self;
}

-(void)start {
    __weak typeof(self) weakSelf = self;
    [_server addDefaultHandlerForMethod:@"GET" requestClass:[GCDWebServerRequest self] asyncProcessBlock:^(__kindof GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {
        [weakSelf processRequest:request completionBlock:completionBlock];
    }];

    NSError* err = nil;
    [_server startWithOptions:@{
        GCDWebServerOption_BindToLocalhost: @YES,
        GCDWebServerOption_Port: [NSNumber numberWithInt:[_cdn serverPort]],
        GCDWebServerOption_BonjourName: @"HolaCDN"
    } error:&err];
}

-(void)stop {
    if ([_server isRunning]) {
        [_server stop];
    }
    [_server removeAllHandlers];
    _server = nil;
}

-(void)bindLoader:(HolaCDNLoaderDelegate *)loader {
    [_loaders setObject:loader forKey:loader.loaderUUID];
}

-(void)unbindLoader:(HolaCDNLoaderDelegate *)loader {
    [_loaders removeObjectForKey:loader.loaderUUID];
}

// internal methods

-(void)processRequest:(GCDWebServerRequest*)request completionBlock:(GCDWebServerCompletionBlock)completion {
    NSArray<NSString*>* path = [request.URL pathComponents];

    if (path == nil || [path count] != 3) {
        [_log err:[NSString stringWithFormat:@"Wrong path: %@", path]];
        completion([GCDWebServerDataResponse responseWithStatusCode:400]);
        return;
    }

    NSString* loaderUUID = path[1];
    HolaCDNLoaderDelegate* loader = _loaders[loaderUUID];

    if (loader == nil) {
        [_log warn:[NSString stringWithFormat:@"Can't find loader: %@", path]];
        completion([GCDWebServerDataResponse responseWithStatusCode:404]);
        return;
    }

    [loader processRequestWithUUID:path[2] completionBlock:completion];
}

-(void)dealloc {
    [_log info:@"Dealloc"];
}

@end
