#!/usr/bin/env bash
# Push-to-talk toggle: run once to start recording, run again to transcribe.
# Bind to a key in your Niri config for hands-free dictation.

MODEL="$HOME/Projects/whisper/models/ggml-base.bin"
WHISPER="whisper-cli"
PIDFILE="/tmp/whisper-ptt.pid"
WAVFILE="/tmp/whisper-ptt.wav"

notify() {
    notify-send -a "Whisper" -h string:x-canonical-private-synchronous:whisper "$@"
}

start_recording() {
    # Set default mic
    pactl set-default-source alsa_input.pci-0000_07_00.6.HiFi__hw_acp__source 2>/dev/null

    arecord -f cd -t wav "$WAVFILE" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"

    notify "Recording..." "Press key again to transcribe"
}

stop_and_transcribe() {
    local pid
    pid=$(cat "$PIDFILE")
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -f "$PIDFILE"

    if [ ! -f "$WAVFILE" ]; then
        notify "Error" "No recording found"
        exit 1
    fi

    notify "Transcribing..." ""

    local text
    text=$($WHISPER -m "$MODEL" -f "$WAVFILE" -nt -np 2>&1)
    rm -f "$WAVFILE"

    if [ -z "$text" ] || [[ "$text" == *"BLANK_AUDIO"* ]]; then
        notify "Error" "No speech detected"
        exit 1
    fi

    echo -n "$text" | wl-copy
    notify "Copied to clipboard" "$text"
}

# Check model exists
if [ ! -f "$MODEL" ]; then
    notify "Error" "Model not found at $MODEL"
    exit 1
fi

# Toggle: if pidfile exists and process is alive, stop. Otherwise, start.
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    stop_and_transcribe
else
    # Clean up stale pidfile/wav if process died
    rm -f "$PIDFILE" "$WAVFILE"
    start_recording
fi
