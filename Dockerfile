FROM linuxserver/ffmpeg:latest

COPY run-within-window.sh /usr/local/bin/run-within-window.sh
RUN chmod +x /usr/local/bin/run-within-window.sh

ENV TRANSCODE_SCRIPT=/config/transcode.sh \
    START_TIME=1030 \
    END_TIME=1600 \
    RUN_INTERVAL_SECONDS=60 \
    SLEEP_SECONDS=300

ENTRYPOINT ["/usr/local/bin/run-within-window.sh"]
