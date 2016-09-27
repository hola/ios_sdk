//
//  hola_cdn_loader_delegate.m
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_loader_delegate.h"
#import "hola_hls_parser.h"
#import "GCDWebServer/GCDWebServerRequest.h"
#import "GCDWebServer/GCDWebServerDataResponse.h"
#import "GCDWebServer/GCDWebServerStreamedResponse.h"

@interface HolaCDNLoaderDelegate()
{
HolaCDN* _cdn;
HolaHLSParser* _parser;
GCDWebServer* _server;
NSURLSession* _session;

int _totalBytes;

NSMutableDictionary<NSNumber*, AVAssetResourceLoadingRequest*>* pending;
NSMutableDictionary<NSString*, NSMutableDictionary*>* proxyRequests;
NSMutableDictionary<NSNumber*, GCDWebServerCompletionBlock>* taskClients;
NSMutableDictionary<NSNumber*, NSString*>* taskTimers;

int req_id;
}
@end

@implementation HolaCDNLoaderDelegate

static HolaCDNLog* _log;
static const char* LOADER_QUEUE = "org.hola.hola-cdn-sdk.loader";

// class static methods

+(NSString*)getOriginSchemeName:(HolaScheme)scheme {
    switch (scheme) {
    case HolaSchemeHTTP:
        return @"http";
    case HolaSchemeHTTPS:
        return @"https";
    }
}

+(NSString*)getCDNSchemeName:(HolaScheme)scheme andType:(HolaCDNScheme)type {
    switch (scheme) {
    case HolaSchemeHTTP:
        switch (type) {
        case HolaCDNSchemeFetch:
            return @"hcdnf";
        case HolaCDNSchemeRedirect:
            return @"hcdnr";
        case HolaCDNSchemeKey:
            return @"hcdnk";
        case HolaCDNSchemeProgressive:
            return @"hcdnp";
        }
    case HolaSchemeHTTPS:
        switch (type) {
        case HolaCDNSchemeFetch:
            return @"hcdnfs";
        case HolaCDNSchemeRedirect:
            return @"hcdnrs";
        case HolaCDNSchemeKey:
            return @"hcdnks";
        case HolaCDNSchemeProgressive:
            return @"hcdnps";
        }
    }
}

+(HolaScheme)mapScheme:(NSString*)scheme {
    NSArray<NSString*>* http = [NSArray arrayWithObjects:@"http", @"hcdnf", @"hcdnr", @"hcdnk", @"hcdnp", nil];
    NSArray<NSString*>* https = [NSArray arrayWithObjects:@"https", @"hcdnfs", @"hcdnrs", @"hcdnks", @"hcdnps", nil];

    if ([http containsObject:scheme]) {
        return HolaSchemeHTTP;
    }

    if ([https containsObject:scheme]) {
        return HolaSchemeHTTPS;
    }

    return HolaSchemeHTTP;
}

+(HolaCDNScheme)mapCDNScheme:(NSURL*)url {
    NSArray<NSString*>* fetch = [NSArray arrayWithObjects:@"http", @"https", @"hcdnf", @"hcdnfs", nil];
    NSArray<NSString*>* redirect = [NSArray arrayWithObjects:@"hcdnr", @"hcdnrs", nil];
    NSArray<NSString*>* key = [NSArray arrayWithObjects:@"hcdnk", @"hcdnks", nil];
    NSArray<NSString*>* progressive = [NSArray arrayWithObjects:@"hcdnp", @"hcdnps", nil];

    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    NSString* scheme = components.scheme;

    NSString* extension = url.pathExtension;

    if ([extension isEqualToString:@"mp4"]) {
        // XXX alexeym TODO
        return HolaCDNSchemeProgressive;
    }

    if ([fetch containsObject:scheme]) {
        return HolaCDNSchemeFetch;
    }

    if ([redirect containsObject:scheme]) {
        return HolaCDNSchemeRedirect;
    }

    if ([key containsObject:scheme]) {
        return HolaCDNSchemeKey;
    }

    return HolaCDNSchemeFetch;
}

