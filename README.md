# HolaCDN.framework

This document describes integration of a native iOS app to HolaCDN

## Requirements

iOS version 8+ required.

At the moment, HolaCDN works only with `AVPlayer`+`AVURLAsset`+HLS videos.

Custom `AVAssetResourceLoaderDelegate` is not yet supported.

## Install

### Manually

- Download the latest [release](https://github.com/hola/ios_sdk/releases)

- Add hola_cdn.xcodeproj into your project

- In your Target, click + in `Linked Frameworks and Libraries`, add `HolaCDN.framework`

### via Carthage

- Install [Carthage](https://github.com/Carthage/Carthage#installing-carthage)

- Add `github "hola/ios_sdk" ~> 1.1` to your Cartfile

- Run `$ carthage update` and add the generated frameworks to your Xcode projects (see [Carthage instructions](https://github.com/Carthage/Carthage#adding-frameworks-to-an-application)).

### via CocoaPods

- Will be available later

## Initialization

- Create a new instance of `HolaCDN`

```swift
let cdn = HolaCDN()
```

- Call the config method with desired parameters
  - `customer`: String – required parameter, your customerId
  - `zone`: String? – optional parameter to force zone selection. In case of `nil` will be selected automatically according to your customer's HolaCDN config
  - `mode`: String? – optional parameter to force cdn mode selection. In case of `nil` will be selected automatically according to your customer's HolaCDN config; supported options are: `nil`, `"stats"`, `"cdn"`.

```swift
cdn.config(customer: "your_customer_id")
```

- Create a class which conforms to `HolaCDNDelegate` protocol to
handle some HolaCDN callbacks:

```swift
protocol HolaCDNDelegate: NSObjectProtocol {
    optional func cdnDidLoaded(cdn: HolaCDN) -> Void
    optional func cdnDidAttached(cdn: HolaCDN) -> Void
    optional func cdnDidDetached(cdn: HolaCDN) -> Void
    optional func cdnStateChanged(cdn: HolaCDN, state: String) -> Void
    optional func cdnExceptionOccured(cdn: HolaCDN, error: JSValue) -> Void
}
```

- Set the delegate and call `load` method

```swift
// in case if you have implemented the protocol for the current ViewController
cdn.delegate = self
try! cdn.load() // could throw an error in case if no "customerId" provided with cdn.config method
```

- Loading occurs asynchronically. During that process some delegate
methods could be called:

  - `cdnDidLoaded(cdn: HolaCDN) -> Void`: when HolaCDN code is loaded & inited
  - `cdnExceptionOccured(cdn: HolaCDN, error: JSValue) -> Void`:
when something goes wrong while executing HolaCDN code

- How to check `HolaCDN` state:

  - `cdn.get_mode()`: String – returns current cdn mode:

    - `"loading"` – CDN js code is loading
    - `"detached"` – CDN is loaded, not attached to a player
    - `"disabled"` – CDN is in automatic mode and disabled for current config
    - `"stats"` – CDN is attached and working in stats-only mode
    - `"cdn"` – CDN is attached and working in cdn mode

## Attach

Attachment is required to activate HolaCDN features. Example:

```swift
let myAVPlayer = AVPlayer(URL: url)
cdn.attach(myAVPlayer)
```

`myAVPlayer` instance can be used as a regular AVPlayer object.

## Example

### Swift

```swift
import HolaCDN

class PlayerViewController: AVPlayerViewController, HolaCDNDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        let cdn = HolaCDN()
        cdn.config(customer: "demo", zone: nil, mode: "cdn")
        cdn.delegate = self

        let url = NSURL(string: "https://example.com/your/video.m3u8")!
        self.player = AVPlayer(URL: url)

        try! cdn.load()
    }

    func cdnDidLoaded(cdn: HolaCDN) {
        NSLog("cdn did loaded")

        cdn.attach(self.player!)
    }

    func cdnDidAttached(cdn: HolaCDN) {
        NSLog("cdn did attached! \(cdn.get_mode())")
    }
}
```

### Objective-C

```objc
@import HolaCDN;

@implementation PlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    HolaCDN *cdn = [[HolaCDN alloc] init];
    [cdn setDelegate:self];
    [cdn config:@"demo" zone:nil mode:@"cdn"];

    NSURL *url = [NSURL URLWithString:@"https://example.com/your/video.m3u8"];
    self.player = [AVPlayer playerWithURL:url];

    NSError *err = [NSError alloc];
    [cdn loadAndReturnError:&err];
}

-(void)cdnDidLoaded:(HolaCDN *)cdn {
    [cdn attach:[self playerTmp]];
}

-(void)cdnDidAttached:(HolaCDN *)cdn {
    NSLog(@"cdn did attached! %@", [cdn get_mode]);
}

@end
```
