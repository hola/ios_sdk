//
//  hola_hls_level_info.h
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "hola_hls_segment_info.h"

@class HolaHLSSegmentInfo;

@interface HolaHLSLevelInfo : NSObject

@property NSString* url;
@property NSNumber* bitrate;

@property NSMutableArray<HolaHLSSegmentInfo*>* segments;

-(NSDictionary*)getInfo;

@end
