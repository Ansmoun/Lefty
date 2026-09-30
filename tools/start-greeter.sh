#!/bin/sh

# Log en /var/log para que sobreviva al reinicio.
LOG=/var/log/lefty-greeter.log
exec > "$LOG" 2>&1

echo "=== lefty-greeter wrapper arrancando ==="
date
echo "USER=$USER"
echo "HOME=$HOME"
echo "XDG_VTNR=${XDG_VTNR:-<unset>}"
echo "GREETD_SOCK=${GREETD_SOCK:-<unset>}"
echo "---"

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Cerrar TODOS los fds > 2 excepto el del propio script.
#
# Greetd abre un socket de coordinacion con su session-worker y lo
# deja heredado al invocar el wrapper. Si ese socket sigue abierto
# en el wrapper (o en cualquiera de sus descendientes) cuando
# greetd intenta terminar el worker, el worker no termina y greetd
# no avanza. Deadlock.
#
# El cierre tiene que pasar en el shell del wrapper, al principio,
# antes de arrancar Xorg. Asi el socket no se hereda a nadie.
#
# El unico fd que hay que preservar es el del script ($0), porque
# sh lo esta leyendo para ejecutar las lineas siguientes. Se
# identifica con readlink, no por numero fijo.
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null) || SCRIPT_PATH="$0"
SCRIPT_FD=""
for f in /proc/$$/fd/*; do
    n="${f##*/}"
    target=$(readlink "$f" 2>/dev/null)
    if [ "$target" = "$SCRIPT_PATH" ]; then
        SCRIPT_FD="$n"
        break
    fi
done
echo "wrapper: script_fd=$SCRIPT_FD script_path=$SCRIPT_PATH"

echo "--- fds antes del cierre ---"
ls -la /proc/$$/fd/ 2>/dev/null

for f in /proc/$$/fd/*; do
    n="${f##*/}"
    case "$n" in
        0|1|2) continue ;;
    esac
    if [ -n "$SCRIPT_FD" ] && [ "$n" = "$SCRIPT_FD" ]; then
        continue
    fi
    eval "exec $n<&-" 2>/dev/null || true
    eval "exec $n>&-" 2>/dev/null || true
done

echo "--- fds despues del cierre ---"
ls -la /proc/$$/fd/ 2>/dev/null

TEST_MODE=0
if [ "$1" = "--test" ]; then
    TEST_MODE=1
fi

LEFTY_DIR="/opt/lefty"
LEFTY_RUN="$LEFTY_DIR/run"
DISPLAY_NUM=0
XORG_PID=""


_kill_xorg_bounded() {
    if [ -z "$XORG_PID" ]; then return; fi
    if ! kill -0 "$XORG_PID" 2>/dev/null; then return; fi
    chvt 1 2>/dev/null || true
    sleep 0.3
    echo "[$(date +%T)] SIGTERM a Xorg (pid=$XORG_PID)"
    kill "$XORG_PID" 2>/dev/null || true
    _i=0
    while [ "$_i" -lt 30 ]; do
        if ! kill -0 "$XORG_PID" 2>/dev/null; then
            echo "[$(date +%T)] Xorg termino con SIGTERM"
            return
        fi
        sleep 0.1
        _i=$((_i + 1))
    done
    echo "[$(date +%T)] Xorg no murio, SIGKILL"
    kill -9 "$XORG_PID" 2>/dev/null || true
    sleep 0.5
}

cleanup() {
    echo "cleanup: liberando Xorg (pid=$XORG_PID)"
    if [ -n "$XORG_PID" ]; then
        _kill_xorg_bounded
        sleep 2
    fi
    exit 0
}
trap cleanup TERM INT HUP

if [ "$TEST_MODE" = "1" ]; then
    VT=8
    DISPLAY_NUM=2
else
    VT="${XDG_VTNR:-7}"
    for d in 0 1 2 3; do
        if [ ! -e "/tmp/.X${d}-lock" ]; then
            DISPLAY_NUM=$d
            break
        fi
    done
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

Xorg ":$DISPLAY_NUM" -seat seat0 -nolisten tcp -terminate \
    -auth "$XAUTH" "vt$VT" &
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
    kill "$XORG_PID" 2>/dev/null || true
    exit 1
fi

echo "start-greeter: Xorg listo (pid=$XORG_PID)"

export XCURSOR_THEME="Vimix-dark"
export XCURSOR_SIZE=24
if [ -f "$HOME/.Xresources" ]; then
    DISPLAY=":$DISPLAY_NUM" xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
fi
DISPLAY=":$DISPLAY_NUM" xsetroot -cursor_name left_ptr 2>/dev/null || true

DISPLAY=":$DISPLAY_NUM" xrandr \
    --output "$OTHER" --off \
    --output "$ACTIVE" --mode "$RES" --pos 0x0 2>/dev/null || true

export DISPLAY=":$DISPLAY_NUM"
export LANETK_LOG="${LANETK_LOG:-info}"

echo "--- pstree antes de lefty ---"
command -v pstree >/dev/null && pstree -p $$ || true

"$LEFTY_RUN" "$LEFTY_DIR/src/main.lua" --greeter
EXIT_CODE=$?

echo "start-greeter: lefty salio con $EXIT_CODE"

_kill_xorg_bounded
sleep 2

exit "$EXIT_CODE"
