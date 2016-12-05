//
//  hola_hls_parser.h
//  hola-cdn-sdk
//
//  Created by alexeym on 28/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "hola_log.h"
#import "hola_hls_segment_info.h"
#import "hola_hls_level_info.h"

@interface HolaHLSParser : NSObject

@property(readonly) HolaCDNLog* log;

-(NSString*)parse:(NSString*)url andData:(NSString*)data withError:(NSError**)error;
-(NSDictionary*)getSegmentInfo:(NSString*)url;
-(BOOL)isMedia:(NSString*)url;

@end
