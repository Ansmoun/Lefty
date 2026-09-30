# Lefty

Greeter (pantalla de login) construido sobre **LaneTK**, el toolkit
gráfico en LuaJIT + FFI del mismo autor. Lefty es un producto de
LaneTK, no parte del toolkit: vive en su propio repositorio y
consume la API pública de LaneTK como cualquier otra aplicación.

Nombre: "lefty" en referencia a la mano zurda, y al gesto de
extenderla para abrir una puerta. Es lo primero que ve el usuario
al encender el equipo.

---

## Índice

1. Arquitectura
2. Estructura del repositorio
3. Cómo correr
4. Instalación en /opt/
5. Integración con greetd
6. Configuración
7. Layouts
8. Flujo de autenticación
9. Cómo probar
10. Componentes reutilizables
11. Troubleshooting
12. Anti-patrones
13. Decisiones de diseño

-------------------------------+
    |            greetd             |
    |  daemon: PAM, VTs, logind     |
    +---------------+---------------+
                    |
                    | ejecuta como usuario greeter
                    | en la VT que le asigna
                    v
    +-------------------------------+
    |  /etc/greetd/start-greeter.sh |
    |  1. Arranca Xorg :0           |
    |  2. Ajusta cursor, monitor    |
    |  3. Corre /opt/lefty/run      |
    |     src/main.lua --greeter    |
    +---------------+---------------+
                    |
                    v
    +-------------------------------+
    |         Lefty (LuaJIT)        |
    |  - UI del login               |
    |  - Habla con greetd por el    |
    |    socket Unix ($GREETD_SOCK) |
    |  - Al autenticar:             |
    |    create_session,            |
    |    post_auth,                 |
    |    start_session(cmd)         |
    +---------------+---------------+
                    |
                    | greetd mata al wrapper y lanza
                    | la sesión del usuario en otra VT
                    v
    +-------------------------------+
    |  startx /usr/bin/env bspwm    |
    |  como el usuario autenticado  |
    +-------------------------------+

Lefty **no** es un compositor ni un WM. Solo dibuja la UI, autentica,
y le dice a greetd qué comando ejecutar. greetd hace el resto.

Lefty **no** usa Wayland. Corre sobre Xorg vía el binding XCB de
LaneTK. La sesión final del usuario también es X11 (bspwm, awesome,
etc.), pero eso es independiente: greetd podría lanzar un compositor
Wayland si estuviera configurado así.

---

## 2. Estructura del repositorio

    ~/proyectos/lefty/
    |-- README.md              -- este archivo
    |-- config.conf            -- plantilla de config (se copia a /etc/greetd/)
    |-- run                    -- arranque: setea LUA_PATH y ejecuta luajit
    |-- src/
    |   |-- main.lua           -- entry point, flujo greetd
    |   |-- ui.lua             -- árbol de widgets, clases, carga de layouts
    |   +-- layouts/
    |       |-- centered.lua   -- reloj arriba-izq + card centrada
    |       +-- win10.lua      -- reloj abajo-izq, pills arriba-der, power abajo-der
    |-- assets/
    |   +-- icons/             -- iconos propios (vacío, se usan los de LaneTK)
    +-- tools/
        |-- install.sh         -- copia lefty y LaneTK a /opt/ para greeter
        |-- test-greeter.sh    -- corre lefty en Xephyr (ventana anidada)
        +-- start-greeter.sh   -- wrapper de producción (lo invoca greetd)

El `run` resuelve LUA_PATH con dos raíces:

- `$LEFTY/src/?.lua` -- los módulos de lefty (ui, layouts.*).
- `$TK/?.lua` y `$TK/src/?.lua` -- el toolkit LaneTK
  (lib.server, lib.theme, lib.widgets, bindings.cdef.*).

`$TK` se resuelve en orden: si `LEFTY == /opt/lefty` y existe
`/opt/lanetk/src/lib`, se usa `/opt/lanetk`. Si no, se usa
`$LANETK_DIR` o `$HOME/proyectos/lanetk` (desarrollo).

---

## 3. Cómo correr

### Modo standalone (desarrollo, desde tu sesión X)

    cd ~/proyectos/lefty
    ./run src/main.lua --standalone

