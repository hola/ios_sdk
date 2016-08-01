//
//  hola_cdn_asset.h
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "hola_cdn_sdk.h"

@interface HolaCDNAsset: AVURLAsset

//@property(readonly) HolaCDNLoaderDelegate loader;

-(instancetype)initWithURL:(NSURL*)url andCDN:(HolaCDN*)cdn;

@end
