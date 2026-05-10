# transcode-within-window

Little script and dockerfile that can transcode to AV1 during solar hours.

## Build the Docker image

```bash
docker build -t transcode-within-window .
```

## Run with Docker

Mount the directory containing videos and pass the mounted path to the script:

```bash
docker run --rm \
  -v /path/to/videos:/videos \
  transcode-within-window /videos
```
