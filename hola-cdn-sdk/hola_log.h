//
//  HolaCDNLog.h
//  hola-cdn-sdk
//
//  Created by alexeym on 27/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(int, HolaCDNLogLevel) {
   HolaCDNLogLevelNone = 0,
   HolaCDNLogLevelDebug,
   HolaCDNLogLevelInfo,
   HolaCDNLogLevelWarning,
   HolaCDNLogLevelError,
   HolaCDNLogLevelCritical
};

@interface HolaCDNLog : NSObject

@property NSString* module;

-(void) debug:(NSString*) msg;
-(void) info:(NSString*) msg;
-(void) warn:(NSString*) msg;
-(void) err:(NSString*) msg;
-(void) crit:(NSString*) msg;

+(void) setVerboseLevel:(HolaCDNLogLevel) level;

@end
