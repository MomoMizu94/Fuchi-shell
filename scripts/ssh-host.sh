#!/usr/bin/env bash
# Launch a floating SSH terminal, or run its SSH session inside Kitty.
set -u

if [[ ${1:-} == --session ]]; then
    shift
    if (( $# < 1 || $# > 2 )); then
        printf 'Usage: ssh-host.sh --session destination [startup-command]\n' >&2
        exit 2
    fi
    if [[ -n ${2:-} ]]; then
        # Keep the remote shell alive when Ctrl+C stops the startup program.
        # Both the command and $SHELL are evaluated on the Pi after login.
        remote_command=$'trap : INT\n'
        remote_command+="$2"
        remote_command+=$'\ntrap - INT\nexec "${SHELL:-/bin/sh}" -l'
        ssh -t -o ConnectTimeout=10 -- "$1" "$remote_command"
    else
        ssh -o ConnectTimeout=10 -- "$1"
    fi
    status=$?
    if (( status != 0 )); then
        printf '\nSSH to %s ended with exit status %s.\n' "$1" "$status" >&2
        printf 'Press Enter to close this window, then choose the host to retry. ' >&2
        read -r answer
    fi
    exit "$status"
fi

# An already-running menu may still use the original five-argument command.
# Preserve that call until Quickshell reloads the updated QML.
if (( $# == 5 )); then
    set -- "$@" 76 20
fi

if (( $# < 7 || $# > 8 )) || [[ ! $1 =~ ^[a-zA-Z0-9_-]+$ ]] \
        || [[ ! $4 =~ ^[1-9][0-9]*$ || ! $5 =~ ^[1-9][0-9]*$ ]] \
        || [[ ! $6 =~ ^(0|[1-9][0-9]*)$ || ! $7 =~ ^(0|[1-9][0-9]*)$ ]]; then
    printf 'Usage: ssh-host.sh id name destination width height [left-inset bottom-inset [startup-command]]\n' >&2
    exit 2
fi

for dependency in kitty ssh hyprctl; do
    if ! command -v "$dependency" >/dev/null; then
        printf 'Required command not found: %s\n' "$dependency" >&2
        exit 127
    fi
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Hyprland runs exec_cmd through /bin/sh. Quote each argument for that shell.
shell_quote() {
    local value=$1
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

command=exec
for argument in kitty --class "fuchi-ssh-$1" --title "$2" \
        -o remember_window_size=no -o "initial_window_width=$4" \
        -o "initial_window_height=$5" bash "$script_dir/ssh-host.sh" --session "$3"; do
    command+=" $(shell_quote "$argument")"
done
if [[ -n ${8:-} ]]; then
    command+=" $(shell_quote "$8")"
fi

# A Lua long string preserves shell quoting and Unicode. Pick a delimiter that
# cannot be closed by an argument. exec keeps Kitty's PID for the launch rules.
delimiter='='
while [[ $command == *"]$delimiter]"* ]]; do
    delimiter+='='
done
# Keep the window beside the sidebar and above the bottom frame on any output.
output=$(hyprctl eval "hl.exec_cmd([$delimiter[$command]$delimiter], {float=true, size={$4,$5}, move={$6,\"monitor_h-window_h-$7\"}})")
status=$?
if (( status != 0 )); then
    printf '%s\n' "$output" >&2
    exit "$status"
fi
if [[ $output != ok ]]; then
    printf 'Hyprland could not launch the terminal: %s\n' "$output" >&2
    exit 1
fi
