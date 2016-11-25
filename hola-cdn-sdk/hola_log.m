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
static NSArray* verboseModules;

static dispatch_once_t onceToken;
static NSString* const defaultModules[] = {@"cdn", @"player", @"parser"};
static int const defaultModulesCount = 3;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _module = @"cdn";

        dispatch_once(&onceToken, ^{
            if (verboseModules == nil) {
                [HolaCDNLog setVerboseModules:nil];
            }
        });
    }
    return self;
}

+(void) setVerboseLevel:(HolaCDNLogLevel) level {
    verboseLevel = level;
}

+(void) setVerboseModules:(NSArray*) modules {
    if (modules == nil) {
        NSArray* dm = [NSArray arrayWithObjects:defaultModules count:defaultModulesCount];
        verboseModules = dm;
        return;
    }

    verboseModules = modules;
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

    if (verboseModules == nil || [verboseModules count] == 0 || [verboseModules containsObject:_module]) {
        NSLog(@"%@ %@", [self prefixForLevel:level], msg);
    }
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