Abre una ventana normal 500x620, con el layout indicado en
`~/.config/lefty/config.conf` o el que se pase por CLI con
`--layout <name>`.

Argumentos:

- `--standalone` -- modo ventana normal. Default.
- `--greeter` -- modo fullscreen override_redirect (para greetd).
- `--user <name>` -- fuerza un usuario específico (útil para testing).
- `--layout <name>` -- fuerza un layout (centered, win10, win8, gnome).

En modo standalone, `on_login` intenta conectar con greetd. Como no
hay socket ($GREETD_SOCK no existe), falla y muestra un error. Es lo
esperado: en standalone solo se prueba la UI.

### Modo test con Xephyr (recomendado)

    cd ~/proyectos/lefty
    ./tools/test-greeter.sh            # usa el layout del config
    ./tools/test-greeter.sh centered   # fuerza centered
    ./tools/test-greeter.sh win10      # fuerza win10

Arranca un Xephyr (servidor X anidado) en un display libre entre :90
y :99, corre lefty adentro, y cuando cerrás la ventana todo termina.
No toca greetd, no requiere sudo, no requiere reiniciar la sesión.

Variables: SCREEN_W y SCREEN_H para el tamaño de la ventana
(default 1024x768).

### Modo producción

Lo invoca greetd. No se corre a mano.

---

## 4. Instalación en /opt/

El usuario greeter (con el que corre greetd) necesita poder leer lefty
y LaneTK. Como no tiene home propio más que /home/.greeter, y no
puede leer /home/ansmoun/proyectos/, se instala todo en /opt/.

    cd ~/proyectos/lefty
    sudo tools/install.sh

El script:

1. Copia ~/proyectos/lanetk/ a /opt/lanetk/, excluyendo .git, docs/,
   examples/, tests/, *.bak*, *.orig.
2. Copia ~/proyectos/lefty/ a /opt/lefty/, excluyendo .git, *.bak*,
   *.orig. NO excluye tools/: ahí vive el wrapper.
3. Ajusta permisos: chmod -R a+rX,go-w, más +x en los scripts.
4. Crea /var/lib/lefty/ con last-user escribible por todos.
5. Verifica que el usuario greeter puede leer y ejecutar.

Se corre cada vez que se cambia el código de lefty o del toolkit y se
quiere probar en condiciones "reales". En desarrollo diario no hace
falta: se usa ./run src/main.lua --standalone o ./tools/test-greeter.sh.

---

## 5. Integración con greetd

Config de greetd (/etc/greetd/config.toml):

    [terminal]
    vt = "next"

    [default_session]
    command = "/etc/greetd/start-greeter.sh"
    user = "greeter"

Wrapper /etc/greetd/start-greeter.sh: es una copia de
tools/start-greeter.sh. El wrapper:

1. Detecta el monitor activo (VGA-1 si está conectado, si no LVDS-1).
2. Arranca Xorg :0 -seat seat0 -nolisten tcp vt$XDG_VTNR -auth <file> -noreset.
3. Espera hasta 5 s a que Xorg responda a xdpyinfo.
4. Apaga el monitor inactivo con xrandr --output OTHER --off.
5. Corre /opt/lefty/run /opt/lefty/src/main.lua --greeter.
6. Al terminar lefty, mata Xorg.

El wrapper no arranca un WM. Lefty se dibuja directamente sobre el
root de Xorg como ventana override_redirect.

Cadena de usuario:

- greetd corre el wrapper como usuario greeter (uid 1001, home
  /home/.greeter).
- greeter no tiene shell de login útil: es una cuenta de servicio.
- Al autenticar, greetd cambia a la sesión del usuario final.
- El wrapper muere (junto con Xorg y lefty) y greetd lanza el comando
  que lefty le pasó en start_session.

Ajustes de sistema que hacen falta:

/etc/X11/Xwrapper.config:

    allowed_users = anybody
    needs_root_rights = yes

Sin esto, Xorg.wrap bloquea a greeter con "Only console users are
allowed to run the X server".

Usuario greeter con home:

    sudo mkdir -p /home/.greeter
    sudo chown greeter:greeter /home/.greeter
    sudo chmod 700 /home/.greeter

El home es donde Xorg escribe .Xauthority. Sin él, Xorg falla al
generar la cookie.

