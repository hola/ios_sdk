//
//  hola_hls_parser.m
//  hola-cdn-sdk
//
//  Created by alexeym on 28/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_hls_parser.h"
#import "hola_log.h"

@interface HolaHLSParser()
{

NSMutableArray<HolaHLSLevelInfo*>* levels;
NSURL* master;

}
@end

typedef NS_ENUM(int, HolaLevelState) {
   HolaLevelStateTop = 0,
   HolaLevelStateInner
};

typedef NS_ENUM(int, HolaHLSEntry) {
   HolaHLSEntryHeader = 0,
   HolaHLSEntryPlaylist,
   HolaHLSEntrySegment,
   HolaHLSEntryKey,
   HolaHLSEntryUrl,
   HolaHLSEntryOther
};

typedef NS_ENUM(int, HolaHLSError) {
   HolaHLSErrorHeader = 0,
   HolaHLSErrorBandwidth,
   HolaHLSErrorDuration,
   HolaHLSErrorObvious
};

@implementation HolaHLSParser

HolaCDNLog* _log;

-(instancetype)init {
    self = [super init];

    if (self) {
        _log = [HolaCDNLog new];
        [_log setModule:@"parser"];
    }

    return self;
}

-(NSString*)parse:(NSString*)url andData:(NSString*)data withError:(NSError**)error {
    HolaHLSLevelInfo* level = [HolaHLSLevelInfo new];
    HolaHLSSegmentInfo* segment = [HolaHLSSegmentInfo new];

    HolaLevelState state = [self getUrlState:url];

    switch (state) {
    case HolaLevelStateTop:
        master = [NSURL URLWithString:url];
        level = [HolaHLSLevelInfo new];
        break;
    case HolaLevelStateInner:
        level = [self getUrlLevel:url];
        break;
    }

    if (![data hasPrefix:@"#EXTM3U"]) {
        *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:HolaHLSErrorHeader userInfo:nil];
        return nil;
    }

    NSMutableArray<NSString*>* lines = [[data componentsSeparatedByString:@"\n"] mutableCopy];
    for (int i = 0; i < lines.count; i+=1) {
        NSString* line = lines[i];

        HolaHLSEntry type = [self getEntryType:line];

        switch (type) {
        case HolaHLSEntryPlaylist:
        {
            NSRange bwPos = [line rangeOfString:@"BANDWIDTH"];
            if (bwPos.location == NSNotFound) {
                *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:HolaHLSErrorBandwidth userInfo:nil];
                return nil;
            }

            NSRange toEnd = NSMakeRange(bwPos.location, line.length);
            NSRange bwEnd = [line rangeOfString:@"," options:NSCaseInsensitiveSearch range:toEnd];
            if (bwEnd.location == NSNotFound) {
                level.bitrate = [NSNumber numberWithInt:[line substringFromIndex:bwPos.location+bwPos.length].intValue];
                continue;
            }

            NSRange toBwEnd = NSMakeRange(bwPos.location+bwPos.length+1, bwEnd.location);
            level.bitrate = [NSNumber numberWithInt:[line substringWithRange:toBwEnd].intValue];
            break;
        }
        case HolaHLSEntrySegment:
        {
            if (state == HolaLevelStateTop) {
                state = HolaLevelStateInner;

                level.bitrate = [NSNumber numberWithInt:1];
                level.url = url;

                master = [NSURL URLWithString:url];
                [levels addObject:level];
            }

            NSRange toEnd = NSMakeRange(8, line.length);
            NSRange durEnd = [line rangeOfString:@"," options:NSCaseInsensitiveSearch range:toEnd];
            if (durEnd.location == NSNotFound) {
                *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:HolaHLSErrorDuration userInfo:nil];
                return nil;
            }

            NSRange toDurEnd = NSMakeRange(8, durEnd.location);
            segment.duration = [NSNumber numberWithInt:[line substringWithRange:toDurEnd].intValue];
            break;
        }
        case HolaHLSEntryUrl:
        {
            NSURL* levelUrl = [NSURL URLWithString:line relativeToURL:master];

            NSURL* cdnLevelUrl;
            if (state == HolaLevelStateTop) {
                level.url = levelUrl.absoluteString;
                [levels addObject:level];
                level = [HolaHLSLevelInfo new];
                cdnLevelUrl = levelUrl; // HolaCDNLoaderDelegate.applyCDNScheme(levelUrl, type: HolaCDNScheme.Fetch)
            } else {
                segment.url = levelUrl.absoluteString;
                segment.level = level;
                [level.segments addObject:segment];
                segment = [HolaHLSSegmentInfo new];
                cdnLevelUrl = levelUrl; //HolaCDNLoaderDelegate.applyCDNScheme(levelUrl, type: HolaCDNScheme.Redirect)
            }

            lines[i] = cdnLevelUrl.absoluteString;
            break;
        }
        case HolaHLSEntryKey:
        {
            NSRange keyPos = [line rangeOfString:@"URI="];
            if (keyPos.location == NSNotFound) {
                break;
            }

            NSRange keyPosEnd = NSMakeRange(keyPos.location+keyPos.length+1, line.length);
            NSRange keyEnd = [line rangeOfString:@"\"" options:NSCaseInsensitiveSearch range:keyPosEnd];
            if (keyEnd.location == NSNotFound) {
                break;
            }

            NSRange keyRange = NSMakeRange(keyPosEnd.location, keyEnd.location);
            NSString* keyUrlString = [line substringWithRange:keyRange];
            NSURL* keyUrl = [NSURL URLWithString:keyUrlString relativeToURL:master];

            NSURL* customKeyUrl = keyUrl; // HolaCDNLoaderDelegate.applyCDNScheme(keyUrl, type: HolaCDNScheme.Key)
            lines[i] = [line stringByReplacingCharactersInRange:keyRange withString:customKeyUrl.absoluteString];
            break;
        }
        default:
            break;
        }
    }

    return [lines componentsJoinedByString:@"\n"];
}

