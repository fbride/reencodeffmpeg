#!/bin/bash

# Function to display help message
display_help() {
    echo "Usage: $0 <find-pattern>"
    echo ""
    echo "This script re-encodes video files using ffmpeg with H.265 (libx265) encoding."
    echo "It checks the video bitrate, resolution, and audio bitrate before deciding whether to re-encode."
    echo ""
    echo "Arguments:"
    echo "  <find-pattern>   A pattern used by the 'find' command to search for video files."
    echo ""
    echo "Example:"
    echo "  $0 '*.mkv'       Re-encodes all .mkv files in the current directory and its subdirectories."
    echo ""
    exit 1
}

# Check if a pattern is provided as an argument
if [[ -z "$1" ]]; then
    display_help
fi

VIDEO_FILE="$1"
mkdir -p reencoded

# Function to get subtitles track count using mediainfo
get_subtitle_track_count() {
    SUBTITLE_COUNT=$(mediainfo "$VIDEO_FILE" | grep -c "^Text")
    echo "$SUBTITLE_COUNT"
}

# Function to get audio track count using mediainfo
get_audio_track_count() {
    AUDIO_COUNT=$(mediainfo "$VIDEO_FILE" | grep -c "^Audio")
    echo "$AUDIO_COUNT"
}

# Function to get video bitrate using mediainfo
get_video_bitrate() {
    VIDEO_BITRATE=$(mediainfo --Output="Video;%BitRate%" "$VIDEO_FILE")
    echo "$VIDEO_BITRATE"
}

# Function to get video resolution using mediainfo
get_video_resolution() {
    VIDEO_WIDTH=$(mediainfo --Output="Video;%Width%" "$VIDEO_FILE")
    VIDEO_HEIGHT=$(mediainfo --Output="Video;%Height%" "$VIDEO_FILE")
    VIDEO_RESOLUTION="${VIDEO_WIDTH},${VIDEO_HEIGHT}"
    echo "$VIDEO_RESOLUTION"
}

# Function to get audio bitrate using mediainfo
get_audio_bitrate() {
    AUDIO_BITRATE=$(mediainfo --Output="Audio;%BitRate%" "$VIDEO_FILE")
    echo "$AUDIO_BITRATE"
}

# Main loop for processing videos
echo "Processing file: $VIDEO_FILE"

# Get video and audio properties
SUBTITLE_TRACK_COUNT=$(get_subtitle_track_count)
AUDIO_TRACK_COUNT=$(get_audio_track_count)
VIDEO_BITRATE=$(get_video_bitrate)
AUDIO_BITRATE=$(get_audio_bitrate)
VIDEO_RESOLUTION=$(get_video_resolution)

# Check if the bitrate and resolution values are valid (not empty)
if [[ "$VIDEO_BITRATE" == "N/A" || -z "$VIDEO_BITRATE" ]]; then
    VIDEO_BITRATE=1500000  # Default to 1500000 if no bitrate is detected
fi

# Extract width and height from resolution
VIDEO_WIDTH=$(echo "$VIDEO_RESOLUTION" | cut -d ',' -f1)
VIDEO_HEIGHT=$(echo "$VIDEO_RESOLUTION" | cut -d ',' -f2)

# Set output format based on input file extension
EXT="${VIDEO_FILE##*.}"
if [[ "$EXT" == "mkv" ]]; then
    OUTPUT_FILE="reencoded/$(basename "$VIDEO_FILE" .mkv).mkv"
else
    OUTPUT_FILE="reencoded/$(basename "$VIDEO_FILE" .${EXT}).mp4"
fi

# Set default ffmpeg command
FFMPEG_CMD="ffmpeg -i \"$VIDEO_FILE\""

# Determine if video should be copied or re-encoded based on bitrate and resolution
if [[ "$VIDEO_BITRATE" -lt 800000 && "$VIDEO_WIDTH" -le 1280 && "$VIDEO_HEIGHT" -le 720 ]]; then
    echo "Video meets criteria, copying without re-encoding."
    FFMPEG_CMD+=" -map 0:v:0 -c:v copy"
