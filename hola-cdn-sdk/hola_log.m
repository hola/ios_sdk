//
//  HolaCDNLog.m
//  hola-cdn-sdk
//
//  Created by alexeym on 27/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_log.h"

@implementation HolaCDNLog

static HolaCDNLogLevel verboseLevel = HolaCDNLogLevelError;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _module = @"cdn";
    }
    return self;
}

+(void) setVerboseLevel:(HolaCDNLogLevel) level {
    verboseLevel = level;
}

-(NSString*) prefixForLevel:(HolaCDNLogLevel)level {
    NSString* levelString;

    switch (level) {
      case HolaCDNLogLevelNone:
        levelString = @"";
        break;
      case HolaCDNLogLevelDebug:
        levelString = @"DEBUG";
        break;

      case HolaCDNLogLevelInfo:
        levelString = @"INFO";
        break;

      case HolaCDNLogLevelWarning:
        levelString = @"WARN";
        break;

      case HolaCDNLogLevelError:
        levelString = @"ERROR";
        break;

      case HolaCDNLogLevelCritical:
        levelString = @"CRIT";
        break;
    }

    return [NSString stringWithFormat:@"[%@/%@]", levelString, _module];
}

-(void) rawLogWithLevel:(HolaCDNLogLevel)level andMessage:(NSString *)msg {
    if (level < verboseLevel) {
        return;
    }

    NSLog(@"%@%@", [self prefixForLevel:level], msg);
}

-(void) debug:(NSString*) msg {
    [self rawLogWithLevel:HolaCDNLogLevelDebug andMessage:msg];
}

-(void) info:(NSString*) msg {
    [self rawLogWithLevel:HolaCDNLogLevelInfo andMessage:msg];
}

-(void) warn:(NSString*) msg {
    [self rawLogWithLevel:HolaCDNLogLevelWarning andMessage:msg];
}

-(void) err:(NSString*) msg {
    [self rawLogWithLevel:HolaCDNLogLevelError andMessage:msg];
}

-(void) crit:(NSString*) msg {
    [self rawLogWithLevel:HolaCDNLogLevelCritical andMessage:msg];
}

@end
