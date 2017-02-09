//
//  hola_hls_segment_info.m
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2017 hola. All rights reserved.
//

#import "hola_hls_segment_info.h"

@class HolaHLSSegmentInfo;

@implementation HolaHLSSegmentInfo

-(NSNumber*)getBitrate {
    return _level.bitrate;
}

-(NSDictionary*)getInfo {
    return @{
        @"playlist_url": _level.url,
        @"bitrate": [self getBitrate],
        @"url": _url,
        @"duration": _duration,
        @"media_index": [NSNumber numberWithUnsignedInteger:[_level.segments indexOfObject:self]]
    };
}

@end
