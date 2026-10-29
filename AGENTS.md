# Agent instructions for Glamshot

Glamshot is one of the family of Mac apps whose standard is `../DMKit/FAMILY.md`. Read it before changing any UI and cite its rules (F1–F16) in commits. Use DMKit's components (`InspectorCard`, `InspectorSlider`, `FilledSegments`, `StatusCapsule`, `AboutScene`, `FamilyHelpCommands`, `UndoCommands`, `DropTarget`) instead of local copies.

## Build and verify

```sh
swift build
swift test                                    # layout, naming and option logic
Scripts/build-app.sh && open build/Glamshot.app
build/Glamshot.app/Contents/MacOS/Glamshot --self-test Tests/Fixtures
```

The self-test photographs the pages in `Tests/Fixtures` inside the real app (WebKit won't run under `swift test`) and checks image sizes and pixel colors at 1×, 2× and 3×. Run it after any change to `PagePhotographer`.

A UI change is not done until you have launched the packaged app, exercised the change, and looked at the window and the menu bar.

## Rules specific to Glamshot

- **Preview/export parity.** The canvas and the exported image are drawn by the same `ShotView`. Never draw a preview-only approximation of chrome or a backdrop.
- **Chrome is drawn at real point size** (`ChromeMetrics`) times the capture scale. Never scale it to the page.
- `GlamshotCore` holds models, layout math and capture; it stays free of SwiftUI and gets unit tests for new logic.
