#!/bin/sh
# test-greeter.sh - Corre lefty en una ventana dentro de tu sesion.
#
# Uso (sin sudo):
#   ./tools/test-greeter.sh [layout]
#
# Arranca un Xephyr (servidor X anidado) en un display libre, corre
# lefty adentro, y cuando cerras la ventana del Xephyr, todo termina.
#
# Args:
#   $1  layout (opcional). Si se pasa, override el del config.
#       Valores: centered, win10, win8, gnome.
#   $2  --greeter (opcional). Corre lefty en modo --greeter
#       (fullscreen override_redirect) en lugar de --standalone.
#       Tambien acepta --greeter como $1.
#
# Como funciona:
#   Xephyr :99 -screen 1024x768
#   DISPLAY=:99 lefty --standalone  (o --greeter)
#
# Nada de /etc/greetd, nada de sudo. Solo prueba la UI.

set -e
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

LAYOUT="$1"
GREETER_MODE=0
if [ "$1" = "--greeter" ] || [ "$2" = "--greeter" ]; then
    GREETER_MODE=1
fi
if [ "$1" = "--greeter" ]; then
    LAYOUT=""
fi

LEFTY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$LEFTY_DIR"

# Elegir un display libre entre :90 y :99
for d in 90 91 92 93 94 95 96 97 98 99; do
    if [ ! -e "/tmp/.X${d}-lock" ]; then
        DISP=":$d"
        break
    fi
done
if [ -z "$DISP" ]; then
    echo "test-greeter: no hay display libre entre :90 y :99" >&2
    exit 1
fi

# Tamano de la ventana. 1024x768 imita el VGA real y entra comodo
# en la sesion del usuario.
# Tamano por default: 1024x600 (LVDS-1 de la maquina de referencia).
# Override con SCREEN_W y SCREEN_H en el entorno.
SCREEN_W="${SCREEN_W:-1024}"
SCREEN_H="${SCREEN_H:-600}"

echo "test-greeter: Xephyr en $DISP (${SCREEN_W}x${SCREEN_H})"
echo "test-greeter: layout = ${LAYOUT:-(del config)}"
echo "test-greeter: cerra la ventana para terminar"

# Cursor: Xephyr con -sw-cursor lo dibuja en software. Necesita
# saber que theme usar. Sin XCURSOR_THEME, no encuentra ninguno.
export XCURSOR_THEME="${XCURSOR_THEME:-Vimix-dark}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"

# Arrancar Xephyr. Hereda el DISPLAY actual de la sesion del usuario.
Xephyr "$DISP" \
    -screen "${SCREEN_W}x${SCREEN_H}" \
    -ac -br -noreset \
    -sw-cursor \
    -title "lefty test ($DISP)" &

XEPHYR_PID=$!

# Esperar a que Xephyr este listo (max 5 segundos)
READY=0
for i in $(seq 1 50); do
    if DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 0.1
    if ! kill -0 "$XEPHYR_PID" 2>/dev/null; then
        echo "test-greeter: Xephyr murio" >&2
        exit 1
    fi
done
if [ "$READY" != "1" ]; then
    echo "test-greeter: Xephyr no respondio" >&2
    kill "$XEPHYR_PID" 2>/dev/null || true
    exit 1
fi

# Correr lefty adentro. Si se paso layout, pasarlo por CLI.
export DISPLAY="$DISP"

# Aplicar el cursor al root dentro del Xephyr. Sin esto, el cursor
# queda en el default del servidor (invisible en muchos casos).
xsetroot -cursor_name left_ptr 2>/dev/null || true
xrdb -merge << XEOF
Xcursor.theme: $XCURSOR_THEME
Xcursor.size: $XCURSOR_SIZE
XEOF

MODE_FLAG="--standalone"
if [ "$GREETER_MODE" = "1" ]; then
    MODE_FLAG="--greeter"
fi

echo "test-greeter: mode = $MODE_FLAG"

if [ -n "$LAYOUT" ]; then
    ./run src/main.lua "$MODE_FLAG" --layout "$LAYOUT" --size "${SCREEN_W}x${SCREEN_H}"
else
    ./run src/main.lua "$MODE_FLAG" --size "${SCREEN_W}x${SCREEN_H}"
fi

# Al salir lefty, matar Xephyr
kill "$XEPHYR_PID" 2>/dev/null || true
wait "$XEPHYR_PID" 2>/dev/null || true
echo "test-greeter: fin"
