#!/bin/sh
# install.sh: instala LaneTK y Lefty en /opt/ para uso como greeter.
#
# Uso:
#   cd ~/proyectos/lefty
#   sudo tools/install.sh [-y]
#
# -y, --yes  no pedir confirmación

set -e

# --- Argumentos ---
AUTO_YES=0
for a in "$@"; do
    case "$a" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
    esac
done

# --- Usuario real (por si se corre con sudo) ---
if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

SRC_TK="${REAL_HOME}/proyectos/lanetk"
SRC_LEFTY="${REAL_HOME}/proyectos/lefty"
DST_TK="/opt/lanetk"
DST_LEFTY="/opt/lefty"
STATE_DIR="/var/lib/lefty"

# --- Verificaciones ---
if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: necesita root. Correlo con sudo." >&2
    exit 1
fi

if [ ! -d "$SRC_TK/src/lib" ]; then
    echo "install.sh: no existe $SRC_TK/src/lib" >&2
    exit 1
fi

if [ ! -d "$SRC_LEFTY/src" ]; then
    echo "install.sh: no existe $SRC_LEFTY/src" >&2
    exit 1
fi

# --- Aviso ---
echo "==> Instalación de LaneTK + Lefty en /opt/"
echo "    LaneTK:  $SRC_TK"
echo "    Lefty:   $SRC_LEFTY"
echo "    Estado:  $STATE_DIR"
echo

if [ -d "$DST_TK" ] || [ -d "$DST_LEFTY" ]; then
    if [ "$AUTO_YES" -eq 0 ]; then
        printf "Se va a reemplazar la instalación existente. Continuar? [y/N] "
        read -r ans
        case "$ans" in
            y|Y|yes|YES) ;;
            *) echo "Cancelado."; exit 0 ;;
        esac
    fi
fi

# --- Limpiar destino ---
echo "==> Borrando instalación previa"
rm -rf "$DST_TK" "$DST_LEFTY"

# --- Copiar LaneTK ---
echo "==> Copiando LaneTK"
mkdir -p "$DST_TK"
tar -C "$SRC_TK" \
    --exclude='./.git' \
    --exclude='./.backups' \
    --exclude='./docs' \
    --exclude='./examples' \
    --exclude='./tests' \
    --exclude='./tools' \
    --exclude='*.bak' \
    --exclude='*.bak-*' \
    --exclude='*.bak.*' \
    --exclude='*.orig' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    -cf - . | tar -C "$DST_TK" -xf -

# --- Copiar Lefty ---
echo "==> Copiando Lefty"
mkdir -p "$DST_LEFTY"
tar -C "$SRC_LEFTY" \
    --exclude='./.git' \
    --exclude='*.bak' \
    --exclude='*.bak-*' \
    --exclude='*.bak.*' \
    --exclude='*.orig' \
    --exclude='*.swp' \
    --exclude='.DS_Store' \
    -cf - . | tar -C "$DST_LEFTY" -xf -

# --- Permisos ---
echo "==> Ajustando permisos"
chmod -R a+rX,go-w "$DST_TK" "$DST_LEFTY"

for f in \
    "$DST_TK/run" \
    "$DST_TK/bin/lanetk-session" \
    "$DST_LEFTY/run" \
    "$DST_LEFTY/tools/install.sh" \
    "$DST_LEFTY/tools/start-greeter.sh" \
    "$DST_LEFTY/tools/test-greeter.sh"
do
    if [ -f "$f" ]; then
        chmod +x "$f"
    fi
done

# --- Estado persistente ---
echo "==> Preparando $STATE_DIR"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/last-user"
chmod 0777 "$STATE_DIR"
chmod 0666 "$STATE_DIR/last-user"

# --- Verificación como greeter ---
if id greeter >/dev/null 2>&1; then
    echo "==> Verificando acceso del usuario greeter"
    failed=0
    for f in \
        "$DST_LEFTY/run" \
        "$DST_LEFTY/src/main.lua" \
        "$DST_TK/src/lib/server.lua" \
        "$DST_TK/src/lib/greetd.lua" \
        "$DST_TK/src/lib/xsessions.lua" \
        "$DST_TK/bindings/cdef/net.lua"
    do
        if sudo -u greeter test -r "$f"; then
            echo "    OK    $f"
        else
            echo "    FALLO $f"
            failed=1
        fi
    done
    if [ "$failed" -eq 1 ]; then
        echo "install.sh: el usuario greeter no puede leer algunos archivos." >&2
        exit 1
    fi
else
    echo "==> El usuario 'greeter' no existe."
    echo "    Crearlo antes de habilitar greetd:"
    echo "        sudo useradd -r -s /bin/bash -d /home/.greeter -m greeter"
fi

# --- Resumen ---
echo
echo "==> Instalación completa."
echo
echo "Pasos manuales que quedan por hacer (una sola vez):"
echo
echo "  1. Config:"
echo "       sudo cp $DST_LEFTY/config.conf /etc/greetd/lefty.conf"
echo
echo "  2. Wrapper:"
echo "       sudo cp $DST_LEFTY/tools/start-greeter.sh /etc/greetd/start-greeter.sh"
echo "       sudo chmod +x /etc/greetd/start-greeter.sh"
echo
echo "  3. /etc/greetd/config.toml:"
echo "       [terminal]"
echo "       vt = \"next\""
echo "       [default_session]"
echo "       command = \"/etc/greetd/start-greeter.sh\""
echo "       user = \"greeter\""
echo
echo "  4. Habilitar el servicio:"
echo "       sudo ln -sf /etc/sv/greetd /var/service/greetd"
