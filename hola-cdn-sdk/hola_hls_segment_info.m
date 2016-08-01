//
//  hola_hls_segment_info.m
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_hls_segment_info.h"

@class HolaHLSSegmentInfo;

@implementation HolaHLSSegmentInfo

-(NSDictionary*)getInfo {
    return @{
        @"playlist_url": _level.url,
        @"bitrate": _bitrate,
        @"url": _url,
        @"duration": _duration,
        @"media_index": [NSNumber numberWithUnsignedInteger:[_level.segments indexOfObject:self]]
    };
}

@end
