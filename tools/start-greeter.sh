#!/bin/sh
# Wrapper de greetd para Lefty.

LOG=/var/log/lefty-greeter.log
exec > "$LOG" 2>&1

echo "=== lefty-greeter wrapper arrancando ==="
date
echo "USER=$USER HOME=$HOME"
echo "XDG_VTNR=${XDG_VTNR:-<unset>}"
echo "GREETD_SOCK=${GREETD_SOCK:-<unset>}"

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

TEST_MODE=0
[ "$1" = "--test" ] && TEST_MODE=1

LEFTY_DIR="/opt/lefty"
LEFTY_RUN="$LEFTY_DIR/run"
LEFTY_PID=""
XORG_PID=""

# VT y display segun modo
if [ "$TEST_MODE" = "1" ]; then
    VT=8
    DISPLAY_NUM=2
else
    VT="${XDG_VTNR:-7}"
    DISPLAY_NUM=""
    for d in 0 1 2 3; do
        if [ ! -e "/tmp/.X${d}-lock" ]; then
            DISPLAY_NUM=$d
            break
        fi
    done
    [ -z "$DISPLAY_NUM" ] && DISPLAY_NUM=0
fi

echo "start-greeter: display=:$DISPLAY_NUM vt=$VT"

XAUTH="$HOME/.Xauthority"
touch "$XAUTH"
chmod 600 "$XAUTH"
export XAUTHORITY="$XAUTH"

VGA_STATUS=$(cat /sys/class/drm/card0-VGA-1/status 2>/dev/null)
if [ "$VGA_STATUS" = "connected" ]; then
    ACTIVE="VGA-1"; OTHER="LVDS-1"; RES="1024x768"
else
    ACTIVE="LVDS-1"; OTHER="VGA-1"; RES="1024x600"
fi
echo "start-greeter: monitor=$ACTIVE"

# Xorg en subshell que cierra fds > 2 antes de exec.
(
    for f in /proc/self/fd/*; do
        n="${f##*/}"
        case "$n" in 0|1|2) continue ;; esac
        eval "exec $n<&-" 2>/dev/null
        eval "exec $n>&-" 2>/dev/null
    done
    exec Xorg ":$DISPLAY_NUM" -seat seat0 -nolisten tcp -noreset \
        -auth "$XAUTH" "vt$VT"
) &
XORG_PID=$!

READY=0
for i in $(seq 1 50); do
    if DISPLAY=":$DISPLAY_NUM" XAUTHORITY="$XAUTH" xdpyinfo >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 0.1
    if ! kill -0 "$XORG_PID" 2>/dev/null; then
        echo "start-greeter: Xorg murio durante el arranque" >&2
        exit 1
    fi
done

if [ "$READY" != "1" ]; then
    echo "start-greeter: Xorg no respondio en 5s" >&2
    kill "$XORG_PID" 2>/dev/null
    exit 1
fi

echo "start-greeter: Xorg listo (pid=$XORG_PID)"

export XCURSOR_THEME="Vimix-dark"
export XCURSOR_SIZE=24
[ -f "$HOME/.Xresources" ] && \
    DISPLAY=":$DISPLAY_NUM" xrdb -merge "$HOME/.Xresources" 2>/dev/null
DISPLAY=":$DISPLAY_NUM" xsetroot -cursor_name left_ptr 2>/dev/null

DISPLAY=":$DISPLAY_NUM" xrandr \
    --output "$OTHER" --off \
    --output "$ACTIVE" --mode "$RES" --pos 0x0 2>/dev/null

export DISPLAY=":$DISPLAY_NUM"
export LANETK_LOG="${LANETK_LOG:-debug}"

_kill_xorg_bounded() {
    [ -z "$XORG_PID" ] && return
    kill -0 "$XORG_PID" 2>/dev/null || return
    kill -TERM "$XORG_PID" 2>/dev/null
    i=0
    while [ $i -lt 20 ]; do
        kill -0 "$XORG_PID" 2>/dev/null || return
        sleep 0.05
        i=$((i+1))
    done
    kill -KILL "$XORG_PID" 2>/dev/null
}

cleanup() {
    echo "[$(date +%T)] cleanup"
    if [ -n "$LEFTY_PID" ]; then
        kill -TERM "$LEFTY_PID" 2>/dev/null
        i=0
        while [ $i -lt 20 ]; do
            kill -0 "$LEFTY_PID" 2>/dev/null || break
            sleep 0.05
            i=$((i+1))
        done
        kill -KILL "$LEFTY_PID" 2>/dev/null
    fi
    _kill_xorg_bounded
    exit 0
}
trap cleanup TERM INT HUP

"$LEFTY_RUN" "$LEFTY_DIR/src/main.lua" --greeter &
LEFTY_PID=$!
echo "[$(date +%T)] lefty lanzado (pid=$LEFTY_PID)"

wait "$LEFTY_PID"
EXIT_CODE=$?
echo "[$(date +%T)] lefty salio con $EXIT_CODE"

_kill_xorg_bounded
exit "$EXIT_CODE"
