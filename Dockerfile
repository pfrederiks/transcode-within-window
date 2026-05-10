FROM linuxserver/ffmpeg:latest

WORKDIR /work

COPY transcode-opus.sh /usr/local/bin/transcode-opus.sh
RUN chmod +x /usr/local/bin/transcode-opus.sh

ENTRYPOINT ["/usr/local/bin/transcode-opus.sh"]
