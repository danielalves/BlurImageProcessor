# BlurImageProcessor

[![Version](http://cocoapod-badges.herokuapp.com/v/BlurImageProcessor/badge.png)](http://cocoadocs.org/docsets/BlurImageProcessor)
[![Platform](http://cocoapod-badges.herokuapp.com/p/BlurImageProcessor/badge.png)](http://cocoadocs.org/docsets/BlurImageProcessor)

<p align="center">
    <img src="./blur-image-processor.gif" width="320" height="568"/>
</p>

ALDBlurImageProcessor offers a very easy and practical way to generate blurred images in real time. After an image
is specified to be targeted by it, every new blur operation will create a new allocated image. Varying the value of 
radiuses and iterations, its possible to create many different results and even animations.

Blur operations can be synchronous and asynchronous. Synchronous operations run on the thread/operation queue from which they were called. Each ALDBlurImageProcessor object has its own processing queue to run asynchronous operations, so it it easy to manage them. Besides that, all delegate callbacks and notifications are called/fired on the main thread, so there's no need to worry about using the new blurred images passed as parameters directly into the user interface.

ALDBlurImageProcessor tries to achieve a good balance between memory and performance. It also listens to 
UIApplicationDidReceiveMemoryWarningNotification notifications to clean temporary internal buffers on low memory conditions.

## Usage

To run the example project; clone the repo, and run `pod install` from the Example directory first.

## Requirements

iOS 6.0 or higher

## Installation

BlurImageProcessor is available through [CocoaPods](http://cocoapods.org), to install
it simply add the following line to your Podfile:

```ruby
pod "BlurImageProcessor"
```

## Author

- [Daniel L. Alves](http://github.com/danielalves) ([@alveslopesdan](https://twitter.com/alveslopesdan))

## Collaborators

- [Gustavo Barbosa](http://github.com/barbosa) ([@gustavocsb](https://twitter.com/gustavocsb))

## License

BlurImageProcessor is available under the MIT license. See the LICENSE file for more info.

