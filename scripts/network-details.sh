#!/usr/bin/env bash
ip -4 -o addr show up dev "$1" scope global | awk 'NR == 1 { address = $4 } END { print address }'
if [[ $2 == wifi ]]; then
    LC_ALL=C nmcli -t -f ACTIVE,FREQ device wifi list ifname "$1" --rescan no |
        awk -F: '$1 == "yes" { print $2; exit }'
fi
