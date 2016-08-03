//
//  hola_cdn_asset.m
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_cdn_asset.h"

@implementation HolaCDNAsset

-(instancetype)initWithURL:(NSURL*)url andCDN:(HolaCDN*)cdn {
    NSURL* cdnURL = [HolaCDNLoaderDelegate applyCDNScheme:url andType:HolaCDNSchemeFetch];

    _loader = [[HolaCDNLoaderDelegate alloc] initWithCDN:cdn];

    self = [super initWithURL:cdnURL options:nil];
    if (self) {
        [self.resourceLoader setDelegate:_loader queue:_loader.queue];
    }

    return self;
}

-(void)dealloc {
    [_loader uninit];
    _loader = nil;
}

@end
