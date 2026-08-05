#!/usr/bin/env bash
# Consolidated performance snapshot, polled by the Performance tab and by
# the Overview tab's hardware mini-chart (see Dashboard.qml).
# Samples /proc/stat and /proc/net/dev 0.5s apart, emits one JSON line

s1=$(grep '^cpu' /proc/stat)
n1=$(awk '/:/{gsub(":","",$1); if($1!="lo"){rx+=$2; tx+=$10}} END{print rx+0, tx+0}' /proc/net/dev)
sleep 0.5
s2=$(grep '^cpu' /proc/stat)
n2=$(awk '/:/{gsub(":","",$1); if($1!="lo"){rx+=$2; tx+=$10}} END{print rx+0, tx+0}' /proc/net/dev)

# Busy% per /proc/stat line from the two samples; line 1 is the total, rest are cores
cpu_json=$(awk -v s1="$s1" -v s2="$s2" 'BEGIN {
    n = split(s1, a, "\n"); split(s2, b, "\n")
    out = ""
    for (i = 1; i <= n; i++) {
        split(a[i], x, " "); split(b[i], y, " ")
        idle1 = x[5] + x[6]; idle2 = y[5] + y[6]
        tot1 = 0; tot2 = 0
        for (j = 2; j <= 11; j++) { tot1 += x[j]; tot2 += y[j] }
        dt = tot2 - tot1
        pct = dt > 0 ? (100 * (dt - (idle2 - idle1)) / dt) : 0
        if (i == 1) total = pct
        else out = out (out == "" ? "" : ",") sprintf("%.0f", pct)
    }
    printf "%.0f [%s]", total, out
}')
cpu=${cpu_json%% *}
cores=${cpu_json#* }

freq=$(awk -F: '/cpu MHz/{s+=$2; n++} END{if (n) printf "%.1f", s/n/1000; else print 0}' /proc/cpuinfo)
ctemp=$(sensors 2>/dev/null | awk '/Tctl/{gsub(/[+°C]/,"",$2); print $2; exit}')
gpu=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,name --format=csv,noheader,nounits 2>/dev/null)
gutil=$(echo "$gpu" | cut -d, -f1 | tr -d ' ')
gtemp=$(echo "$gpu" | cut -d, -f2 | tr -d ' ')
gname=$(echo "$gpu" | cut -d, -f3- | sed 's/^ *//; s/NVIDIA GeForce //')
read -r ramU ramT < <(free -m | awk 'NR==2{printf "%.1f %.1f", $3/1024, $2/1024}')
read -r dU dT < <(df -BG / | awk 'NR==2{gsub("G",""); print $3, $2}')
procs=$(ps -e --no-headers | wc -l)
read -r rx1 tx1 <<< "$n1"
read -r rx2 tx2 <<< "$n2"
up=$(awk -v a="$tx1" -v b="$tx2" 'BEGIN{printf "%.1f", (b-a)/0.5/1000000}')
down=$(awk -v a="$rx1" -v b="$rx2" 'BEGIN{printf "%.1f", (b-a)/0.5/1000000}')

printf '{"cpu":%s,"cores":%s,"freq":%s,"ctemp":%s,"gpu":%s,"gtemp":%s,"gname":"%s","ramU":%s,"ramT":%s,"up":%s,"down":%s,"diskU":%s,"diskT":%s,"procs":%s}\n' \
    "${cpu:-0}" "${cores:-[]}" "${freq:-0}" "${ctemp:-0}" "${gutil:-0}" "${gtemp:-0}" "$gname" \
    "${ramU:-0}" "${ramT:-0}" "${up:-0}" "${down:-0}" "${dU:-0}" "${dT:-0}" "${procs:-0}"
