#!/bin/bash

# ---
# A script to extract the *exact* last frame of a video file.
#
# This script uses the "Method B" approach:
# 1. Use ffprobe to get the total number of frames.
# 2. Use ffmpeg's 'select' filter to extract the very last frame by its index.
#
# Usage:
# 1. Make the script executable: chmod +x extract_last_frame.sh
# 2. Run it with your video: ./extract_last_frame.sh /path/to/your/video.mp4
# ---

set -e

# --- 1. Dependency Check ---
# We check for both ffmpeg (for extraction) and ffprobe (for frame counting).
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: 'ffmpeg' is not installed or not in your PATH." >&2
    echo "Please install ffmpeg to use this script." >&2
    exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
    echo "Error: 'ffprobe' is not installed or not in your PATH." >&2
    echo "(ffprobe is usually included with the ffmpeg package)" >&2
    echo "Please install ffmpeg to use this script." >&2
    exit 1
fi

# --- 2. Input Validation ---
if [ -z "$1" ]; then
    echo "Usage: $0 <video_file>" >&2
    echo "Example: $0 my_video.mp4" >&2
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File not found at '$INPUT_FILE'" >&2
    exit 1
fi

# --- 3. Define Output Filename ---
# Creates a filename like "my_video_last_frame.png"
FILENAME=$(basename -- "$INPUT_FILE")
FILENAME_NO_EXT="${FILENAME%.*}"
OUTPUT_FILE="${FILENAME_NO_EXT}_last_frame.png"

echo "Input video: $INPUT_FILE"

# --- 4. Get Total Frame Count (Step 1 from Method B) ---
echo "Probing video file to find total frame count..."
# This command asks ffprobe for the video stream (v:0), tells it to count frames,
# and formats the output to show *only* the number of frames.
TOTAL_FRAMES=$(ffprobe -v error \
                         -select_streams v:0 \
                         -count_frames \
                         -show_entries stream=nb_read_frames \
                         -of default=nokey=1:noprint_wrappers=1 \
                         "$INPUT_FILE")

if [ -z "$TOTAL_FRAMES" ] || ! [[ "$TOTAL_FRAMES" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not determine total frame count for '$INPUT_FILE'." >&2
    echo "The file may be corrupt or not a valid video file." >&2
    exit 1
fi

# --- 5. Calculate Last Frame Index (Step 2 from Method B) ---
# Frames are 0-indexed, so we subtract 1 from the total count.
LAST_FRAME_INDEX=$(($TOTAL_FRAMES - 1))

echo "Total frames found: $TOTAL_FRAMES"
echo "Targeting last frame index: $LAST_FRAME_INDEX"

# --- 6. Extract the Frame (Step 3 from Method B) ---
echo "Extracting frame... (This may be slow for long videos)"

# -vf "select=eq(n\,$LAST_FRAME_INDEX)"
#   -vf means "video filter"
#   'select=' is the filter name
#   'eq(n\,$LAST_FRAME_INDEX)' selects the frame where the frame number (n)
#   is equal to our calculated index. The comma (,) is escaped with a backslash (\)
#   so the bash shell doesn't misinterpret it.
#
# -vframes 1
#   Tells ffmpeg to output only one frame.
ffmpeg -i "$INPUT_FILE" -vf "select=eq(n\,$LAST_FRAME_INDEX)" -vframes 1 "$OUTPUT_FILE"

echo ""
echo "Success! Last frame saved to:"
echo "$OUTPUT_FILE"
