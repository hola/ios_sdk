//
//  hola_hls_segment_info.h
//  hola-cdn-sdk
//
//  Created by alexeym on 29/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "hola_hls_level_info.h"

@class HolaHLSLevelInfo;

@interface HolaHLSSegmentInfo: NSObject

@property NSString* url;
@property NSNumber* duration;

@property(weak) HolaHLSLevelInfo* level;

-(NSDictionary*)getInfo;

@end
