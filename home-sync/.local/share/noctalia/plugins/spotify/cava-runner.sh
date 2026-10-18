#!/bin/sh
# Managed cava runner for the gery/spotify Noctalia plugin.
#
#   cava-runner.sh <cava-binary> <cava-config> <control-file> <session-PATH>
#
# Runs for the whole session as a single Noctalia `runStream` child (runStream
# has no stop API). It keeps cava alive only while the control file reads "1",
# so the plugin can start/stop the visualizer — and its audio capture — by
# writing to that file. cava's stdout is inherited, so its raw ASCII frames flow
# straight back up the runStream pipe to the plugin service.
#
# Noctalia spawns plugin subprocesses without the session PATH, so the caller
# passes it in; cava itself is already an absolute path.
#
# No `exec`: the loop must outlive each cava invocation. The trap reaps cava
# when Noctalia tears the stream down (reload/remove/stop).

cava="$1"
conf="$2"
ctrl="$3"
session_path="$4"

if [ -n "$session_path" ]; then
    export PATH="$session_path"
fi

pid=""

stop() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
    fi
    exit 0
}
trap stop INT TERM

[ -n "$ctrl" ] || exit 1
mkdir -p "$(dirname "$ctrl")" 2>/dev/null || true

while :; do
    want="0"
    if [ -r "$ctrl" ]; then
        want=$(cat "$ctrl" 2>/dev/null)
    fi

    if [ "$want" = "1" ]; then
        if [ -z "$pid" ]; then
            "$cava" -p "$conf" &
            pid=$!
        fi
    else
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            pid=""
        fi
    fi

    # Reap cava if it died on its own (bad config, no PipeWire, ...).
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        pid=""
    fi

    sleep 0.5
done
