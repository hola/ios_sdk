//
//  hola_hls_parser.m
//  hola-cdn-sdk
//
//  Created by alexeym on 28/07/16.
//  Copyright © 2016 hola. All rights reserved.
//

#import "hola_hls_parser.h"
#import "hola_log.h"
#import "hola_cdn_loader_delegate.h"

@interface HolaHLSParser()
{

NSMutableArray<HolaHLSLevelInfo*>* levels;
NSMutableArray<NSString*>* media_urls;
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

static HolaCDNLog* _log;

-(instancetype)init {
    self = [super init];

    if (self) {
        _log = [HolaCDNLog new];
        [_log setModule:@"parser"];

        levels = [NSMutableArray new];
        media_urls = [NSMutableArray new];
    }

    return self;
}

-(NSString*)parse:(NSString*)url andData:(NSString*)data withError:(NSError**)error {
    HolaHLSLevelInfo* level = [HolaHLSLevelInfo new];
    HolaHLSSegmentInfo* segment = [HolaHLSSegmentInfo new];

    HolaLevelState state = [self getUrlState:url];

    switch (state) {
    case HolaLevelStateTop:
        level = [HolaHLSLevelInfo new];
        break;
    case HolaLevelStateInner:
        level = [self getUrlLevel:url];
        break;
    }

    master = [NSURL URLWithString:url];

    if (![data hasPrefix:@"#EXTM3U"]) {
        *error = [NSError errorWithDomain:@"org.hola.hola-cdn-sdk" code:HolaHLSErrorHeader userInfo:nil];
        return nil;
    }

    NSCharacterSet *separator = [NSCharacterSet newlineCharacterSet];
    NSMutableArray<NSString*>* lines = [[data componentsSeparatedByCharactersInSet:separator] mutableCopy];
    lines = [lines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]].mutableCopy;
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

            NSRange toEnd = NSMakeRange(bwPos.location, line.length-bwPos.location);
            NSRange bwEnd = [line rangeOfString:@"," options:NSCaseInsensitiveSearch range:toEnd];
            if (bwEnd.location == NSNotFound) {
                level.bitrate = [NSNumber numberWithInt:[line substringFromIndex:bwPos.location+bwPos.length].intValue];
                continue;
            }

            NSRange toBwEnd = NSMakeRange(bwPos.location+bwPos.length+1, bwEnd.location - (bwPos.location+bwPos.length+1));
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

            NSRange toEnd = NSMakeRange(8, line.length-8);
            NSRange durEnd = [line rangeOfString:@"," options:NSCaseInsensitiveSearch range:toEnd];
            NSRange toDurEnd;
            if (durEnd.location == NSNotFound) {
                toDurEnd = toEnd;
            } else {
                toDurEnd = NSMakeRange(8, durEnd.location-8);
            }

            segment.duration = [NSNumber numberWithDouble:[line substringWithRange:toDurEnd].doubleValue];
            break;
        }
        case HolaHLSEntryUrl:
        {
            NSURL* levelUrl = [NSURL URLWithString:line relativeToURL:master];
            NSString* levelUrlString = levelUrl.absoluteString;

            NSURL* cdnLevelUrl;
            if (state == HolaLevelStateTop) {
                level.url = levelUrlString;
                [levels addObject:level];
                level = [HolaHLSLevelInfo new];
                cdnLevelUrl = [HolaCDNLoaderDelegate applyCDNScheme:levelUrl andType:HolaCDNSchemeFetch];
            } else {
                segment.url = levelUrlString;
                segment.level = level;
                [level.segments addObject:segment];
                [media_urls addObject:levelUrlString];
                segment = [HolaHLSSegmentInfo new];
                cdnLevelUrl = [HolaCDNLoaderDelegate applyCDNScheme:levelUrl andType:HolaCDNSchemeRedirect];
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

            NSRange keyPosEnd = NSMakeRange(keyPos.location+keyPos.length+1, line.length-(keyPos.location+keyPos.length+1));
            NSRange keyEnd = [line rangeOfString:@"\"" options:NSCaseInsensitiveSearch range:keyPosEnd];
            if (keyEnd.location == NSNotFound) {
                break;
            }

            NSRange keyRange = NSMakeRange(keyPosEnd.location, keyEnd.location-keyPosEnd.location);
            NSString* keyUrlString = [line substringWithRange:keyRange];
            NSURL* keyUrl = [NSURL URLWithString:keyUrlString relativeToURL:master];

            NSURL* customKeyUrl = [HolaCDNLoaderDelegate applyCDNScheme:keyUrl andType:HolaCDNSchemeKey];
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

-(BOOL)isMedia:(NSString*)url {
    return [media_urls containsObject:url];
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

    if (![entry hasPrefix:@"#"]) {
        return HolaHLSEntryUrl;
    }

    return HolaHLSEntryOther;
}

@end
