#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# Veo 3.1 Video Generation Script (Vertex AI)
# -----------------------------------------------------------------------------

# Default configurations
LOCATION="us-central1"
MODEL_VERSION="veo-3.1-generate-preview"
ASPECT_RATIO="16:9"
DURATION="8"
RESOLUTION="1080p"
WITH_AUDIO="false"
SAMPLE_COUNT=1
PROJECT_ID=""
OUTPUT_GCS_URI=""
PROMPT=""
NEGATIVE_PROMPT=""
INPUT_IMAGE=""
LAST_IMAGE=""
PERSON_GENERATION="allow_all"
DOWNLOAD_PATH="" # New flag: Local path to download to
DELETE_AFTER_DOWNLOAD="false" # New flag: Delete from GCS after download

# Function to print help message
function show_help {
    echo "Usage: $(basename "$0") --project-id PROJECT_ID --prompt 'Your text prompt' [OPTIONS]"
    echo ""
    echo "Required Arguments:"
    echo "  --project-id <id>     Your Google Cloud Project ID."
    echo "  --prompt <text>       The text prompt for video generation."
    echo ""
    echo "Optional Arguments:"
    echo "  --model <name>        Model version (default: $MODEL_VERSION)."
    echo "  --location <region>   Vertex AI region (default: $LOCATION)."
    echo "  --output-uri <gs://>   Google Cloud Storage URI for saving results (required for download)."
    echo "  --download-to <path>  Polls for completion and downloads the file from GCS to a local path."
    echo "  --delete-after-download Delete the video from GCS after successful download."
    echo "  --aspect-ratio <ratio> Video aspect ratio: '16:9' (default), '9:16', '1:1', etc."
    echo "  --duration <seconds>  Video duration in seconds: 4, 6, or 8 (default: $DURATION)."
    echo "  --resolution <res>    Resolution: '720p' or '1080p' (default: $RESOLUTION)."
    echo "  --with-audio          Include this flag to generate matched audio."
    echo "  --seed <int>          Integer seed for deterministic generation."
    echo "  --image <path/uri>    Local file path or gs:// URI for Image-to-Video mode (e.g., image.png)."
    echo "  --lastimage <path/uri> Final image for interpolation video transition (requires --image)."
    echo "  --negative-prompt <text> What NOT to include in the video generation."
    echo "  --person-generation <policy> Person generation policy: 'allow_all' (default), 'allow_adult', 'dont_allow'."
    echo "  --help                Show this help message."
    echo ""
    echo "Dependencies: gcloud, gsutil, jq, curl"
    exit 1
}

# Check for dependencies
command -v gcloud >/dev/null 2>&1 || { echo >&2 "Error: 'gcloud' CLI is required."; exit 1; }
command -v gsutil >/dev/null 2>&1 || { echo >&2 "Error: 'gsutil' is required for the --download-to option."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "Error: 'jq' is required for JSON processing."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "Error: 'curl' is required."; exit 1; }

# Argument Parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --project-id) PROJECT_ID="$2"; shift ;;
        --location) LOCATION="$2"; shift ;;
        --model) MODEL_VERSION="$2"; shift ;;
        --prompt) PROMPT="$2"; shift ;;
        --negative-prompt) NEGATIVE_PROMPT="$2"; shift ;;
        --output-uri) OUTPUT_GCS_URI="$2"; shift ;;
        --download-to) DOWNLOAD_PATH="$2"; shift ;;
        --delete-after-download) DELETE_AFTER_DOWNLOAD="true" ;;
        --aspect-ratio) ASPECT_RATIO="$2"; shift ;;
        --duration) DURATION="$2"; shift ;;
        --resolution) RESOLUTION="$2"; shift ;;
        --seed) SEED="$2"; shift ;;
        --with-audio) WITH_AUDIO="true" ;;
        --image) INPUT_IMAGE="$2"; shift ;;
        --lastimage) LAST_IMAGE="$2"; shift ;;
        --person-generation) PERSON_GENERATION="$2"; shift ;;
        --help|-h) show_help ;;
        *) echo "Unknown parameter passed: $1"; show_help ;;
    esac
    shift
done