+(NSURL*)applyCDNScheme:(NSURL*)url andType:(HolaCDNScheme)type {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    HolaScheme scheme = [HolaCDNLoaderDelegate mapScheme:components.scheme];

    [components setScheme:[HolaCDNLoaderDelegate getCDNSchemeName:scheme andType:type]];

    return [components URL];
}

+(NSURL*)applyOriginScheme:(NSURL*)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    HolaScheme scheme = [HolaCDNLoaderDelegate mapScheme:components.scheme];

    [components setScheme:[HolaCDNLoaderDelegate getOriginSchemeName:scheme]];

    return [components URL];
}

// delegate init

-(instancetype)initWithCDN:(HolaCDN*)cdn {
    self = [super init];
    if (self) {
        _log = [HolaCDNLog new];
        [_log setModule:@"Loader"];

        req_id = 1;
        pending = [NSMutableDictionary new];
        proxyRequests = [NSMutableDictionary new];
        taskTimers = [NSMutableDictionary new];
        taskClients = [NSMutableDictionary new];

        _totalBytes = 0;

        _cdn = cdn;
        _queue = dispatch_queue_create(LOADER_QUEUE, nil);
        _parser = [HolaHLSParser new];

        NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];

        _server = cdn.server;

        __weak typeof(self) weakSelf = self;
        [_server addDefaultHandlerForMethod:@"GET" requestClass:[GCDWebServerRequest self] asyncProcessBlock:^(__kindof GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {
            [weakSelf processRequest:request completionBlock:completionBlock];
        }];

        NSError* err = nil;
        [_server startWithOptions:@{
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_Port: [NSNumber numberWithInt:[cdn serverPort]],
            GCDWebServerOption_BonjourName: @"HolaCDN"
        } error:&err];
    }

    return self;
}

-(void)dealloc {
    [self uninit];
}

-(void)uninit {
    if (_session != nil) {
        [_session invalidateAndCancel];
        _session = nil;
    }

    if (_server != nil) {
        [_server stop];
        _server = nil;
    }
}

// requests handling

-(BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    return [self makeRequest:loadingRequest];
}

