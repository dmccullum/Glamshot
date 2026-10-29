# Glamshot

A Mac app that photographs webpages at device sizes and frames them for mockups.

- **Output size**: MacBook Air, MacBook Pro, iMac, Studio Display, 1080p, 1440p, iPad, iPhone, social sizes (1080 × 1080, 1080 × 1350, 1080 × 1920, 1920 × 1080), or your own width × height, at 1×, 2× or 3×. The saved image is that size; the window and backdrop take their room from it and the page gets the rest.
- **Page zoom**: 50–100%. At 80%, a page drawn in 1,000 points lays out like a 1,250-point browser window.
- **Capture**: one screen at the viewport size (for a laptop or phone mockup), or the full scrolling length of the page as one image. Elements sized from the viewport height, such as a 100vh hero, keep their on-screen height in a full-page capture.
- **Window**: none, or Safari-style window chrome drawn at Safari's real point size, in Light, Dark, or matched to the page.
- **Backdrop**: none (a transparent PNG with the window's shadow), a canvas with automatic or custom padding, or a Mac desktop with a menu bar and a window you can drag and resize. Canvas and desktop backgrounds are Undertone gradients, a color, or an image.
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
