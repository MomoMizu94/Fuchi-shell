#!/usr/bin/env bash
set -eu

fetch() {
    # curl reads the key from stdin so it stays out of the process arguments
    printf '%s' "$OWM_API_KEY" | curl -fsS --max-time 15 --get \
        --data-urlencode "lat=$2" --data-urlencode "lon=$3" \
        --data-urlencode 'units=metric' --data-urlencode 'appid@-' \
        "https://api.openweathermap.org/data/2.5/$1"
}

current=$(fetch weather "$1" "$2")
forecast=$(fetch forecast "$1" "$2")
printf '{"cur":%s,"fc":%s}\n' "$current" "$forecast"