-(BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest {
    return YES;
}

-(BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForResponseToAuthenticationChallenge:(NSURLAuthenticationChallenge *)authenticationChallenge {
    return YES;
}

-(BOOL)makeRequest:(AVAssetResourceLoadingRequest*)req {
    if (_cdn.playerProxy == nil) {
        [_log err:@"Trying to make request, but no player attached!"];
        return NO;
    }

    if (req.request.URL == nil) {
        [_log err:@"Trying to make request, but no request url found!"];
        return NO;
    }

    // TODO:
    if (NO/*non-HLS*/) {
        /*
        serve it via some ProgressiveProxyHandler
        ProgressiveProxyHandler
            send cdns "req", creates internal req_id and so on
            responses with chunks to the single mp4 request
        */
    } else {
        NSNumber* currentId = [NSNumber numberWithInt:req_id];
        [pending setObject:req forKey:currentId];

        NSURL* originUrl = [HolaCDNLoaderDelegate applyOriginScheme:req.request.URL];
        [_log debug:[NSString stringWithFormat:@"makeRequest: %@", originUrl.absoluteString]];

        [_cdn.playerProxy execute:@"req" withValue:[JSValue valueWithObject:@{
            @"url": originUrl.absoluteString,
            @"req_id": currentId
        } inContext:_cdn.ctx]];

        req_id += 1;
    }

    return YES;
}

-(void)processRequest:(NSString*)url forFrag:(int)frag_id withReq:(int)arg_req_id isRate:(BOOL)rate {
    if ([pending objectForKey:[NSNumber numberWithInt:frag_id]] == nil) {
        [_log warn:[NSString stringWithFormat:@"Unknown req_id %d", frag_id]];
        return;
    }

    [self sendOpen:arg_req_id];

    if (rate) {
        [self processExternalRequest:url :arg_req_id];
        return;
    }

    AVAssetResourceLoadingRequest* req = [self getRequest:frag_id];
    [_log debug:[NSString stringWithFormat:@"get request %d", frag_id]];
    if (req == nil) {
        [self processExternalRequest:url :arg_req_id];
        return;
    }

    [self processInternalRequest:url :req :arg_req_id];
}

-(void)processExternalRequest:(NSString*)url :(int)arg_req_id {
    NSURL* nsurl = [HolaCDNLoaderDelegate applyOriginScheme:[NSURL URLWithString:url]];

    NSDate* date = [NSDate new];
    NSError* err = nil;
    NSData* data = [NSData dataWithContentsOfURL:nsurl options:NSDataReadingUncached error:&err];
    if (err != nil) {
        [_log err:[NSString stringWithFormat:@"external fetch error %@", err]];
        [self sendError:arg_req_id];
        return;
    }

    NSTimeInterval interval = [[NSDate new] timeIntervalSinceDate:date];

    [self sendResponse:arg_req_id :(interval * 1000) :200];
    [self sendProgress:arg_req_id :(int)[data length] :(int)[data length]];
    [self sendComplete:arg_req_id];
}

-(void)processInternalRequest:(NSString*)url :(AVAssetResourceLoadingRequest*)req :(int)arg_req_id {
    HolaCDNScheme scheme = [HolaCDNLoaderDelegate mapCDNScheme:req.request.URL];

    switch (scheme) {
    case HolaCDNSchemeRedirect:
        [self redirect:url forRequest:req withId:arg_req_id];
        break;
    case HolaCDNSchemeFetch:
        [self fetch:req :arg_req_id];
        break;
    case HolaCDNSchemeKey:
        [self fetch:req :arg_req_id :YES];
        break;
    case HolaCDNSchemeProgressive:
        [self redirect:url forRequest:req withId:arg_req_id];
        break;
    }
}

-(void)fetch:(AVAssetResourceLoadingRequest*)req :(int)arg_req_id {
    [self fetch:req :arg_req_id :NO];
}

-(void)fetch:(AVAssetResourceLoadingRequest*)req :(int)arg_req_id :(BOOL)key {
    NSURL* url = [HolaCDNLoaderDelegate applyOriginScheme:req.request.URL];

    NSDate* date = [NSDate new];
    NSError* err = nil;
    NSData* nsData;
    if (key) {
        nsData = [NSData dataWithContentsOfURL:url];
    } else {
        NSString* data = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];

        if (err != nil) {
            [_log err:[NSString stringWithFormat:@"Can't fetch data %@", err]];
            [self sendError:req msg:@"Can't fetch data"];
            [self sendError:arg_req_id];
            return;
        }

        NSString* manifest = [_parser parse:url.absoluteString andData:data withError:&err];
        if (err != nil) {
            [_log err:[NSString stringWithFormat:@"Can't parse data %@", err]];
            [self sendError:req msg:@"Can't parse data"];
            [self sendError:arg_req_id];
            return;
        }

        nsData = [NSData dataWithData:[manifest dataUsingEncoding:NSUTF8StringEncoding]];
    }

    NSTimeInterval interval = [[NSDate new] timeIntervalSinceDate:date];

    dispatch_async(_queue, ^{
        [req.dataRequest respondWithData:nsData];
        [req finishLoading];
    });

    [self sendResponse:arg_req_id :(interval * 1000) :200];
    [self sendProgress:arg_req_id :(int)[nsData length] :(int)[nsData length]];
    [self sendComplete:arg_req_id];
}

-(void)redirect:(NSString*)urlString forRequest:(AVAssetResourceLoadingRequest*)req withId:(int)arg_req_id {
    NSURL* url = [NSURL URLWithString:urlString];

    NSMutableDictionary* proxyRec = [NSMutableDictionary new];
    proxyRec[@"uuid"] = [[NSUUID new] UUIDString];
    proxyRec[@"id"] = [NSNumber numberWithInt:arg_req_id];
    proxyRec[@"target"] = url;
    proxyRec[@"timer"] = [NSDate new];
    proxyRec[@"data"] = [NSMutableData new];
    proxyRec[@"size"] = [NSNumber numberWithInt:0];

    AVAssetResourceLoadingDataRequest* dataReq = req.dataRequest;
    if (dataReq.requestedOffset != 0 || !dataReq.requestsAllDataToEndOfResource) {
        proxyRec[@"range"] = [NSString stringWithFormat:@"bytes=%lli-%lli", dataReq.requestedOffset, dataReq.requestedOffset + dataReq.requestedLength-1];
    }

    [proxyRequests setObject:proxyRec forKey:proxyRec[@"uuid"]];

    NSString* redirectUrl = [NSString stringWithFormat:@"http://127.0.0.1:%d/%@", [_cdn serverPort], proxyRec[@"uuid"]];

    dispatch_async(_queue, ^{
        NSURLRequest* redirect = [NSURLRequest requestWithURL:[NSURL URLWithString:redirectUrl]];
        [req setRedirect:redirect];

        NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:302 HTTPVersion:nil headerFields:nil];
        [req setResponse:response];
        [req finishLoading];
    });
}

