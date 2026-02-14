#!/usr/bin/env bash
# Simple speech-to-text script using whisper.cpp

MODEL="$HOME/Projects/whisper/models/ggml-base.bin"
WHISPER="whisper-cli"

# Use the built-in DMIC by default
pactl set-default-source alsa_input.pci-0000_07_00.6.HiFi__hw_acp__source 2>/dev/null

# Function to copy to clipboard
copy_to_clipboard() {
    local text="$1"

    # Try wl-copy (Wayland)
    if command -v wl-copy >/dev/null 2>&1; then
        echo -n "$text" | wl-copy
        return 0
    fi

    # Try xclip (X11)
    if command -v xclip >/dev/null 2>&1; then
        echo -n "$text" | xclip -selection clipboard
        return 0
    fi

    # Try xsel (X11)
    if command -v xsel >/dev/null 2>&1; then
        echo -n "$text" | xsel --clipboard --input
        return 0
    fi

    echo "Warning: No clipboard utility found (install xclip, xsel, or wl-clipboard)"
    return 1
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f FILE      Transcribe audio file"
    echo "  -r SECONDS   Record from mic for N seconds and transcribe"
    echo "  -l           List available recording devices"
    echo "  -h           Show this help"
    echo ""
    echo "Default: Record until 'q' is pressed"
    echo ""
    echo "Examples:"
    echo "  $0                   # Record until 'q' pressed"
    echo "  $0 -r 5              # Record 5 seconds and transcribe"
    echo "  $0 -f audio.wav      # Transcribe existing file"
    echo "  $0 -l                # List microphones"
}

# List recording devices
list_devices() {
    echo "Available recording devices:"
    arecord -l
}

# Record until key press
record_until_keypress() {
    local tmpfile="/tmp/whisper-recording-$$.wav"

    echo "Recording... Press 'q' to stop."

    # Start recording in background (use system default device)
    arecord -f cd -t wav "$tmpfile" >/dev/null 2>&1 &
    local record_pid=$!

    # Wait for 'q' key press
    while true; do
        read -n 1 -s key
        if [ "$key" = "q" ]; then
            break
        fi
    done

    # Stop recording
    kill $record_pid 2>/dev/null
    wait $record_pid 2>/dev/null

    echo "Transcribing..."
    TRANSCRIPTION=$($WHISPER -m "$MODEL" -f "$tmpfile" -nt -np 2>&1)
    rm -f "$tmpfile"

    if [ -z "$TRANSCRIPTION" ] || [[ "$TRANSCRIPTION" == *"BLANK_AUDIO"* ]]; then
        echo "Error: No audio detected"
        exit 1
    fi

    echo ""
    echo "$TRANSCRIPTION"
    echo ""

    # Copy to clipboard
    if copy_to_clipboard "$TRANSCRIPTION"; then
        echo "[Copied to clipboard]"
    fi
}

# Record and transcribe
record_and_transcribe() {
    local duration="${1:-10}"
    local tmpfile="/tmp/whisper-recording-$$.wav"

    echo "Recording for $duration seconds..."
    arecord -d "$duration" -f cd -t wav "$tmpfile" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "Transcribing..."
        TRANSCRIPTION=$($WHISPER -m "$MODEL" -f "$tmpfile" -nt -np 2>&1)
        rm -f "$tmpfile"

        if [ -z "$TRANSCRIPTION" ] || [[ "$TRANSCRIPTION" == *"BLANK_AUDIO"* ]]; then
            echo "Error: No audio detected"
            exit 1
        fi

        echo ""
        echo "$TRANSCRIPTION"
        echo ""

        # Copy to clipboard
        if copy_to_clipboard "$TRANSCRIPTION"; then
            echo "[Copied to clipboard]"
        fi
    else
        echo "Error: Recording failed"
        exit 1
    fi
}

# Transcribe file
transcribe_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "Error: File '$file' not found"
        exit 1
    fi

    echo "Transcribing $file..."
    TRANSCRIPTION=$($WHISPER -m "$MODEL" -f "$file" -nt -np 2>&1)

    if [ -z "$TRANSCRIPTION" ] || [[ "$TRANSCRIPTION" == *"BLANK_AUDIO"* ]]; then
        echo "Error: No audio detected"
        exit 1
    fi

    echo ""
    echo "$TRANSCRIPTION"
    echo ""

    # Copy to clipboard
    if copy_to_clipboard "$TRANSCRIPTION"; then
        echo "[Copied to clipboard]"
    fi
}

# Check if model exists
if [ ! -f "$MODEL" ]; then
    echo "Error: Model not found at $MODEL"
    exit 1
fi

# Parse arguments
if [ $# -eq 0 ]; then
    # Default: record until 'q' is pressed
    record_until_keypress
    exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            list_devices
            exit 0
            ;;
        -r|--record)
            shift
            record_and_transcribe "${1:-10}"
            exit 0
            ;;
        -f|--file)
            shift
            transcribe_file "$1"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done
