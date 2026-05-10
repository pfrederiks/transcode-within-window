#!/usr/bin/env bash
set -euo pipefail

TRANSCODE_SCRIPT="${TRANSCODE_SCRIPT:-/config/transcode.sh}"
START_TIME="${START_TIME:-1030}"
END_TIME="${END_TIME:-1600}"
RUN_INTERVAL_SECONDS="${RUN_INTERVAL_SECONDS:-60}"
SLEEP_SECONDS="${SLEEP_SECONDS:-300}"

if [[ ! -x "${TRANSCODE_SCRIPT}" ]]; then
  echo "Transcode script is missing or not executable: ${TRANSCODE_SCRIPT}" >&2
  exit 1
fi

while true; do
  NOW="$(date +%H%M)"

  if (( 10#${NOW} >= 10#${START_TIME} && 10#${NOW} < 10#${END_TIME} )); then
    echo "$(date -Iseconds) In solar window (${START_TIME}-${END_TIME}). Running ${TRANSCODE_SCRIPT}."
    "${TRANSCODE_SCRIPT}"
    sleep "${RUN_INTERVAL_SECONDS}"
  else
    echo "$(date -Iseconds) Outside solar window (${START_TIME}-${END_TIME}). Sleeping ${SLEEP_SECONDS}s."
    sleep "${SLEEP_SECONDS}"
  fi
done