-(void)sendError:(AVAssetResourceLoadingRequest*)req msg:(NSString*)msg {
    [_log err:msg];

    dispatch_async(_queue, ^{
        [req finishLoadingWithError:[NSError errorWithDomain:@"org.hola.hola-cdn-sdk.loader" code:HolaCDNErrorCodeBadRequest userInfo:@{
            NSLocalizedFailureReasonErrorKey: msg
        }]];
    });
}

-(AVAssetResourceLoadingRequest*)getRequest:(int)arg_req_id {
    NSNumber* key = [NSNumber numberWithInt:arg_req_id];
    AVAssetResourceLoadingRequest* req = [pending objectForKey:key];

    if (req == nil) {
        return nil;
    }

    [pending removeObjectForKey:key];
    return req;
}

-(void)remove:(int)arg_req_id {
    AVAssetResourceLoadingRequest* req = [self getRequest:arg_req_id];

    if (req == nil) {
        return;
    }

    dispatch_async(_queue, ^{
        [req finishLoadingWithError:[NSError errorWithDomain:@"org.hola.hola-cdn-sdk.loader" code:HolaCDNErrorCodeCancelled userInfo:@{
            NSLocalizedFailureReasonErrorKey: @"Request cancelled"
        }]];
    });
}

-(void)sendMessage:(NSString*)message withData:(id)data {
    if (_cdn.playerProxy == nil) {
        [_log err:@"Trying to send message, but no player attached!"];
        return;
    }

    [_cdn.playerProxy execute:message withValue:data];
}

-(NSDictionary*)getSegmentInfo:(NSString*)url {
    return [_parser getSegmentInfo:url];
}

// communications with js code

-(void)sendOpen:(int)arg_req_id {
    [self sendMessage:@"stream_open" withData:@{
        @"req_id": [NSNumber numberWithInt:arg_req_id]
    }];
}

-(void)sendComplete:(int)arg_req_id {
    [self sendMessage:@"stream_complete" withData:@{
        @"req_id": [NSNumber numberWithInt:arg_req_id]
    }];
}

-(void)sendError:(int)arg_req_id {
    [self sendMessage:@"stream_error" withData:@{
        @"req_id": [NSNumber numberWithInt:arg_req_id]
    }];
}

-(void)sendResponse:(int)arg_req_id :(int)ms :(int)statusCode {
    [self sendMessage:@"stream_response" withData:@{
        @"req_id": [NSNumber numberWithInt:arg_req_id],
        @"ms": [NSNumber numberWithInt:ms],
        @"status": [NSNumber numberWithInt:statusCode]
    }];
}

