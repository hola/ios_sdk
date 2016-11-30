//
//  hola_cdn_asset.h
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "hola_cdn_sdk.h"
#import "hola_cdn_loader_delegate.h"

@class HolaCDN;
@class HolaCDNLoaderDelegate;

@interface HolaCDNAsset: AVURLAsset

@property(readonly) HolaCDNLoaderDelegate* loader;
@property(readonly) NSMutableArray* keysToLoad;
@property(readonly) BOOL isAttached;
@property(readonly) BOOL attachTimeoutSet;
@property(readonly) BOOL attachTimeoutTriggered;

-(instancetype)initWithURL:(NSURL*)url andCDN:(HolaCDN*)cdn;
-(void)loadValuesAsynchronouslyForKeys:(NSArray<NSString *> *)keys completionHandler:(void (^)(void))handler;
-(void)onAttached;
-(void)onDetached;

@end