Herramientas X necesarias en /usr/sbin (Void):

    xauth xdpyinfo xrandr xrdb xsetroot xorg-server-xephyr

El wrapper exporta PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH" al
inicio, porque greetd corre con un PATH mínimo.

---

## 6. Configuración

Lefty lee su config de, en orden de prioridad:

1. $LEFTY_CONFIG -- variable de entorno (override manual).
2. /etc/greetd/lefty.conf -- instalación de sistema (modo greeter).
3. $HOME/.config/lefty/config.conf -- desarrollo, o modo standalone.

El primero que exista gana. En modo greeter, $HOME es /home/.greeter,
así que el archivo 3 no aplica: siempre se lee de /etc/greetd/lefty.conf.

Claves:

| Clave | Tipo | Default | Qué hace |
|---|---|---|---|
| layout | string | centered | Layout a usar. Ver sección 8. |
| users_blacklist | csv | (vacío) | Nombres de usuario extra a excluir del listado. |

Los comentarios con # al inicio de línea se ignoran.

Cuando se agregue soporte de wallpaper y fondo de card, las claves
van a sumarse acá. Ver sección 15 (pendientes).

---

## 7. Layouts

Un layout es un módulo Lua en src/layouts/<name>.lua que exporta una
función M.build(ctx). La función recibe un ctx (contexto) con todos
los widgets ya construidos, y devuelve el Area raíz del árbol.

### Contrato

ctx contiene:

Widgets de contenido:

- avatar          Area      -- avatar circular del usuario
- name_lbl        Text      -- nombre del usuario
- pass_input      TextInput -- campo de contraseña (con ojo adentro)
- go_btn          Button    -- botón submit (flecha)
- eye_btn         Icon      -- el icono de ojo (dentro del input)
- error_lbl       Text      -- mensaje de error
- pills_container PillDock  -- dock de pills de sesión
- power_row       Group     -- fila de power buttons
- clock_lbl       Text      -- reloj en formato HH:MM
- date_lbl        Text      -- fecha en español
- user_dock       PillDock  -- dock de pills de usuario (nil si 1 usuario)

Power buttons individuales (por si el layout quiere recomponer):

- pwr_power       PowerButton
- pwr_reboot      PowerButton
- pwr_suspend     PowerButton

Clases y helpers:

- Card            clase -- contenedor con fondo
- FloatingBlock   clase -- bloque anclado a una esquina, sin ocupar espacio
- Overlay         clase -- contenedor que da a los hijos el rect completo
- PillDock        clase -- dock de pills que se expanden al hover
- PowerButton     clase
- SessionPill     clase

Contexto:

- srv             Server -- event loop
- theme           tabla  -- paleta activa (theme.fg_rgb, theme.accent_rgb, ...)
- username        string -- usuario actual
- sessions        tabla  -- sesiones X disponibles
- current_idx     int    -- índice de la sesión actual

Helpers:

- spacer(n)       -> Text con min_h = max_h = n (para separar en un Group)
- centered(w)     -> Group horizontal con spacers laterales (centra w)

Funciones:

- clock_str()     -> string -- hora actual "HH:MM"
- date_str()      -> string -- fecha actual en español

### Clases auxiliares

FloatingBlock.new { content, anchor, block_width, block_height }

Dibuja content en una esquina del rect que se le asigne, sin ocupar
espacio en el flujo del padre. anchor puede ser "top-left" (default),
"top-right", "bottom-left", "bottom-right".

Overlay.new {}

Contiene varios hijos y les da a todos el rect completo del Overlay.
Los hijos se superponen, el último añadido se dibuja encima. Es la
forma correcta de componer un layout con varios elementos flotantes:
Overlay:add(center_col); Overlay:add(clock_block); ...

PillDock.new { spacing, row_height, align }

Contiene pills (SessionPill o UserPill) que se expanden al hover.
Reposiciona los pills en cada frame según su hover_t actual, sin pedir
relayout. align puede ser "left", "center" (default) o "right".

### Layouts disponibles

centered -- el primero. Reloj flotante arriba-izquierda (hora +
fecha, tamaño normal). Card de ancho completo centrada verticalmente
con: avatar 140, nombre, input, pills de sesión, power buttons.

