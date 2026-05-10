# transcode-within-window

Docker image for AV1 transcoding with a user-provided script, only running between 10:30 and 16:00.

## Build

```bash
docker build -t transcode-within-window .
```

## Run

Provide your transcoding script at `/config/transcode.sh` (mounted into the container and executable):

```bash
docker run --rm \
  -e TZ=Europe/Amsterdam \
  -v /path/to/transcode.sh:/config/transcode.sh:ro \
  -v /path/to/media:/media \
  transcode-within-window
```

Optional environment variables:

- `START_TIME` (default `1030`)
- `END_TIME` (default `1600`)
- `RUN_INTERVAL_SECONDS` (default `60`)
- `SLEEP_SECONDS` (default `300`)
- `TRANSCODE_SCRIPT` (default `/config/transcode.sh`)

Make sure `/path/to/transcode.sh` has executable permissions on the host (`chmod +x /path/to/transcode.sh`) before starting the container.
