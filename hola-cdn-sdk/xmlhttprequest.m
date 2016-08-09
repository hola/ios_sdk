//
//  XMLHttpRequest.m
//  hola-cdn-sdk
//
//  Created by norlin on 04/08/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "XMLHttpRequest.h"

@implementation XMLHttpRequest
{
    NSURLSession *_urlSession;
    NSString *_httpMethod;
    NSURL *_url;
    __weak JSContext* _context;
    bool _async;
    NSMutableDictionary *_requestHeaders;
    NSDictionary *_responseHeaders;
}

NS_ENUM(NSUInteger, XMLHttpReadyState) {
    XMLHttpReadyStateUNSENT =0,
    XMLHttpReadyStateOPENED,
    XMLHttpReadyStateHEADERS,
    XMLHttpReadyStateLOADING,
    XMLHttpReadyStateDONE
};

@synthesize response;
@synthesize responseText;
@synthesize onreadystatechange;
@synthesize readyState;
@synthesize onload;
@synthesize onerror;
@synthesize status;

- (instancetype)init {
    return [self initWithURLSession:[NSURLSession sharedSession]];
}

- (instancetype)initWithURLSession:(NSURLSession *)urlSession {
    if (self = [super init]) {
        _urlSession = urlSession;
        readyState = @(XMLHttpReadyStateUNSENT);
        _requestHeaders = [NSMutableDictionary new];
    }
    return self;
}

- (void)extend:(id)jsContext {

    // simulate the constructor.
    jsContext[@"XMLHttpRequest"] = ^{
        return self;
    };
    jsContext[@"XMLHttpRequest"][@"UNSENT"] = @(XMLHttpReadyStateUNSENT);
    jsContext[@"XMLHttpRequest"][@"OPENED"] = @(XMLHttpReadyStateOPENED);
    jsContext[@"XMLHttpRequest"][@"LOADING"] = @(XMLHttpReadyStateLOADING);
    jsContext[@"XMLHttpRequest"][@"HEADERS"] = @(XMLHttpReadyStateHEADERS);
    jsContext[@"XMLHttpRequest"][@"DONE"] = @(XMLHttpReadyStateDONE);

    _context = jsContext;
}

- (void)open:(NSString *)httpMethod :(NSString *)url :(bool)async {
    // XXX alexeym: should throw an error if called with wrong arguments
    _httpMethod = httpMethod;
    _url = [NSURL URLWithString:url];
    if ([_url scheme] == nil) {
        NSString* location = _context[@"location"][@"href"].toString;
        NSString* scheme = nil;
        if (location != nil) {
            NSURL* href = [NSURL URLWithString:location];
            scheme = href.scheme;
        }
        NSURLComponents* components = [NSURLComponents componentsWithURL:_url resolvingAgainstBaseURL:NO];
        components.scheme = scheme == nil ? @"http" : scheme;
        _url = [components URL];
    }
    _async = async;
    readyState = @(XMLHttpReadyStateOPENED);
}

-(void)abort {
    [_urlSession invalidateAndCancel];
}

- (void)send:(id)data {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url];
    for (NSString *name in _requestHeaders) {
        [request setValue:_requestHeaders[name] forHTTPHeaderField:name];
    }

    if ([data isKindOfClass:[NSString class]]) {
        request.HTTPBody = [((NSString *) data) dataUsingEncoding:NSUTF8StringEncoding];
    }

    [request setHTTPMethod:_httpMethod];

    __block __weak XMLHttpRequest *weakSelf = self;

    id completionHandler = ^(NSData *receivedData, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
        weakSelf.readyState = @(XMLHttpReadyStateDONE);
        weakSelf.status = @(httpResponse.statusCode);
        weakSelf.responseText = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
        weakSelf.response = weakSelf.responseText;

        [weakSelf setAllResponseHeaders:[httpResponse allHeaderFields]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.onreadystatechange == nil || ![weakSelf.onreadystatechange toBool]) {
                return;
            }
            [weakSelf.onreadystatechange.context[@"setTimeout"] callWithArguments:@[weakSelf.onreadystatechange, [JSValue valueWithInt32:0 inContext:[weakSelf.onload context]]]];
        });

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.onload == nil || ![weakSelf.onload toBool]) {
                return;
            }

            NSDictionary* event = @{
                @"target": @{
                    @"response": weakSelf.response == nil ? [JSValue valueWithUndefinedInContext:[weakSelf.onload context]] : weakSelf.response,
                    @"responseText": weakSelf.responseText == nil ? @"" : weakSelf.responseText,
                },
                @"total": [NSNumber numberWithInteger:[receivedData length]]
            };

            JSValue* jsEvent = [JSValue valueWithObject:event inContext:[weakSelf.onload context]];

            NSArray* args = @[weakSelf.onload, [JSValue valueWithInt32:0 inContext:[weakSelf.onload context]], jsEvent];
            [weakSelf.onload.context[@"setTimeout"] callWithArguments:args];
        });
    };
    NSURLSessionDataTask *task = [_urlSession dataTaskWithRequest:request completionHandler:completionHandler];
    [task resume];
}

- (void)setRequestHeader:(NSString*)name :(NSString*)value {
    _requestHeaders[name] = value;
}

- (NSString*)getAllResponseHeaders {
    NSMutableString* responseHeaders = [NSMutableString new];
    for (NSString* key in _responseHeaders) {
        [responseHeaders appendString:key];
        [responseHeaders appendString:@": "];
        [responseHeaders appendString:_responseHeaders[key]];
        [responseHeaders appendString:@"\n"];
    }
    return responseHeaders;
}

- (NSString*)getReponseHeader:(NSString*)name {
    return _responseHeaders[name];
}

- (void)setAllResponseHeaders:(NSDictionary*)responseHeaders {
    _responseHeaders = responseHeaders;
}

@end