-(void)sendProgress:(int)arg_req_id :(int)loaded :(int)total {
    [self sendMessage:@"stream_progress" withData:@{
        @"req_id": [NSNumber numberWithInt:arg_req_id],
        @"loaded": [NSNumber numberWithInt:loaded],
        @"total": [NSNumber numberWithInt:total]
    }];
}

// data fetching

-(void)processRequest:(GCDWebServerRequest*)request completionBlock:(GCDWebServerCompletionBlock)completion {
    NSArray<NSString*>* path = [request.URL pathComponents];

    if (path == nil) {
        completion([GCDWebServerDataResponse responseWithStatusCode:400]);
        return;
    }

    NSString* uuid = path[1];
    NSURLSessionDataTask* task = [self processRequestWithUUID:uuid completionBlock:completion];

    if (task == nil) {
        completion([GCDWebServerDataResponse responseWithStatusCode:400]);
        return;
    }

    [task resume];
}

-(NSURLSessionDataTask*)processRequestWithUUID:(NSString*)uuid completionBlock:(GCDWebServerCompletionBlock)completion {
    NSDictionary* proxyRec = proxyRequests[uuid];

    if (proxyRec == nil) {
        [_log warn:@"process request: no proxy request found!"];
        completion([GCDWebServerDataResponse responseWithStatusCode:400]);
        return nil;
    }

    NSURL* url = [HolaCDNLoaderDelegate applyOriginScheme:proxyRec[@"target"]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];

    NSString* range = proxyRec[@"range"];
    if (range != nil) {
        [_log debug:[NSString stringWithFormat:@"request specific range: %@", proxyRec[@"range"]]];
        [request setValue:proxyRec[@"range"] forHTTPHeaderField:@"Range"];
    }

    NSURLSessionDataTask* task = [_session dataTaskWithRequest:request];
    NSNumber* taskId = [NSNumber numberWithUnsignedInteger:task.taskIdentifier];

    [_log debug:[NSString stringWithFormat:@"start request: %d", taskId.integerValue]];

    [taskClients setObject:completion forKey:taskId];
    [taskTimers setObject:proxyRec[@"uuid"] forKey:taskId];

    return task;
}

-(void)handleResponse:(NSDictionary*)req withResponse:(NSHTTPURLResponse*)resp andId:(NSNumber*)taskId {
    int ms;

    [_log debug:[NSString stringWithFormat:@"handle response: %d", taskId.integerValue]];

    NSDictionary* headers = [resp allHeaderFields];

    NSDate* timer = req[@"timer"];
    if (timer == nil) {
        ms = 100;
    } else {
        NSTimeInterval interval = [[NSDate new] timeIntervalSinceDate:timer];
        ms = interval * 1000;
    }

    int size;
    NSString* length = headers[@"Content-Length"];
    if (length == nil) {
        size = 0;
    } else {
        size = [length intValue];
    }

    NSString* uuid = req[@"uuid"];
    [[proxyRequests objectForKey:uuid] setObject:[NSNumber numberWithInt:size] forKey:@"size"];
    [[proxyRequests objectForKey:uuid] setObject:[NSNumber numberWithInteger:[resp statusCode]] forKey:@"statusCode"];

    NSString* type = [resp MIMEType];
    [[proxyRequests objectForKey:uuid] setObject:type forKey:@"contentType"];
    [[proxyRequests objectForKey:uuid] setObject:headers forKey:@"headers"];

    [self sendResponse:((NSNumber*)req[@"id"]).intValue :ms :(int)[resp statusCode]];

    [_log debug:[NSString stringWithFormat:@"handle response full done: %d", taskId.integerValue]];
}

-(void)redirectProgress:(NSDictionary*)req {
    NSData* data = req[@"data"];
    [self sendProgress:((NSNumber*)req[@"id"]).intValue  :(int)data.length  :((NSNumber*)req[@"size"]).intValue];
}

