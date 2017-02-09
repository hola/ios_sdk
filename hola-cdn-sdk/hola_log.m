//
//  HolaCDNLog.m
//  hola-cdn-sdk
//
//  Created by alexeym on 27/07/16.
//  Copyright © 2017 hola. All rights reserved.
//

#import "hola_log.h"

@implementation HolaCDNLog

static HolaCDNLogLevel verboseLevel = HolaCDNLogLevelError;
static NSArray* verboseModules;

static dispatch_once_t onceToken;
static NSString* const defaultModules[] = {};
static int const defaultModulesCount = 0;

- (instancetype)init:(NSString*)module
{
    self = [super init];
    if (self) {
        _module = module == nil ? @"cdn" : module;

        NSNumber* instances = [HolaCDNLog instances][_module];
        if (instances == nil) {
            [[HolaCDNLog instances] setObject:[NSNumber numberWithInt:1] forKey:_module];
            _instance = 1;
        } else {
            _instance = [instances intValue]+1;
            [[HolaCDNLog instances] setObject:[NSNumber numberWithInt:_instance] forKey:_module];
        }

        dispatch_once(&onceToken, ^{
            if (verboseModules == nil) {
                [HolaCDNLog setVerboseModules:nil];
            }
        });
    }
    return self;
}

+(NSMutableDictionary*)instances {
    static NSMutableDictionary* instances = nil;
    if (instances == nil) {
        instances = [NSMutableDictionary new];
    }

    return instances;
}

+(instancetype)logWithModule:(NSString*)module {
    return [[HolaCDNLog alloc] init:module];
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

    NSString* instanceID = _instance != 0 ? [NSString stringWithFormat:@":%d", _instance] : @"";
    return [NSString stringWithFormat:@"[%@/%@%@]", levelString, _module, instanceID];
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
