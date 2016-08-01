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
    // let url = HolaCDNLoaderDelegate.applyCDNScheme(URL, type: HolaCDNScheme.Fetch)
    // loader = HolaCDNLoaderDelegate(cdn)

    self = [super initWithURL:url options:nil];
    if (self) {
        //self.resourceLoader.setDelegate(loader, queue: loader.queue)
    }

    return self;
}

@end
