# HolaCDN.framework

This document describes integration of a native iOS app to HolaCDN

## Initialization

- Include `HolaCDN.framework` to your project.

- Create a new instance of `HolaCDN` with your customer id as
a parameter and call `load` method. Example:

```swift
let cdn = HolaCDN(customer: "demo")
cdn.load()
```

- You can create a class which conforms to `HolaCDNDelegate` protocol to
handling some HolaCDN callbacks:

```swift
protocol HolaCDNDelegate: NSObjectProtocol {
    optional func cdnDidLoaded(cdn: HolaCDN) -> Void
    optional func cdnDidAttached(cdn: HolaCDN) -> Void
    optional func cdnDidDetached(cdn: HolaCDN) -> Void
    optional func cdnStateChanged(cdn: HolaCDN, state: String) -> Void
    optional func cdnExceptionOccured(cdn: HolaCDN, error: JSValue) -> Void
}
```

- Loading occurs asynchronically. During that process some delegate
methods could be called:

  - `cdnDidLoaded(cdn: HolaCDN) -> Void`: when HolaCDN code is loaded & inited
  - `cdnExceptionOccured(cdn: HolaCDN, error: JSValue) -> Void`:
when something goes wrong while executing HolaCDN code

- How to check `HolaCDN` state:

  - `cdn.ready`: Bool - returns true if service is inited
  - `cdn.attached`: Bool – returns true if service exists and the wrapper
  is attached to AVPlayer

## Attach

Attachment is required to activate HolaCDN features. At the moment, cdn mode
for `AVPlayer` object is functional in stats-only mode. Example:

```swift
let myAVPlayer = AVPlayer(URL: url)
cdn.attach(myAVPlayer)
```

`myAVPlayer` instance can be used as a regular AVPlayer object.

## Example

```swift
class PlayerViewController: AVPlayerViewController, HolaCDNDelegate {
    let urlString = "https://example.com/your/video.m3u8"
    lazy var cdn = HolaCDN(customer: "demo")

    override func viewDidLoad() {
        super.viewDidLoad()

        cdn.delegate = self

        let url = NSURL(string: urlString)!
        self.player = AVPlayer(URL: url)

        cdn.load()
    }

    func cdnDidLoaded(cdn: HolaCDN) {
        NSLog("cdn did loaded")

        cdn.attach(self.player!)
    }
}
```
