#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# Create a 30-second video by generating and concatenating multiple 8-second clips
# -----------------------------------------------------------------------------

# Check for required arguments
if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <project-id> <gcs-bucket> <clip1-prompt> <clip2-prompt> <clip3-prompt> <clip4-prompt>"
    echo ""
    echo "Example:"
    echo "  $0 my-project gs://my-bucket \\"
    echo "     'A serene ocean at dawn, waves gently rolling' \\"
    echo "     'The sun rising over the horizon, golden light' \\"
    echo "     'Seagulls flying across the brightening sky' \\"
    echo "     'The beach coming alive with morning colors'"
    echo ""
    echo "This will generate 4 x 8-second clips and concatenate them into a 30-second video."
    echo "Dependencies: ffmpeg (for concatenation)"
    exit 1
fi

PROJECT_ID="$1"
GCS_BUCKET="$2"
CLIP1_PROMPT="$3"
CLIP2_PROMPT="$4"
CLIP3_PROMPT="$5"
CLIP4_PROMPT="$6"

# Check for ffmpeg
command -v ffmpeg >/dev/null 2>&1 || { 
    echo >&2 "Error: 'ffmpeg' is required for video concatenation."
    echo >&2 "Install with: brew install ffmpeg (macOS) or apt-get install ffmpeg (Linux)"
    exit 1
}

# Create output directory
OUTPUT_DIR="./30sec-output-$(date +%s)"
mkdir -p "$OUTPUT_DIR"

echo "=== Creating 30-Second Video ==="
echo "Project: $PROJECT_ID"
echo "GCS Bucket: $GCS_BUCKET"
echo "Output Directory: $OUTPUT_DIR"
echo ""
echo "Clip Prompts:"
echo "  1: $CLIP1_PROMPT"
echo "  2: $CLIP2_PROMPT"
echo "  3: $CLIP3_PROMPT"
echo "  4: $CLIP4_PROMPT"
echo ""

# Generate 4 clips (4 x 8 seconds = 32 seconds, we'll trim to 30)
CLIPS=()
# Create array with prompts (bash arrays are 0-indexed)
declare -a PROMPTS
PROMPTS[0]="$CLIP1_PROMPT"
PROMPTS[1]="$CLIP2_PROMPT"
PROMPTS[2]="$CLIP3_PROMPT"
PROMPTS[3]="$CLIP4_PROMPT"

for i in {1..4}; do
    echo "--- Generating Clip $i/4 ---"
    
    # Get the prompt for this clip (array is 0-indexed, so i-1)
    CLIP_PROMPT="${PROMPTS[$((i-1))]}"
    echo "Prompt: $CLIP_PROMPT"
    
    CLIP_FILE="$OUTPUT_DIR/clip_$i.mp4"
    
    ./veo-create.sh --project-id "$PROJECT_ID" --prompt "$CLIP_PROMPT" --output-uri "$GCS_BUCKET/30sec-project/clip-$i/" --download-to "$CLIP_FILE" --delete-after-download --duration 8 --aspect-ratio 16:9 --resolution 1080p --with-audio
    
    CLIPS+=("$CLIP_FILE")
    echo "✅ Clip $i complete: $CLIP_FILE"
    echo ""
done

# Create concat file for ffmpeg
CONCAT_FILE="$OUTPUT_DIR/concat_list.txt"
for clip in "${CLIPS[@]}"; do
    echo "file '$(basename "$clip")'" >> "$CONCAT_FILE"
done

echo "--- Concatenating clips ---"
TEMP_OUTPUT="$OUTPUT_DIR/concatenated_32sec.mp4"

# Concatenate all clips
cd "$OUTPUT_DIR"
ffmpeg -f concat -safe 0 -i concat_list.txt -c copy "$TEMP_OUTPUT" -y

# Trim to exactly 30 seconds
FINAL_OUTPUT="../video_30sec_$(date +%s).mp4"
ffmpeg -i "$TEMP_OUTPUT" -t 30 -c copy "$FINAL_OUTPUT" -y
cd ..

echo ""
echo "✅ 30-Second Video Complete!"
echo "Output: $FINAL_OUTPUT"
echo "Temporary files in: $OUTPUT_DIR"
echo ""
echo "To clean up temporary files, run: rm -rf $OUTPUT_DIR"

