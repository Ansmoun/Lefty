#!/bin/sh
# install.sh: instala Lefty en /opt/lefty/.
#
# Uso:
#   cd ~/proyectos/lefty
#   sudo tools/install.sh [-y] [--install-deps]
#
# -y, --yes            no pedir confirmación
#     --install-deps   instalar dependencias faltantes (solo Void Linux)

set -e

AUTO_YES=0
INSTALL_DEPS=0
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)          AUTO_YES=1 ;;
        --install-deps)    INSTALL_DEPS=1 ;;
        -h|--help)         sed -n '2,10p' "$0"; exit 0 ;;
        *)                 echo "Argumento desconocido: $1" >&2; exit 1 ;;
    esac
    shift
done

if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

SRC="${REAL_HOME}/proyectos/lefty"
TK_SRC="${REAL_HOME}/proyectos/lanetk"
DST="/opt/lefty"
TK_DST="/opt/lanetk"
STATE_DIR="/var/lib/lefty"

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: necesita root. Correlo con sudo." >&2
    exit 1
fi
if [ ! -d "$SRC/src" ]; then
    echo "install.sh: no existe $SRC/src" >&2
    exit 1
fi

# --- Helpers ---
is_void() { [ -f /etc/os-release ] && grep -q '^ID="\?void"\?$' /etc/os-release; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

MISSING=""
need_cmd() {
    if has_cmd "$1"; then
        echo "    OK      $1"
    else
        echo "    FALTA   $1"
        MISSING="$MISSING $1"
    fi
}

echo "==> Lefty — instalación en $DST"
echo "    Origen:  $SRC"
echo

# --- LaneTK ---
echo "==> Verificando LaneTK"
if [ -d "$TK_DST/src/lib" ]; then
    echo "    OK      $TK_DST (ya instalado)"
elif [ -d "$TK_SRC/src/lib" ]; then
    echo "    Instalando LaneTK primero (invocando su install.sh)..."
    if [ -x "$TK_SRC/tools/install.sh" ]; then
        "$TK_SRC/tools/install.sh" -y
    else
        echo "    FALTA: $TK_SRC/tools/install.sh no existe" >&2
        exit 1
    fi
else
    echo "    FALTA: ni $TK_DST ni $TK_SRC existen" >&2
    echo "           cloná LaneTK en ~/proyectos/lanetk y reintentá" >&2
    exit 1
fi
echo

# --- Dependencias del greeter ---
echo "==> Verificando dependencias del greeter"
echo
echo "  Daemon de sesión:"
need_cmd greetd
echo
echo "  Herramientas X necesarias por el wrapper:"
need_cmd xauth
need_cmd xdpyinfo
need_cmd xrandr
need_cmd xsetroot
need_cmd xrdb
echo
echo "  Control de sesión (elogind):"
need_cmd loginctl
echo

if [ -n "$MISSING" ]; then
    echo "==> Faltan dependencias:$MISSING"
    echo
    if is_void; then
        echo "    Paquetes sugeridos para Void:"
        echo "      xbps-install -S greetd xauth xdpyinfo xrandr xsetroot xrdb elogind"
        echo
        if [ "$INSTALL_DEPS" -eq 1 ]; then
            echo "==> Instalando dependencias (--install-deps activo)"
            xbps-install -Sy greetd xauth xdpyinfo xrandr xsetroot xrdb elogind \
                || { echo "Instalación falló" >&2; exit 1; }
        else
            echo "    Volvé a correr con --install-deps para instalarlas."
            exit 1
        fi
    else
        echo "    Instalalas a mano según tu gestor de paquetes."
        exit 1
    fi
else
    echo "==> Todas las dependencias presentes."
fi
echo

# --- Verificar PAM ---
echo "==> Verificando configuración PAM"
if [ -f /etc/pam.d/greetd ]; then
    echo "    OK      /etc/pam.d/greetd"
else
    echo "    AVISO   /etc/pam.d/greetd no existe"
    echo "            greetd necesita este archivo para autenticar."
    echo "            Copialo del paquete o crealo con:"
    echo "              auth       required  pam_securetty.so"
    echo "              auth       requisite pam_nologin.so"
    echo "              auth       include   system-local-login"
    echo "              account    include   system-local-login"
    echo "              session    include   system-local-login"
fi
echo

# --- Verificar Xwrapper.config ---
echo "==> Verificando Xwrapper.config"
if [ -f /etc/X11/Xwrapper.config ]; then
    if grep -q 'allowed_users *= *anybody' /etc/X11/Xwrapper.config; then
        echo "    OK      allowed_users = anybody"
    else
        echo "    AVISO   Xwrapper.config no permite allowed_users = anybody"
        echo "            sin esto Xorg.wrap bloquea a greeter al arrancar"
    fi
else
    echo "    AVISO   /etc/X11/Xwrapper.config no existe"
    echo "            crealo con:"
    echo "              allowed_users = anybody"
    echo "              needs_root_rights = yes"
fi
echo

# --- Verificar usuario greeter ---
echo "==> Verificando usuario greeter"
if id greeter >/dev/null 2>&1; then
    echo "    OK      usuario greeter existe"
    GREETER_HOME=$(getent passwd greeter | cut -d: -f6)
    if [ -d "$GREETER_HOME" ]; then
        echo "    OK      home $GREETER_HOME existe"
    else
        echo "    AVISO   home $GREETER_HOME no existe"
        echo "            mkdir -p $GREETER_HOME && chown greeter:greeter $GREETER_HOME"
    fi
else
    echo "    AVISO   usuario greeter no existe"
    echo "            crealo antes de habilitar greetd:"
    echo "              useradd -r -s /bin/bash -d /home/.greeter -m greeter"
fi
echo

# --- Confirmar y copiar ---
if [ -d "$DST" ] && [ "$AUTO_YES" -eq 0 ]; then
    printf "==> Se va a reemplazar $DST. Continuar? [y/N] "
    read -r ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "Cancelado."; exit 0 ;;
    esac
fi

echo "==> Copiando Lefty"
rm -rf "$DST"
mkdir -p "$DST"
tar -C "$SRC" \
    --exclude='./.git' \
    --exclude='*.bak' --exclude='*.bak-*' --exclude='*.bak.*' \
    --exclude='*.orig' --exclude='*.swp' --exclude='.DS_Store' \
    -cf - . | tar -C "$DST" -xf -

echo "==> Ajustando permisos"
chmod -R a+rX,go-w "$DST"
for f in "$DST/run" "$DST/tools/start-greeter.sh" "$DST/tools/install.sh" "$DST/tools/test-greeter.sh"; do
    [ -f "$f" ] && chmod +x "$f"
done

# --- Estado persistente ---
echo "==> Preparando $STATE_DIR"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/last-user"
chmod 0777 "$STATE_DIR"
chmod 0666 "$STATE_DIR/last-user"

# --- Verificar acceso del usuario greeter ---
if id greeter >/dev/null 2>&1; then
    echo "==> Verificando acceso de greeter a los archivos"
    failed=0
    for f in \
        "$DST/run" \
        "$DST/src/main.lua" \
        "$TK_DST/src/lib/server.lua" \
        "$TK_DST/src/lib/greetd.lua" \
        "$TK_DST/src/lib/xsessions.lua" \
        "$TK_DST/bindings/cdef/net.lua"
    do
        if sudo -u greeter test -r "$f"; then
            echo "    OK      $f"
        else
            echo "    FALLO   $f"
            failed=1
        fi
    done
    if [ "$failed" -eq 1 ]; then
        echo "install.sh: el usuario greeter no puede leer algunos archivos." >&2
        exit 1
    fi
fi

echo
echo "==> Instalación completa."
echo "    Lefty en $DST"
echo
echo "Pasos manuales que quedan por hacer (una sola vez):"
echo
echo "  1. Config de Lefty:"
echo "       sudo cp $DST/config.conf /etc/greetd/lefty.conf"
echo
echo "  2. Wrapper de greetd:"
echo "       sudo cp $DST/tools/start-greeter.sh /etc/greetd/start-greeter.sh"
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