-(NSDictionary*)getSegmentInfo:(NSString*)url {
    for (HolaHLSLevelInfo* level in levels) {
        for (HolaHLSSegmentInfo* segment in level.segments) {
            if ([segment.url hasSuffix:url]) {
                return [segment getInfo];
            }
        }
    }

    return [NSDictionary new];
}

-(NSNumber*)getSegmentSize:(NSString*)url {
    for (HolaHLSLevelInfo* level in levels) {
        for (HolaHLSSegmentInfo* segment in level.segments) {
            if ([segment.url hasSuffix:url]) {
                return segment.size;
            }
        }
    }

    return 0;
}

-(NSDictionary*)getLevels {
    NSMutableDictionary* response = [NSMutableDictionary new];

    for (HolaHLSLevelInfo* level in levels) {
        if ([level.segments count] == 0) {
            continue;
        }

        response[level.url] = [level getInfo];
    }

    return response;
}

-(HolaLevelState)getUrlState:(NSString*)url {
    for (HolaHLSLevelInfo* level in levels) {
        if ([url hasSuffix:level.url]) {
            return HolaLevelStateInner;
        }
    }

    return HolaLevelStateTop;
}

-(HolaHLSLevelInfo*)getUrlLevel:(NSString*)url {
    for (HolaHLSLevelInfo* level in levels) {
        if ([url hasSuffix:level.url]) {
            return level;
        }

        for (HolaHLSSegmentInfo* segment in level.segments) {
            if ([url hasSuffix:segment.url]) {
                return level;
            }
        }
    }

    return [HolaHLSLevelInfo new];
}

-(HolaHLSEntry)getEntryType:(NSString*)entry {
    if ([entry hasPrefix:@"#EXTM3U"]) {
        return HolaHLSEntryHeader;
    }

    if ([entry hasPrefix:@"#EXT-X-STREAM-INF"]) {
        return HolaHLSEntryPlaylist;
    }

    if ([entry hasPrefix:@"#EXTINF"]) {
        return HolaHLSEntrySegment;
    }

    if ([entry hasPrefix:@"#EXT-X-KEY"]) {
        return HolaHLSEntryKey;
    }

    if ([entry length] == 0) {
        return HolaHLSEntryOther;
    }

    if ([entry hasPrefix:@"#"]) {
        return HolaHLSEntryUrl;
    }

    return HolaHLSEntryOther;
}

@end