win10 -- inspirado en la pantalla de login de Windows 10. Reloj
grande (56pt) abajo-izquierda con la fecha al lado. Pills de sesión
arriba-derecha. Power abajo-derecha. Centro: avatar 140, nombre
grande, input.

win8, gnome -- pendientes.

### Escribir un layout nuevo

1. Copiar src/layouts/centered.lua como base.
2. Renombrar a src/layouts/<name>.lua.
3. Rearmar el árbol con los widgets que vienen en ctx.
4. Probar con ./tools/test-greeter.sh <name>.

No hace falta tocar ui.lua. El ui.lua construye todos los widgets
siempre y los pasa en ctx. El layout decide cuáles usar y dónde
ponerlos. Si un layout no usa un widget, simplemente no lo agrega al
árbol.

---

## 8. Flujo de autenticación

El protocolo de greetd es JSON line-delimited sobre un socket Unix. El
path está en $GREETD_SOCK. La implementación en LaneTK está en
lib/greetd.lua.

Secuencia:

    lefty                            greetd
      |                                |
      |  create_session(username)      |
      |------------------------------->|
      |                                | consulta PAM
      |  auth_message {                |
      |    auth_message_type: "secret" |
      |    auth_message: "Password: "  |
      |  }                             |
      |<-------------------------------|
      |                                |
      |  post_auth_message_response    |
      |    { response: "hunter2" }     |
      |------------------------------->|
      |                                |
      |  success                       |
      |<-------------------------------|
      |                                |
      |  start_session {               |
      |    cmd: ["startx",             |
      |          "/usr/bin/env",       |
      |          "bspwm"]              |
      |  }                             |
      |------------------------------->|
      |                                | greetd mata al wrapper,
      |                                | cambia de usuario, ejecuta cmd

Si create_session falla (usuario desconocido, PAM error), llega un
error con error_type (auth_error, error) y description. Lefty muestra
la descripción en error_lbl y limpia el campo de contraseña.

Si el usuario cambia de sesión con los pills, el cmd que se le pasa a
start_session corresponde a la sesión elegida.

Después del success y antes de start_session, lefty registra el
usuario en /var/lib/lefty/last-user vía tab.record_login(). La próxima
vez, ese usuario se preselecciona.

src/main.lua implementa todo el flujo. src/ui.lua solo se ocupa de la
UI y expone los callbacks (on_login, on_power) más los accesos
(current_username, record_login).

---

## 9. Cómo probar

Test rápido de UI (sin greetd):

    ./tools/test-greeter.sh centered

Cerrás la ventana y termina. No toca nada del sistema.

Test de la autenticación contra un mock:

El flujo de greetd se puede probar contra un servidor mock que
implemente el protocolo. Ese mock está documentado en las notas del
toolkit LaneTK (docs/notes.md), donde se usó para validar
lib/greetd.lua antes de escribir lefty.

Test del wrapper de producción sin reiniciar:

    sudo -u greeter -H /opt/lefty/tools/start-greeter.sh --test

Arranca Xorg en :2 / vt8 (que no choca con tu sesión :0 o :1). Cambiás
a Ctrl+Alt+F8 para ver el resultado, y volvés con Ctrl+Alt+F7. No es
necesario reiniciar.

Test de instalación:

    sudo -u greeter /opt/lefty/run -e '
      require("lib.server")
      require("ui")
      print("requires OK")
    '

Verifica que el usuario greeter puede cargar todos los módulos del
toolkit y de lefty.

---

## 10. Componentes reutilizables

Los siguientes módulos viven en LaneTK (/opt/lanetk/src/lib/) y se
consumen desde lefty. No son parte de lefty.

