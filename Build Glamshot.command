#!/bin/zsh
# Double-click in Finder to build build/Glamshot.app and open it.

set -u

ROOT="${0:A:h}"
APP="$ROOT/build/Glamshot.app"

pause_before_exit() {
    if [[ -t 0 ]]; then
        echo
        read -k 1 "?Press any key to close this window…"
        echo
    fi
}

fail() {
    echo
    echo "❌ Glamshot could not be built."
    echo "$1"
    pause_before_exit
    exit 1
}

cd "$ROOT" || fail "The Glamshot source folder could not be opened."

if ! /usr/bin/xcrun --find actool >/dev/null 2>&1; then
    fail "Install the full Xcode application, open it once, and try again. The icon needs its actool."
fi

# Quit a running copy so the new build replaces it cleanly.
if pgrep -xq Glamshot; then
    osascript -e 'quit app "Glamshot"'
    while pgrep -xq Glamshot; do sleep 0.2; done
fi

if ! zsh "$ROOT/Scripts/build-app.sh"; then
    fail "See the build output above for details."
fi

echo
echo "✅ Built $APP"
/usr/bin/open "$APP"
pause_before_exit