else
    echo "Video does not meet criteria, re-encoding."
    # Check VIDEO_BITRATE
    if [[ "$VIDEO_BITRATE" -gt 800000 && "$VIDEO_BITRATE" -lt 1000000 ]]; then
        FFMPEG_CMD+=" -map 0:v:0 -c:v libx265 -preset medium -crf 25"
    elif [[ "$VIDEO_BITRATE" -gt 1000000 ]]; then
        FFMPEG_CMD+=" -map 0:v:0 -c:v libx265 -preset medium -crf 28"
    else
        FFMPEG_CMD+=" -b:v ${VIDEO_BITRATE} -maxrate ${VIDEO_BITRATE} -bufsize 2M"
    fi
    # Check its current VIDEO_WIDTH and VIDEO_HEIGHT
    if [[ "$VIDEO_WIDTH" -eq 1280 && "$VIDEO_HEIGHT" -eq 720 ]]; then
        FFMPEG_CMD+=" -map 0:v:0 -c:v libx265 -preset medium -crf 28 -vf scale=1280:720"
    elif [[ "$VIDEO_WIDTH" -gt 1280 || "$VIDEO_HEIGHT" -gt 720 ]]; then
        # Calculate the aspect ratio (DAR = VIDEO_WIDTH / VIDEO_HEIGHT)
        ASPECT_RATIO=$(echo "scale=6; $VIDEO_WIDTH / $VIDEO_HEIGHT" | bc)
        # Check if the width or height is the larger dimension
        if [[ "$VIDEO_WIDTH" -gt "$VIDEO_HEIGHT" ]]; then
            # Scale width down to 1280, and calculate the new height to maintain aspect ratio
            VIDEO_WIDTH=1280
            VIDEO_HEIGHT=$(echo "scale=0; $VIDEO_WIDTH / $ASPECT_RATIO" | bc)
        else
            # Scale height down to 720, and calculate the new width to maintain aspect ratio
            VIDEO_HEIGHT=720
            VIDEO_WIDTH=$(echo "scale=0; $VIDEO_HEIGHT * $ASPECT_RATIO" | bc)
        fi
        FFMPEG_CMD+=" -vf scale=$VIDEO_WIDTH:$VIDEO_HEIGHT"
    elif [[ "$VIDEO_WIDTH" -gt 1280 && "$VIDEO_HEIGHT" -gt 720 ]]; then
        FFMPEG_CMD+=" -vf scale=1280:720"
    elif [[ "$VIDEO_WIDTH" -lt 1280 || "$VIDEO_HEIGHT" -lt 720 ]]; then
        FFMPEG_CMD+=" -vf scale=$VIDEO_WIDTH:$VIDEO_HEIGHT"
    fi
fi

# Handle audio streams: re-encode only if bitrate is higher than 192k
for (( i=0; i<AUDIO_TRACK_COUNT; i++ ))
do
    AUDIO_STREAM_BITRATE=$(get_audio_bitrate "$VIDEO_FILE" "$i")
    
    # Check if the audio bitrate is valid (not 'N/A')
    if [[ "$AUDIO_STREAM_BITRATE" == "N/A" || -z "$AUDIO_STREAM_BITRATE" ]]; then
        AUDIO_STREAM_BITRATE=0  # Default to 0 if no audio bitrate is detected
    fi
    
    if [[ "$AUDIO_STREAM_BITRATE" -le 192000 ]]; then
        echo "Audio stream $i meets criteria, copying without re-encoding."
        FFMPEG_CMD+=" -map 0:a:$i -c:a copy"
    else
        echo "Audio stream $i does not meet criteria, re-encoding."
        FFMPEG_CMD+=" -map 0:a:$i -c:a aac -b:a 192k"
    fi
done

# Copy subtitle streams if they exist
if [[ "$SUBTITLE_TRACK_COUNT" -gt 0 ]]; then
    for (( i=0; i<SUBTITLE_TRACK_COUNT; i++ )); do
        FFMPEG_CMD+=" -map 0:s:$i -c:s:$i copy"
    done
fi

# Preserve chapters if they exist
FFMPEG_CMD+=" -map_chapters 0"

# Set the output format
if [[ "$EXT" == "mkv" ]]; then
    FFMPEG_CMD+=" -f matroska"
fi

# Run the ffmpeg command
FFMPEG_CMD+=" -y \"$OUTPUT_FILE\""
echo "Running: $FFMPEG_CMD"
eval $FFMPEG_CMD
