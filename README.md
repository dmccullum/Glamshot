# Glamshot

A Mac app that photographs webpages at device sizes and frames them for mockups.

- **Sizes**: MacBook Air, MacBook Pro, iMac, Studio Display, 1080p, 1440p, iPad, iPhone, or your own width × height, at 1×, 2× or 3×.
- **Capture**: one screen at the viewport size (for a laptop or phone mockup), or the full scrolling length of the page as one image. Elements sized from the viewport height, such as a 100vh hero, keep their on-screen height in a full-page capture.
- **Window**: none, or Safari-style window chrome drawn at Safari's real point size, in Light, Dark, or matched to the page.
- **Backdrop**: none (a transparent PNG with the window's shadow), a canvas with padding, aspect ratio (16:9, 3:2, 4:3, 1:1, 4:5, 9:16) and alignment, or a Mac desktop with a menu bar. Canvas and desktop backgrounds are Undertone gradients, a color, or an image.
- **Looks**: saved combinations of window, backdrop and background, picked with ⌥⌘1 and up.
- **Output**: PNG, JPEG or HEIC. Save (⌘S), copy (⌘C), drag out of the window, or export every checked size at once (⇧⌘E).

The page in the window is live: sign in, dismiss banners and scroll before you save, and the image shows what you see.

## Building

Requires macOS 26 and Xcode 26 or later. Glamshot depends on [DMKit](../DMKit) and [Undertone](https://github.com/dmccullum/Undertone)'s `UndertoneKit`, checked out next to this repository.

```sh
swift build
swift test
Scripts/build-app.sh && open build/Glamshot.app
build/Glamshot.app/Contents/MacOS/Glamshot --self-test Tests/Fixtures   # photographs the fixture pages and checks pixels
```

Or double-click `Build Glamshot.command`.

## License

GPL-3.0. See [LICENSE](LICENSE).
