//
//  ViewController.m
//  hola-cdn-example-ios
//
//  Created by norlin on 24/01/2017.
//
//

#import "ViewController.h"
#import "hola_cdn_sdk.h"

@implementation ViewController

HolaCDN *cdn;
AVPlayer *player;
AVPlayerLayer *layer;

- (void)viewDidLoad {
    [super viewDidLoad];

    // turn on debug logging
    [HolaCDN setLogLevel:HolaCDNLogLevelDebug];

    // create a HolaCDN instance for specific customer
    cdn = [HolaCDN cdnWithCustomer:@"demo" usingZone:nil andMode:@"hola_cdn"];

    // set timeout to 5 sec (default is 2 sec)
    // in case if HolaCDN JS Library is not downloaded in this timeout, the video will start to play without HolaCDN
    // in that case, you may see WARN log messages similar to this one:
    // [WARN/Proxy:1] Trying to execute js: 'on_timeupdate'; no delegate found!
    [cdn setLoaderTimeout:5];

    // init player for specific video
    NSURL *url = [NSURL URLWithString:@"https://player.h-cdn.org/static/hls/cdn2/master.m3u8"];
    player = [cdn playerWithURL:url];
    [cdn attach:player];

    // add player to the view
    layer = [AVPlayerLayer playerLayerWithPlayer:player];
    [self.view.layer addSublayer:layer];

    // start playback
    [player play];
}

-(void)viewDidLayoutSubviews {
    // resize player layer to the view's bounds
    layer.frame = self.view.bounds;
}

@end
