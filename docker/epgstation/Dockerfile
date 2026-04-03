FROM docker.io/l3tnun/epgstation:latest

# Install ffmpeg for live streaming (HLS, MP4, WebM transcoding)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Create streamfiles directory for HLS segments
RUN mkdir -p /app/streamfiles

# Verify
RUN ffmpeg -version | head -1