# Validation
if [ -z "$PROJECT_ID" ] || [ -z "$PROMPT" ]; then
    echo "Error: Missing required arguments (--project-id and --prompt)."
    show_help
fi

# New Validation: --download-to requires --output-uri
if [ ! -z "$DOWNLOAD_PATH" ] && [ -z "$OUTPUT_GCS_URI" ]; then
    echo "Error: --download-to requires --output-uri to be set."
    echo "Please provide a GCS path like --output-uri gs://my-bucket/video.mp4"
    exit 1
fi

# Validation: --lastimage requires --image
if [ ! -z "$LAST_IMAGE" ] && [ -z "$INPUT_IMAGE" ]; then
    echo "Error: --lastimage requires --image to be set."
    echo "The --lastimage parameter is used for interpolation videos and must be combined with --image."
    exit 1
fi

# Detect Image Input Mode
IMAGE_JSON_PART=""
if [ ! -z "$INPUT_IMAGE" ]; then
    if [[ "$INPUT_IMAGE" == gs://* ]]; then
        # GCS URI
        IMAGE_JSON_PART=$(jq -n --arg uri "$INPUT_IMAGE" '{image: {gcsUri: $uri}}')
    elif [ -f "$INPUT_IMAGE" ]; then
        # Local File (base64 encode)
        echo "Encoding local image..."
        # Note: 'base64 -i <file>' is the macOS syntax.
        # For Linux, use 'base64 -w 0 <file>'
        if [[ "$OSTYPE" == "darwin"* ]]; then
            B64_IMAGE=$(base64 -i "$INPUT_IMAGE")
        else
            B64_IMAGE=$(base64 -w 0 "$INPUT_IMAGE")
        fi
        IMAGE_JSON_PART=$(jq -n --arg b64 "$B64_IMAGE" '{image: {bytesBase64Encoded: $b64}}')
    else
        echo "Error: Image path not found or invalid: $INPUT_IMAGE"
        exit 1
    fi
fi

# Detect Last Image for Interpolation Mode
LAST_IMAGE_JSON_PART=""
if [ ! -z "$LAST_IMAGE" ]; then
    if [[ "$LAST_IMAGE" == gs://* ]]; then
        # GCS URI
        LAST_IMAGE_JSON_PART=$(jq -n --arg uri "$LAST_IMAGE" '{lastImage: {gcsUri: $uri}}')
    elif [ -f "$LAST_IMAGE" ]; then
        # Local File (base64 encode)
        echo "Encoding last image for interpolation..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            B64_LAST_IMAGE=$(base64 -i "$LAST_IMAGE")
        else
            B64_LAST_IMAGE=$(base64 -w 0 "$LAST_IMAGE")
        fi
        LAST_IMAGE_JSON_PART=$(jq -n --arg b64 "$B64_LAST_IMAGE" '{lastImage: {bytesBase64Encoded: $b64}}')
    else
        echo "Error: Last image path not found or invalid: $LAST_IMAGE"
        exit 1
    fi
fi

echo "--- Veo 3.1 Video Generation ---"
echo "Project: $PROJECT_ID"
echo "Model: $MODEL_VERSION"
echo "Prompt: $PROMPT"

# 1. Authenticate and get Access Token
echo "Authenticating for initial submission..."

# 2. Construct JSON Payload using jq
echo "Building request payload..."

# Base instance with just the prompt
INSTANCE_JSON=$(jq -n --arg prompt "$PROMPT" '{prompt: $prompt}')

# Add negative prompt if provided
if [ ! -z "$NEGATIVE_PROMPT" ]; then
    INSTANCE_JSON=$(echo "$INSTANCE_JSON" | jq --arg negPrompt "$NEGATIVE_PROMPT" '. + {negativePrompt: $negPrompt}')
fi

# Merge image into instance if it exists
if [ ! -z "$IMAGE_JSON_PART" ]; then
    INSTANCE_JSON=$(echo "$INSTANCE_JSON" "$IMAGE_JSON_PART" | jq -s 'add')
fi

# Merge last image into instance if it exists (for interpolation)
if [ ! -z "$LAST_IMAGE_JSON_PART" ]; then
    INSTANCE_JSON=$(echo "$INSTANCE_JSON" "$LAST_IMAGE_JSON_PART" | jq -s 'add')
fi

# Build Parameters JSON
PARAMS_JSON=$(jq -n \
    --arg sampleCount "$SAMPLE_COUNT" \
    --arg duration "$DURATION" \
    --arg aspectRatio "$ASPECT_RATIO" \
    --arg resolution "$RESOLUTION" \
    --arg personGen "$PERSON_GENERATION" \
    --argjson audio "$WITH_AUDIO" \
    '{
        sampleCount: ($sampleCount | tonumber),
        durationSeconds: ($duration | tonumber),
        aspectRatio: $aspectRatio,
        resolution: $resolution,
        generateAudio: $audio,
        personGeneration: $personGen
    }')

# Add optional parameters if they exist
if [ ! -z "$OUTPUT_GCS_URI" ]; then
    PARAMS_JSON=$(echo "$PARAMS_JSON" | jq --arg uri "$OUTPUT_GCS_URI" '. + {storageUri: $uri}')
fi
if [ ! -z "$SEED" ]; then
    PARAMS_JSON=$(echo "$PARAMS_JSON" | jq --arg seed "$SEED" '. + {seed: ($seed | tonumber)}')
fi

# Final Full Request Payload
REQUEST_PAYLOAD=$(jq -n \
    --argjson instance "[$INSTANCE_JSON]" \
    --argjson params "$PARAMS_JSON" \
    '{instances: $instance, parameters: $params}')

# 3. Execute API Call
ENDPOINT="https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models/${MODEL_VERSION}:predictLongRunning"

echo "Submitting job to Vertex AI..."
RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$REQUEST_PAYLOAD" \
    "$ENDPOINT")

# 4. Handle Response
# Check if standard error occurred (e.g., authentication failure immediately returned)
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "API Error detected:"
    echo "$RESPONSE" | jq '.'
    exit 1
fi

# Extract Operation Name (Long-running operation ID)
OPERATION_NAME=$(echo "$RESPONSE" | jq -r '.name // empty')

if [ -z "$OPERATION_NAME" ]; then
    echo "Failed to get Operation ID. Raw response:"
    echo "$RESPONSE"
    exit 1
fi

echo ""
echo "✅ Job submitted successfully!"
echo "Operation Name: $OPERATION_NAME"

# Record start time for timing calculation
START_TIME=$(date +%s)

# --- FIX for Veo 3.1 UUID Operation ID Issue ---
# The Veo 3.1 API returns UUID-style operation IDs in the full resource path format:
# projects/{PROJECT}/locations/{LOCATION}/publishers/google/models/{MODEL}/operations/{UUID}
# We need to use the FULL operation name for polling, not the shortened version.

# Use the full operation name as returned by the API
POLL_OPERATION_NAME="$OPERATION_NAME"
echo "Polling operation: $POLL_OPERATION_NAME"

# 5. Poll for completion and download if requested
if [ ! -z "$DOWNLOAD_PATH" ]; then
    echo "Job submitted. Waiting for video generation... (This may take several minutes)"
    echo "Note: Veo 3.1 operations cannot be polled via standard API. Checking GCS bucket directly."
    
    POLL_COUNT=0
    MAX_POLLS=240  # 60 minutes max (240 * 15 seconds)
    SLEEP_INTERVAL=15
    
    # Extract the base path and construct the expected output file pattern
    # The API may append a timestamp or index to the filename
    if [[ "$OUTPUT_GCS_URI" == */ ]]; then
        # If it's a directory, we need to find the file
        GCS_BUCKET_PATH="$OUTPUT_GCS_URI"
        SEARCH_PATTERN="${GCS_BUCKET_PATH}**/*.mp4"
    else
        # If it's a specific file, check for that file
        GCS_BUCKET_PATH=$(dirname "$OUTPUT_GCS_URI")/
        SEARCH_PATTERN="$OUTPUT_GCS_URI"
    fi
    
    echo "Checking for video files in: $GCS_BUCKET_PATH"
    
    while true; do
        # Check if any video files exist in the bucket (recursively)
        VIDEO_FILES=$(gsutil ls -r "$SEARCH_PATTERN" 2>/dev/null | grep '\.mp4$' || true)
        
        if [ ! -z "$VIDEO_FILES" ]; then
            # Found video file(s)
            echo ""
            echo "✅ Video generation complete!"
            
            # Calculate total time taken
            END_TIME=$(date +%s)
            TOTAL_SECONDS=$((END_TIME - START_TIME))
            MINUTES=$((TOTAL_SECONDS / 60))
            SECONDS=$((TOTAL_SECONDS % 60))
            
            echo "⏱️  Total generation time: ${MINUTES}m ${SECONDS}s (${TOTAL_SECONDS} seconds)"
            
            # Get the first (or only) video file
            ACTUAL_GCS_URI=$(echo "$VIDEO_FILES" | head -n 1)
            echo "Video generated at: $ACTUAL_GCS_URI"
            OUTPUT_GCS_URI="$ACTUAL_GCS_URI"
            break
        fi
        
        # Not done yet, wait and try again
        POLL_COUNT=$((POLL_COUNT + 1))
        if [ $POLL_COUNT -ge $MAX_POLLS ]; then
            echo ""
            echo "❌ Timeout: Video generation took longer than expected (60 minutes)"
            echo "The operation may still be running. Check your GCS bucket: $GCS_BUCKET_PATH"
            exit 1
        fi
        
        # Progress indicator with time estimate
        ELAPSED_MINUTES=$((POLL_COUNT * SLEEP_INTERVAL / 60))
        echo -n "." # Print a dot for progress
        
        # Print status update every minute
        if [ $((POLL_COUNT % 4)) -eq 0 ]; then
            echo " [${ELAPSED_MINUTES}m elapsed]"
        fi
        
        sleep $SLEEP_INTERVAL
    done

    # Download the video from GCS
    echo "Downloading video from $OUTPUT_GCS_URI to $DOWNLOAD_PATH..."
    
    # Check if the file exists in GCS before attempting download
    if gsutil -q stat "$OUTPUT_GCS_URI" 2>/dev/null; then
        gsutil cp "$OUTPUT_GCS_URI" "$DOWNLOAD_PATH"
        echo "✅ Download complete: $DOWNLOAD_PATH"
        
        # Show file info
        FILE_SIZE=$(ls -lh "$DOWNLOAD_PATH" | awk '{print $5}')
        echo "File size: $FILE_SIZE"
        
        # Delete from GCS if requested
        if [ "$DELETE_AFTER_DOWNLOAD" == "true" ]; then
            echo "Deleting video from GCS bucket..."
            
            # Extract the directory containing the video file
            VIDEO_DIR=$(dirname "$OUTPUT_GCS_URI")/
            
            # Delete the entire directory (which contains the video file)
            gsutil -m rm -r "$VIDEO_DIR"
            echo "✅ Deleted from GCS: $VIDEO_DIR"
        fi
    else
        echo "❌ Error: File not found in GCS at $OUTPUT_GCS_URI"
        echo ""
        echo "Checking operation response for actual video location..."
        echo "$STATUS_RESPONSE" | jq '.response.predictions[0]' 2>/dev/null || echo "$STATUS_RESPONSE" | jq '.response' 2>/dev/null || echo "$STATUS_RESPONSE"
        
        # List files in the output bucket to help debug
        BUCKET_PATH=$(echo "$OUTPUT_GCS_URI" | sed 's|gs://\([^/]*\)/.*|gs://\1/|')
        echo ""
        echo "Files in bucket $BUCKET_PATH:"
        gsutil ls "$BUCKET_PATH" 2>/dev/null || echo "Unable to list bucket contents"
        
        exit 1
    fi

else
    # Original behavior: Just print info and exit
    echo "------------------------------------------------"
    echo "To check status, run:"
    echo "curl -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \"https://${LOCATION}-aiplatform.googleapis.com/v1/${POLL_OPERATION_NAME}\""
    echo "------------------------------------------------"

    if [ ! -z "$OUTPUT_GCS_URI" ]; then
        echo "Video will be saved to: $OUTPUT_GCS_URI"
    else
        echo "NOTE: No --output-uri provided. You will need to poll the operation manually and extract the base64 video from the final JSON response (not recommended for large videos)."
    fi
fi
