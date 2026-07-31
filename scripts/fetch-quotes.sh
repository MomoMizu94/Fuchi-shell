#!/usr/bin/env bash
# Market data for the dashboard's Finance tab. Emits one JSON line:
#   {"range":"1y","interval":"1d","series":[{...},{...}]}
#
# Usage: fetch-quotes.sh <range> <interval> <symbol>...
#
# Symbols arrive as positional arguments and are never interpolated into a
# command string — they come from a text field the user types into, so the
# usual `bash -c "curl '...$sym...'"` shape used elsewhere in this config would
# be a shell-injection hole here. curl receives them as argv, so the shell
# never re-parses them.
#
# Source is Yahoo's chart endpoint: no API key, no quota, and one URL shape
# covers stocks, crypto, FX and indices. It is undocumented and unofficial, so
# if the Finance tab ever goes blank, this script is the only place to fix.

Y="https://query1.finance.yahoo.com/v8/finance/chart"
# A browser User-Agent is mandatory — the endpoint refuses requests without one.
UA="Mozilla/5.0 (X11; Linux x86_64)"

RANGE="${1:-1y}"
INTERVAL="${2:-1d}"
shift 2 2>/dev/null || true

# Keep only what the chart needs; the raw response is ~30% larger and carries
# adjclose/events/tradingPeriods we never read. Nulls in the OHLC arrays are
# left in place and filtered by the chart (intraday ranges always have some).
FILTER='.chart.result[0] as $r | {
  sym:   $sym,
  ok:    true,
  name:  ($r.meta.shortName // $sym),
  cur:   ($r.meta.currency // ""),
  price: ($r.meta.regularMarketPrice // 0),
  prev:  ($r.meta.chartPreviousClose // $r.meta.previousClose // 0),
  t:     ($r.timestamp // []),
  o:     ($r.indicators.quote[0].open  // []),
  h:     ($r.indicators.quote[0].high  // []),
  l:     ($r.indicators.quote[0].low   // []),
  c:     ($r.indicators.quote[0].close // [])
}'

printf '{"range":"%s","interval":"%s","series":[' "$RANGE" "$INTERVAL"

first=1
for sym in "$@"; do
    [ $first -eq 1 ] || printf ','
    first=0

    body=$(curl -sf -m 10 -A "$UA" --get \
        --data-urlencode "range=$RANGE" \
        --data-urlencode "interval=$INTERVAL" \
        "$Y/$sym" 2>/dev/null)

    # A dead symbol (or a dropped network) degrades to ok:false for that entry
    # only — one bad ticker must never blank the whole tab.
    if [ -z "$body" ]; then
        printf '{"sym":%s,"ok":false}' "$(jq -Rn --arg s "$sym" '$s')"
        continue
    fi

    slim=$(printf '%s' "$body" | jq -c --arg sym "$sym" "$FILTER" 2>/dev/null)
    if [ -z "$slim" ]; then
        printf '{"sym":%s,"ok":false}' "$(jq -Rn --arg s "$sym" '$s')"
    else
        printf '%s' "$slim"
    fi
done

printf ']}\n'
