# HolaCDN.framework

This document describes integration of a native iOS app to HolaCDN.

## Requirements

iOS 7+ or tvOS 9+ required.

At the moment, HolaCDN works with `AVPlayer` or `AVQueuePlayer`, only with `AVURLAsset`+HLS videos. Custom `AVAssetResourceLoaderDelegate` is not yet supported (coming soon).

Note: An [Android version](https://github.com/hola/android_sdk) is also available.

If you have any questions, email us at cdnsupport@hola.org, or skype: holacdn

## Install

### Manually

- Download the latest [release](https://github.com/hola/ios_sdk/releases)

- Add hola-cdn-sdk.xcodeproj into your project

- In your Target, click + in `Linked Frameworks and Libraries`, add `libHolaCDN.a`

### via CocoaPods

- Add the pod into your Podfile:

```
pod "HolaCDN", "~> 1.3.0" # HolaCDN API has been changed from 1.2.x versions
```

- Run `$ pod install`

- For any questions about CocoaPods usage, please check [their documentation](http://cocoapods.org/)

## Initialization

- Create a new instance of `HolaCDN` with desired parameters
  - `customer`: String - required parameter, your customerId
  - `zone`: String? - optional parameter to force zone selection. In case of `nil` will be selected automatically according to your customer's HolaCDN config
  - `mode`: String? - optional parameter to force cdn mode selection. In case of `nil` will be selected automatically according to your customer's HolaCDN config; supported options are: `nil`, `"origin_cdn"`, `"hola_cdn"`.


```swift
let cdn = HolaCDN(customer: "your_customer_id", usingZone: nil, andMode: "hola_cdn")
```

- (optional) You may set a timeout for loading HolaLibrary and assets

```
// In case if timeout reached while HolaLibrary loading, HolaCDN SDK will use saved version.
// In case if timeout reached while asset loading, it will play without HolaCDN (not to make you wait).
cdn.loaderTimeout = 5.0 // in seconds; by default: 2.0
```

- HolaLibrary loading occurs automatically and asynchronically

During that process some delegate methods could be called:

  - `cdnDidLoaded(cdn: HolaCDN) -> Void`: when HolaCDN code is loaded & inited
  - `cdnExceptionOccured(cdn: HolaCDN, withError: NSError) -> Void`:
when something goes wrong while executing HolaCDN code

- How to check `HolaCDN` state:

  - `cdn.get_mode(completionBlock: (String?) -> Void)`: Async method, returns current cdn mode into completionBlock:

    - `"loading"` - CDN js code is loading
    - `"detached"` - CDN is loaded, not attached to a player
    - `"disabled"` - CDN is in automatic mode and disabled for current config
    - `"origin_cdn"` - CDN is attached and working in Origin CDN mode
    - `"hola_cdn"` - CDN is attached and working in HolaCDN mode

  - via Safari inspector:
    - Enable Safari developer mode in the preferences
    - Run your app in a Simulator or connected device
      - To enable this option in your device, look into Settings -> Safari -> Advanced -> Web-inspector
    - Find the app in Safari -> Develop -> Simulator (or the device name) menu
    - in the dev tools console, run `hola_cdn.get_stats()`
      - you should see detailed cdn stats at the moment
      - if you see `undefined` - it means cdn is not working properly

- (optional) You may create a class which conforms to `HolaCDNDelegate` protocol to
handle some HolaCDN callbacks:

```swift
protocol HolaCDNDelegate: NSObjectProtocol {
    optional func cdnDidLoaded(cdn: HolaCDN) -> Void
    optional func cdnDidAttached(cdn: HolaCDN) -> Void
    optional func cdnDidDetached(cdn: HolaCDN) -> Void
    optional func cdnStateChanged(cdn: HolaCDN, toState state: String) -> Void
    optional func cdnExceptionOccured(cdn: HolaCDN, withError: NSError) -> Void
}
```

- (optional) Set the delegate

```swift
// in case if you have implemented the protocol for the current ViewController
cdn.delegate = self
```

## Create a player or player item

There are multiple ways to attach your video to HolaCDN

```swift
let url = NSURL("https://example.com/your/video.m3u8")

let myPlayer = cdn.playerWithURL(url)
cdn.attach(myPlayer)
```

or

```swift
var myPlayer = AVPlayer()
myPlayer = cdn.attach(myPlayer)

let item = cdn.playerItemWithURL(url)
myPlayer.replaceCurrentItemWithPlayerItem(item)

```

or similar methods for AVQueuePlayer:

```swift
let myPlayer1 = cdn.queuePlayerWithURL(url)
```

```swift
let item1 = AVPlayerItem(URL: url)
let item2 = AVPlayerItem(URL: url2)
let myPlayer2 = cdn.queuePlayerWithItems([item1, item2])
```

## Example

### Swift

```swift
import HolaCDN

class PlayerViewController: AVPlayerViewController, HolaCDNDelegate {
    var cdn: HolaCDN!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        cdn = HolaCDN(customer: "demo", usingZone: nil, andMode: "hola_cdn")
        cdn.delegate = self

        let url = NSURL(string: "https://example.com/your/video.m3u8")!
        self.player = cdn.playerWithURL(url)
        cdn.attach(self.player)
    }

    func cdnDidLoaded(cdn: HolaCDN) {
        NSLog("cdn did loaded")
    }

    func cdnDidAttached(cdn: HolaCDN) {
        NSLog("cdn did attached! \(cdn.get_mode())")
    }
}
```

### Objective-C

```objc
#import "hola_cdn_sdk.h"

@implementation PlayerViewController

HolaCDN* cdn;
AVPlayer* player;

- (void)viewDidLoad {
    [super viewDidLoad];

    cdn = [HolaCDN cdnWithCustomer:@"demo" usingZone:nil andMode:@"hola_cdn"];
    [cdn setDelegate:self]; // Your delegate class should be compatible with HolaCDNDelegate

    NSURL *url = [NSURL URLWithString:@"https://example.com/your/video.m3u8"];
    player = [cdn playerWithURL:url];
    [cdn attach:player];
}

-(void)cdnDidLoaded:(HolaCDN *)cdn {
    NSLog(@"cdn did loaded!");
}

-(void)cdnDidAttached:(HolaCDN *)cdn {
    [cdn get_mode:^(NSString *mode) {
        NSLog(@"cdn did attached! %@", mode);
    }];
}

@end
```
## Logs

HolaCDN logs has own format: `[LEVEL/module:instance_id] message`

```
[INFO/cdn:1] New HolaCDN instance created
[INFO/cdn:1] Loading...
[INFO/cdn:1] Attach
[INFO/Item:1] Init
[INFO/Item:2] Init
[WARN/Proxy:1] getDelegate: delegate is undefined
[WARN/Proxy:1] Trying to execute js: 'on_play'; no delegate found!
[INFO/cdn:1] Use fresh-loaded HolaCDN library
[INFO/Proxy:1] HolaCDN attaching...
[INFO/Proxy:2] HolaCDN attaching...
[INFO/cdn:1] Loaded
```

You can choose required level by calling this method:

```swift
HolaCDN.setLogLevel(.Debug) // Possible values are: .None, .Debug, .Info, .Warning, .Error, .Critical
```

And set modules available to output:

```swift
HolaCDN.setLogModules([]) // defaut value, all modules
HolaCDN.setLogModules(["cdn", "loader", "network"]) // main HolaCDN logs, HolaCDNLoaderDelegate delegate logs and networking logs
```

The `instance_id` is useful when you're using `AVQueuePlayer` with multiple assets – then you can filter logs by it using XCode filter field.
For example, filter by `:2]` will shows you logs for the second asset and related HolaCDN modules.
