# Inspector design explorations

`inspector-mockups.html` shows the inspector as it was, then three redesign directions from an
Opus design review:

- **A**: the same four cards with labels in a left column and half the rows. Not built.
- **B**: one frame picker (Page, Safari, Canvas, Desktop tiles) with only that frame's controls below.
  Chosen; this is `main`.
- **C**: the canvas does the framing. A floating bar picks the frame and background, clicking the
  backdrop or window selects it and the inspector follows, and padding is dragged on the canvas.
  Built as a working prototype and kept on the `exploration/direction-c` branch (commit `8573eac`),
  branched from `main` at `721162b`. It predates the iOS 27 iPhone frame, the Share button and
  the even-padding change, so revisiting it means rebasing onto `main`.

To try C: `git worktree add ../Glamshot-c exploration/direction-c`, then build there with
`Scripts/build-app.sh` (DMKit and Undertone must resolve as `../DMKit` and `../Undertone` from that folder).