- lib.greetd -- cliente del protocolo greetd.
- lib.xsessions -- lectura de /usr/share/xsessions/*.desktop.
- lib.data.users -- usuarios del sistema.
- lib.data.last_user -- último login.
- lib.data.inicio -- avatar, nombre de usuario, hostname, etc.
- lib.icon_theme -- iconos del tema GTK activo.
- lib.theme -- paleta activa.
- lib.widgets.* -- el árbol de widgets.
- lib.server, lib.window, lib.xcb -- infraestructura.

Lefty aporta:

- ui.lua -- composición del árbol, clases específicas del greeter
  (Avatar, Card, SessionPill, UserPill, PowerButton, FloatingBlock,
  Overlay, PillDock).
- layouts/*.lua -- composición visual.
- main.lua -- entry point y flujo de autenticación.

---

## 11. Troubleshooting

El greeter no arranca (pantalla negra):

1. Ver el log de greetd: sudo tail -60 /var/log/greetd/current.
2. Ver el log del wrapper: /tmp/lefty-greeter.log si el wrapper
   escribe uno.
3. Verificar que greeter puede leer /opt/lefty y /opt/lanetk:
   sudo -u greeter test -r /opt/lefty/run && echo OK.

Bucle de respawn:

Si el wrapper arranca, falla, y greetd lo relanza cada 3 segundos, el
problema suele estar en el wrapper. Candidatos:

- Xorg.wrap bloqueando por falta de Xwrapper.config.
- Falta $HOME/.Xauthority (el usuario greeter no tiene home).
- xdpyinfo no está en el PATH.
- lefty crashea al construir la UI (mirar el log).

El cursor es invisible:

Xephyr necesita -sw-cursor y XCURSOR_THEME en el entorno. El wrapper
de test ya lo hace. En producción, Xorg del sistema debería tener un
cursor por defecto, pero conviene exportar XCURSOR_THEME y
XCURSOR_SIZE en el wrapper antes de arrancar Xorg.

Los iconos no se ven:

Los iconos de sesión y power están en icons-png/ de LaneTK. Si el
greeter corre como usuario greeter, hay que asegurar que ese
directorio sea legible. El wrapper de test resuelve el path con
LANETK_ICONS_DIR o /opt/lanetk/icons-png. Ver ui.lua,
resolve_icons_dir.

El avatar no aparece:

Lefty busca el avatar con lib.data.inicio.find_avatar(username). El
username se pasa explícito, no se usa $USER. Si el usuario no tiene
avatar, se muestra la inicial del nombre en un círculo.

Las conversiones de JPEG/BMP a PNG se cachean en
~/.cache/lanetk/avatar-<username>.png. El ~ es el del proceso que
corre lefty. En producción, eso es /home/.greeter/.cache/, y el
archivo debe poder escribirse.

La sesión elegida no es la que se lanza:

lib.xsessions.build_command(id) arma { "startx", "/usr/bin/env",
<exec> } a partir del Exec= del .desktop. Si el Exec= del .desktop no
es el comando correcto (por ejemplo, falta startx alrededor), la
sesión falla o no arranca. Verificar el .desktop correspondiente en
/usr/share/xsessions/.

Después de elegir un usuario en el selector, todo sigue igual:

El UserPill solo actualiza el avatar y el nombre al hacer click.
update_user_visuals se llama desde el on_click de cada pill. Si los
widgets no cambian, es probable que update_user_visuals no esté
definida en el scope correcto o que el pill no esté capturando bien
el callback.

---

## 12. Anti-patrones

Documentados para no repetirlos.

13.1. Config en $HOME del usuario que corre el proceso.

El greeter corre como greeter, cuyo $HOME es /home/.greeter. Los paths
hardcodeados a ~/proyectos/lanetk/... no resuelven. La config debe
vivir en /etc/greetd/lefty.conf (path del sistema) y los recursos en
/opt/ (accesibles por todos). $HOME solo se usa como último recurso,
en modo standalone.

13.2. $HOME = /root con sudo.

Cuando un script se corre con sudo, $HOME pasa a ser /root. Los paths
como $HOME/proyectos/lefty dejan de funcionar. Solución: leer
$SUDO_USER y consultar /etc/passwd para obtener el home real, o tomar
$SUDO_USER como referencia.

13.3. Forward references en Lua sin declaración.

    local function f()
        return g()  -- g todavia no esta definida
    end
    local function g() return 42 end

En Lua, g dentro de f se resuelve como global si en el momento de
compilar f no hay una local g en scope. Al ejecutar, g es nil y
crashea con "attempt to call global 'g' (a nil value)". Solución:

    local g  -- forward declaration
    local function f()
        return g()
    end
    g = function() return 42 end

La declaración va arriba; la asignación abajo. Es feo pero es la forma
de Lua.

13.4. install.sh que borra tools/.

Al sincronizar ~/proyectos/lefty/ a /opt/lefty/, borrar tools/ elimina
el propio wrapper de producción que greetd necesita. El wrapper vive
dentro de /opt/lefty/tools/. Si se sincroniza, no excluirlo.

13.5. Xorg.wrap bloqueando usuarios no-console.

Ejecutar Xorg desde una sesión gráfica ya abierta falla con "Only
console users are allowed to run the X server". Es una política de
seguridad. Para desarrollo hay que usar Xephyr. Para producción,
greetd ya pone al usuario en una VT, así que Xorg.wrap no bloquea. Si
en algún momento se necesita correr Xorg fuera de una VT, ajustar
/etc/X11/Xwrapper.config.

13.6. xauth con cookie vacío.

Xorg no genera .Xauthority por sí solo. Un archivo vacío hace que
xdpyinfo (y cualquier cliente) no pueda conectar. Solución: generar
una cookie antes de arrancar Xorg:

    xauth -f "$XAUTH" add "$DISPLAY" . "$(mcookie)"

O pasar un archivo -auth con contenido válido.

13.7. Herramientas X fuera del PATH de greetd.

greetd corre con un PATH mínimo (/bin:/usr/bin, típicamente). En Void,
xdpyinfo, xrandr, xrdb viven en /usr/sbin. Sin ajustar el PATH, el
wrapper falla con "command not found". Solución:

    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

al inicio.

13.8. Xephyr -cursor no existe.

La opción correcta es -sw-cursor. Y aun con el flag, el cursor es
invisible si el entorno no tiene XCURSOR_THEME definido. Hay que
exportarlo antes de arrancar Xephyr, y aplicar xsetroot + xrdb -merge
adentro.

13.9. /etc/passwd tiene decenas de usuarios "del sistema".

Filtrar por uid >= 1000 (usuarios reales), shell de login válida
(/bin/bash, /bin/sh, etc., excluir /sbin/nologin y /bin/false), y una
blacklist explícita (greeter, nobody, más los que el config liste).

13.10. POLLHUP del socket XCB.

Cuando el servidor X muere (por ejemplo, cerrar la ventana de Xephyr),
lefty recibe POLLHUP en el fd de XCB y sale limpio. El log dice "fd de
XCB roto (POLLHUP/POLLERR), cerrando". No es un bug: es la detección
de que el otro extremo cerró la conexión. En el toolkit, ver
lib.poll.wait_readable y lib.server._loop.

---

## 13. Decisiones de diseño

- Lefty es un proyecto separado de LaneTK. El toolkit provee la API;
  lefty consume la API como cualquier otra aplicación. Esto permite
  que lefty tenga su propio README, sus propios tests, su propia
  instalación.
- Sin Wayland. El binding XCB de LaneTK es X11 puro. La sesión del
  usuario también es X11. Wayland añadiría una capa de complejidad que
  no hace falta para este caso.
- Sin WM en el greeter. Lefty se dibuja como ventana override_redirect
  fullscreen directamente sobre Xorg. No hay bspwm, i3, ni similar
  corriendo en el greeter.
- Layouts intercambiables por archivo. Un layout es un módulo Lua con
  M.build(ctx). Agregar uno nuevo no toca ui.lua. Esto permite iterar
  estilos sin riesgo de romper la lógica común.
- Widgets construidos antes del layout. ui.lua construye el avatar,
  input, pills, etc. una sola vez y los pasa en ctx. El layout solo
  los posiciona. Esto evita duplicar la lógica de construcción en
  cada layout.
- Usuarios descubiertos desde /etc/passwd. No se hardcodea el username
  en el config. El selector de usuarios aparece solo si hay 2 o más
  usuarios reales. El último login se guarda en
  /var/lib/lefty/last-user para preseleccionar.
- /opt/ para la instalación. El usuario greeter no puede leer
  /home/ansmoun/proyectos/. Los proyectos se copian a /opt/lanetk/ y
  /opt/lefty/, legibles por todos. En desarrollo se sigue editando en
  ~/proyectos/; install.sh sincroniza cuando hace falta.
- Xephyr para tests. Correr el greeter en Xorg requiere VT y políticas
  de consola. Xephyr permite probar la UI en una ventana anidada, sin
  sudo, sin reiniciar la sesión.

## Licencia

Mismo autor que LaneTK. Sin licencia formal por ahora.
