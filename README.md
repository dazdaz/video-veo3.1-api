# Veo 3.1 Video Generation API

A bash script for generating videos using Google's Veo 3.1 model via Vertex AI API.

## Features

- ✅ **Fixed 404 Polling Errors**: Uses GCS bucket-based polling instead of broken API operation polling
- ✅ **Automatic Download**: Polls for completion and downloads generated videos
- ✅ **Auto-Cleanup**: Optional `--delete-after-download` flag to remove files and folders from GCS
- ✅ **Full Parameter Support**: Aspect ratio, duration, resolution, audio generation, and more
- ✅ **Image-to-Video**: Support for both text-to-video and image-to-video generation
- ✅ **Video Interpolation**: Create smooth transitions between two images using `--lastimage`
- ✅ **Negative Prompts**: Specify what NOT to include in generated videos
- ✅ **Person Generation Control**: Configure person generation policy (allow_all, allow_adult, dont_allow)
- ✅ **Generation Timing**: Displays total time taken to generate videos

## Prerequisites

- Google Cloud SDK (`gcloud`)
- `gsutil` (included with gcloud)
- `jq` (JSON processor)
- `curl`
- Active Google Cloud project with Vertex AI API enabled
- GCS bucket for storing generated videos

## Installation

```bash
# Clone the repository
git clone https://github.com/dazdaz/video-veo3.1-api.git
cd video-veo3.1-api

# Make the script executable
chmod +x veo-create.sh

# Create your GCS bucket
gsutil mb gs://me-veo31-bucket
```

## Usage

### Basic Example

```bash
./veo-create.sh \
  --project-id YOUR_PROJECT_ID \
  --prompt "A serene sunset over mountains" \
  --output-uri gs://your-bucket/videos/ \
  --download-to ./output.mp4
```

### Full Example with All Options

```bash
./veo-create.sh \
  --project-id my-playground \
  --model veo-3.1-generate-preview \
  --location us-central1 \
  --aspect-ratio 16:9 \
  --duration 8 \
  --resolution 1080p \
  --with-audio \
  --person-generation allow_all \
  --output-uri gs://your-bucket/videos/ \
  --download-to ./video.mp4 \
  --delete-after-download \
  --prompt "A realistic bladerunner scene with matching audio"
```

### Image-to-Video Example

```bash
./veo-create.sh \
  --project-id YOUR_PROJECT_ID \
  --image ./input-image.jpg \
  --prompt "Animate this image with gentle movement" \
  --output-uri gs://your-bucket/videos/ \
  --download-to ./animated.mp4
```

### Video Interpolation Example (Image-to-Image Transition)

```bash
./veo-create.sh \
  --project-id YOUR_PROJECT_ID \
  --image ./start-frame.jpg \
  --lastimage ./end-frame.jpg \
  --prompt "Smooth transition from start to end" \
  --output-uri gs://your-bucket/videos/ \
  --download-to ./transition.mp4
```

### Using Negative Prompts

```bash
./veo-create.sh \
  --project-id YOUR_PROJECT_ID \
  --prompt "A beautiful garden scene" \
  --negative-prompt "people, animals, buildings" \
  --output-uri gs://your-bucket/videos/ \
  --download-to ./garden.mp4
```

### Person Generation Control

```bash
./veo-create.sh \
  --project-id YOUR_PROJECT_ID \
  --prompt "A crowded city street" \
  --person-generation "dont_allow" \
  --output-uri gs://your-bucket/videos/ \
  --download-to ./city.mp4
```

## Parameters

### Required
- `--project-id <id>` - Your Google Cloud Project ID
- `--prompt <text>` - Text prompt for video generation

### Optional
- `--model <name>` - Model version (default: `veo-3.1-generate-preview`)
- `--location <region>` - Vertex AI region (default: `us-central1`)
- `--output-uri <gs://>` - GCS URI for saving results (required for download)
- `--download-to <path>` - Local path to download the generated video
- `--delete-after-download` - Delete video and folder from GCS after download
- `--aspect-ratio <ratio>` - Video aspect ratio: `16:9`, `9:16`, `1:1` (default: `16:9`)
- `--duration <seconds>` - Video duration: `4`, `6`, or `8` seconds (default: `8`)
- `--resolution <res>` - Resolution: `720p` or `1080p` (default: `1080p`)
- `--with-audio` - Generate matched audio for the video
- `--seed <int>` - Integer seed for deterministic generation
- `--image <path/uri>` - Local file or GCS URI for image-to-video mode
- `--lastimage <path/uri>` - Final image for interpolation (requires `--image`)
- `--negative-prompt <text>` - What NOT to include in the video
- `--person-generation <policy>` - Person generation policy: `allow_all` (default), `allow_adult`, `dont_allow`
- `--help` - Show help message

## How It Works

1. **Submits** video generation job to Vertex AI with your specified parameters
2. **Polls** the GCS bucket directly for the generated `.mp4` file (bypasses broken API polling)
3. **Downloads** the video once it appears in the bucket
4. **Displays** total generation time
5. **Optionally deletes** both the video file and its parent folder from GCS

## Advanced Features

### Video Interpolation
Create smooth transitions between two images by using both `--image` and `--lastimage` parameters. The model will generate a video that smoothly transitions from the first image to the last image.

### Negative Prompts
Use `--negative-prompt` to specify elements you want to exclude from the generated video. This helps refine the output by telling the model what NOT to include.

### Person Generation Control
Control how people appear in your videos with the `--person-generation` parameter:
- `allow_all` (default): No restrictions on person generation
- `allow_adult`: Only generate adult persons
- `dont_allow`: Do not generate any people in the video

## Troubleshooting

### 404 Errors During Polling
The script automatically handles this by using GCS bucket polling instead of API operation polling. This is a known issue with Veo 3.1's UUID-based operation IDs.

### Authentication Issues
```bash
# Re-authenticate with gcloud
gcloud auth login
gcloud auth application-default login
```

### Permission Issues
Ensure your account has the following permissions:
- `aiplatform.endpoints.predict`
- `storage.objects.create`
- `storage.objects.get`
- `storage.objects.delete` (if using `--delete-after-download`)

## License

MIT License - feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Built for Google's Veo 3.1 video generation model
- Fixes the UUID operation ID polling issue with a GCS-based approach

## Other methods to use Veo 3.1
* Google Cloud Vertex AI - Main platform for users
* Google AI Studio
* https://flow.google

## Docs
* https://blog.google/technology/ai/veo-updates-flow/
* https://ai.google.dev/gemini-api/docs/video?example=dialogue
