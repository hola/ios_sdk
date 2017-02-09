//
//  hola_hls_level_info.m
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2017 hola. All rights reserved.
//

#import "hola_hls_level_info.h"

@class HolaHLSLevelInfo;

@implementation HolaHLSLevelInfo

-(instancetype)init {
    self = [super init];

    if (self) {
        _segments = [NSMutableArray new];
    }

    return self;
}

-(NSDictionary*)getInfo {
    NSMutableArray* segmentsInfo = [NSMutableArray new];

    for (HolaHLSSegmentInfo* segment in _segments) {
        [segmentsInfo addObject:[segment getInfo]];
    }

    return @{
        @"url": _url,
        @"bitrate": _bitrate,
        @"segments": segmentsInfo
    };
}

@end
