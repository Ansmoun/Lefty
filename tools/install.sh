#!/bin/sh
set -e

if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

LEFTY_SRC="$REAL_HOME/proyectos/lefty"
TK_SRC="$REAL_HOME/proyectos/lanetk"
LEFTY_DST="/opt/lefty"
TK_DST="/opt/lanetk"
GREETER_HOME=$(getent passwd greeter | cut -d: -f6)

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: hay que correrlo con sudo" >&2
    exit 1
fi

echo "[lefty-install] usuario real: $SUDO_USER (home: $REAL_HOME)"

echo "[lefty-install] sincronizando toolkit a $TK_DST"
rm -rf "$TK_DST"
cp -a "$TK_SRC" "$TK_DST"
rm -rf "$TK_DST/.git" "$TK_DST/docs" "$TK_DST/examples" "$TK_DST/tests"
find "$TK_DST" -name '*.bak*' -type f -delete 2>/dev/null || true
find "$TK_DST" -name '*.orig'  -type f -delete 2>/dev/null || true

echo "[lefty-install] sincronizando lefty a $LEFTY_DST"
rm -rf "$LEFTY_DST"
cp -a "$LEFTY_SRC" "$LEFTY_DST"
rm -rf "$LEFTY_DST/.git"
# NO borrar tools/: ahi vive start-greeter.sh, que se invoca desde
# /etc/greetd/start-greeter.sh. Si lo borramos, el wrapper queda
# colgado. Los install.sh dentro de tools/ son inofensivos, no se
# ejecutan desde ahi.
find "$LEFTY_DST" -name '*.bak*' -type f -delete 2>/dev/null || true
find "$LEFTY_DST" -name '*.orig'  -type f -delete 2>/dev/null || true

touch /var/log/lefty-greeter.log
chown greeter:greeter /var/log/lefty-greeter.log
chmod 0644 /var/log/lefty-greeter.log
echo "[lefty-install] ajustando permisos"
mkdir -p /var/lib/lefty
chmod 0777 /var/lib/lefty
if [ ! -f /var/lib/lefty/last-user ]; then
    touch /var/lib/lefty/last-user
    chmod 0666 /var/lib/lefty/last-user
fi

# Directorio de estado compartido entre greeter y el usuario final.
# last-user es el ultimo usuario que se autentico, para
# preseleccionarlo. Mode 0777 en el dir + archivo 0666 para que
# ambos puedan escribirlo.
mkdir -p /var/lib/lefty
chmod 0777 /var/lib/lefty
if [ ! -f /var/lib/lefty/last-user ]; then
    touch /var/lib/lefty/last-user
    chmod 0666 /var/lib/lefty/last-user
fi
chmod -R a+rX,go-w "$TK_DST"
chmod -R a+rX,go-w "$LEFTY_DST"
chmod +x "$LEFTY_DST/run"
chmod +x "$TK_DST/run" 2>/dev/null || true
[ -f "$LEFTY_DST/tools/start-greeter.sh" ] && \
    chmod +x "$LEFTY_DST/tools/start-greeter.sh" || true

echo ""
echo "[lefty-install] verificando como usuario greeter..."
if sudo -u greeter test -r "$LEFTY_DST/run" \
   && sudo -u greeter test -r "$TK_DST/src/lib/server.lua"; then
    echo "  OK: greeter puede leer /opt/lefty y /opt/lanetk"
else
    echo "  ERROR: greeter NO puede leer los archivos." >&2
    exit 1
fi

if sudo -u greeter test -x "$LEFTY_DST/run"; then
    echo "  OK: /opt/lefty/run es ejecutable por greeter"
else
    echo "  ERROR: /opt/lefty/run no es ejecutable por greeter" >&2
    exit 1
fi

echo ""
echo "[lefty-install] listo."