-(void)redirectComplete:(NSDictionary*)req {
    [self sendComplete:((NSNumber*)req[@"id"]).intValue];
}

-(void)redirectError:(NSDictionary*)req withError:(NSError*)err {
    [self sendError:((NSNumber*)req[@"id"]).intValue];
}

-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {

    NSNumber* taskId = [NSNumber numberWithUnsignedInteger:dataTask.taskIdentifier];
    GCDWebServerCompletionBlock client = [taskClients objectForKey:taskId];

    [_log debug:[NSString stringWithFormat:@"receive response: %d", taskId.integerValue]];

    if (client == nil) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }

    NSString* uuid  = [taskTimers objectForKey:taskId];
    if (uuid == nil) {
        completionHandler(NSURLSessionResponseCancel);
        client([GCDWebServerDataResponse responseWithStatusCode:400]);
        return;
    }

    NSDictionary* proxyRec = [proxyRequests objectForKey:uuid];
    if (proxyRec == nil) {
        completionHandler(NSURLSessionResponseCancel);
        client([GCDWebServerDataResponse responseWithStatusCode:400]);
        return;
    }

    [self handleResponse:proxyRec withResponse:(NSHTTPURLResponse*)response andId:taskId];
    completionHandler(NSURLSessionResponseAllow);
}

-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSNumber* taskId = [NSNumber numberWithUnsignedInteger:dataTask.taskIdentifier];
    NSString* uuid = [taskTimers objectForKey:taskId];

    if (uuid == nil) {
        [_log err:@"no uuid found"];
        return;
    }

    NSDictionary* proxyRec = [proxyRequests objectForKey:uuid];
    if (proxyRec == nil) {
        [_log err:@"no proxyRec found"];
        return;
    }

    NSMutableData* requestData = [[proxyRequests objectForKey:proxyRec[@"uuid"]] objectForKey:@"data"];
    [requestData appendData:data];
    [[proxyRequests objectForKey:proxyRec[@"uuid"]] setObject:requestData forKey:@"data"];

    [_log debug:[NSString stringWithFormat:@"receive data: %d", requestData.length]];
    _totalBytes += data.length;
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSNumber* taskId = [NSNumber numberWithUnsignedInteger:task.taskIdentifier];

    GCDWebServerCompletionBlock client = [taskClients objectForKey:taskId];

    if (client == nil) {
        return;
    }

    [_log debug:[NSString stringWithFormat:@"request complete: %d", taskId.integerValue]];

    [taskClients removeObjectForKey:taskId];

    if (error != nil) {
        [_log err:[NSString stringWithFormat:@"%@", error]];
        client([GCDWebServerDataResponse responseWithStatusCode:502]);
    }

    NSString* uuid = [taskTimers objectForKey:taskId];
    if (uuid == nil) {
        [_log err:@"no uuid on completion found"];
        return;
    }

    [taskTimers removeObjectForKey:taskId];

    NSDictionary* proxyRec = [proxyRequests objectForKey:uuid];
    if (proxyRec == nil) {
        [_log err:@"no proxyRec on completion found"];
        return;
    }

    NSDictionary* headers = proxyRec[@"headers"];

    [proxyRequests removeObjectForKey:uuid];
    [self redirectProgress:proxyRec];

    if (error != nil) {
        [_log err:@"error on completion found"];
        [self redirectError:proxyRec withError:error];
    } else {
        NSData* data = proxyRec[@"data"];
        [_log debug:[NSString stringWithFormat:@"request done %@\n, total: %d, %d, %@", proxyRec[@"target"], _totalBytes, data.length, proxyRec[@"contentType"]]];
        GCDWebServerDataResponse* response = [GCDWebServerDataResponse responseWithData:data contentType:proxyRec[@"contentType"]];

        for (NSString* header in headers) {
            NSString* value = headers[header];
            [response setValue:value forAdditionalHeader:header];
            NSLog(@"%@: %@", header, value);
        }

        client(response);
        [self redirectComplete:proxyRec];
    }
}

@end



















