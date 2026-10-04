# Lefty

Greeter (pantalla de login) construido sobre **LaneTK**, el toolkit
gráfico en LuaJIT + FFI del mismo autor. Lefty es un proyecto
separado de LaneTK: vive en su propio repositorio y consume la API
pública del toolkit como cualquier otra aplicación.

Lefty se integra con **greetd** para autenticar contra PAM, y le
indica a greetd qué comando ejecutar para arrancar la sesión elegida.
Reemplaza al par `startx` + WM como punto de entrada de la sesión.

---

## Índice

1. Arquitectura
2. Requisitos
3. Instalación
4. Configuración
5. Flujo de autenticación
6. Layouts
7. Componentes
8. Documentación extendida

---

## 1. Arquitectura

    greetd
      │  ejecuta como usuario greeter, en una VT libre
      ▼
    /etc/greetd/start-greeter.sh
      │  1. arranca Xorg :N -noreset
      │  2. aplica cursor, monitor activo, xrandr
      │  3. ejecuta Lefty en modo greeter
      ▼
    Lefty
      │  UI de login. Habla con greetd por $GREETD_SOCK.
      │  Al autenticar: create_session + post_auth + start_session.
      ▼
    greetd
      │  mata al wrapper, cambia de usuario,
      │  ejecuta el comando de start_session en otra VT
      ▼
    startx  →  ~/.xinitrc  →  bin/lanetk-session  →  WM

Lefty es solo la UI del login. No es un compositor ni un WM: dibuja
una ventana `override_redirect` fullscreen sobre Xorg, autentica, y
le dice a greetd qué ejecutar. Greetd hace el resto.

Lefty usa X11 (Xorg). La sesión del usuario también es X11 en el caso
común (bspwm, i3, awesome), pero eso es decisión del comando que
Lefty le pasa a greetd.

---

## 2. Requisitos

Sistema:

- Linux con **greetd >= 0.10**.
- **Xorg**.
- **PAM** configurado para greetd (`/etc/pam.d/greetd`).
- **LuaJIT**.
- **LaneTK** instalado en `/opt/lanetk/`.

Usuario:

- Cuenta `greeter` con home en `/home/.greeter`. Es donde Xorg
  escribe `.Xauthority`.

Herramientas X en el PATH:

- `xauth`, `xdpyinfo`, `xrandr`, `xrdb`, `xsetroot`.

Ajuste de sistema:

- `/etc/X11/Xwrapper.config` con `allowed_users = anybody` y
  `needs_root_rights = yes`. Sin esto, `Xorg.wrap` bloquea a
  `greeter` con "Only console users are allowed to run the X
  server".

---

## 3. Instalación

`tools/install.sh` copia Lefty y LaneTK a `/opt/`, ajusta permisos
para que el usuario `greeter` pueda leerlos y ejecutarlos, y crea
`/var/lib/lefty/` para el estado persistente.

    cd ~/proyectos/lefty
    sudo tools/install.sh

Después:

1. Copiar `config.conf` a `/etc/greetd/lefty.conf`.

2. Copiar `tools/start-greeter.sh` a `/etc/greetd/start-greeter.sh`.

3. Configurar `/etc/greetd/config.toml`:

       [terminal]
       vt = "next"

       [default_session]
       command = "/etc/greetd/start-greeter.sh"
       user = "greeter"

4. Habilitar el servicio greetd:

       sudo ln -sf /etc/sv/greetd /var/service/greetd

El wrapper `start-greeter.sh` sigue reglas específicas para no
colgarse con greetd (framing del socket, herencia de fds, orden de
muerte de Xorg y Lefty). Están documentadas en el Apéndice E, sección
E.3.

---

## 4. Configuración

Lefty lee su config de, en orden de prioridad:

1. `$LEFTY_CONFIG` (variable de entorno).
2. `/etc/greetd/lefty.conf` (instalación de sistema).
3. `$HOME/.config/lefty/config.conf` (desarrollo o modo standalone).

El primero que exista gana.

Claves:

| Clave | Tipo | Default | Qué hace |
|---|---|---|---|
| `layout` | string | `centered` | Layout a usar. Ver sección 6. |
| `default_user` | string | (auto) | Usuario preseleccionado en modo greeter. |
| `users_blacklist` | csv | (vacío) | Nombres de usuario extra a excluir del listado. |

Los comentarios con `#` al inicio de línea se ignoran.

---

## 5. Flujo de autenticación

Lefty habla el protocolo de greetd por el socket en `$GREETD_SOCK`.
El framing es binario: cada mensaje tiene la forma

    <uint32 length, native byte order> <JSON payload>

No es newline-delimited. El cliente Lua está en LaneTK
(`lib/greetd.lua`).

Secuencia completa:

    lefty                            greetd
      │                                │
      │  create_session(username)      │
      │───────────────────────────────>│
      │                                │  consulta PAM
      │  auth_message {                │
      │    auth_message_type: "secret" │
      │    auth_message: "Password: "  │
      │  }                             │
      │<───────────────────────────────│
      │                                │
      │  post_auth_message_response    │
      │    { response: "..." }         │
      │───────────────────────────────>│
      │                                │
      │  success                       │
      │<───────────────────────────────│
      │                                │
      │  escribe /tmp/lanetk-wm-choice │
      │  start_session {               │
      │    cmd: ["startx"]             │
      │  }                             │
      │───────────────────────────────>│
      │                                │  mata al wrapper,
      │                                │  cambia de usuario,
      │                                │  ejecuta cmd

Si `create_session` falla (usuario desconocido, error de PAM), llega
un mensaje `error` con `error_type` (`auth_error` o `error`) y
`description`. Lefty lo muestra en pantalla y limpia el campo de
contraseña.

`start_session` **no espera respuesta**. Greetd mata al wrapper y
lanza la sesión. Lefty sale con `os.exit(0)` inmediatamente después
de mandar el mensaje.

El comando que Lefty le pasa a greetd es **`["startx"]` a secas**, no
`startx <cliente>`. Con un cliente explícito, `startx` ignora
`~/.xinitrc` y arranca el WM sin la cadena de autostart del toolkit.
El motivo está en el Apéndice E, sección E.2.

El WM que el usuario elige en la UI se pasa a `start_session` a
través de `/tmp/lanetk-wm-choice`. Greetd no lo interpreta: lo lee
`bin/lanetk-session` al arrancar la sesión y lo persiste en
`~/.config/lanetk/wm`. El motivo (permisos del home del usuario
final) está en el Apéndice E, sección E.4.

Después del `success` y antes de `start_session`, Lefty registra el
usuario en `/var/lib/lefty/last-user`. La próxima vez, ese usuario
se preselecciona.

---

## 6. Layouts

Un layout es un módulo Lua en `src/layouts/<name>.lua` que exporta
`M.build(ctx)`. Recibe un contexto con los widgets ya construidos y
devuelve el `Area` raíz del árbol.

`ui.lua` construye todos los widgets siempre y los pasa en `ctx`. El
layout decide cuáles usa y dónde los pone. Agregar un layout nuevo no
toca `ui.lua`.

### `ctx` — widgets

| Campo | Tipo | Qué es |
|---|---|---|
| `avatar` | `Area` | Avatar circular del usuario |
| `name_lbl` | `Text` | Nombre del usuario |
| `pass_input` | `TextInput` | Campo de contraseña |
| `go_btn` | `Button` | Botón de submit |
| `eye_btn` | `Icon` | Toggle de visibilidad de la contraseña |
| `error_lbl` | `Text` | Mensaje de error |
| `pills_container` | `PillDock` | Dock de pills de sesión |
| `user_dock` | `PillDock` o `nil` | Dock de pills de usuario (nil si hay uno solo) |
| `power_row` | `Group` | Fila de botones de power |
| `pwr_power`, `pwr_reboot`, `pwr_suspend` | `PowerButton` | Botones individuales |
| `clock_lbl` | `Text` | Reloj en formato `HH:MM` |
| `date_lbl` | `Text` | Fecha en español |

### `ctx` — clases

- **`Card`** — contenedor con fondo redondeado.
- **`FloatingBlock`** — bloque anclado a una esquina, sin ocupar
  espacio en el flujo del padre. `anchor`: `"top-left"` (default),
  `"top-right"`, `"bottom-left"`, `"bottom-right"`.
- **`Overlay`** — contiene hijos y les da a todos el rect completo.
  Los hijos se superponen, el último añadido se dibuja encima.
- **`PillDock`** — dock de pills que se expanden al hover.
- **`SessionPill`**, **`UserPill`**, **`PowerButton`**.

### `ctx` — contexto y helpers

| Campo | Tipo | Qué es |
|---|---|---|
| `srv` | `Server` | Event loop del toolkit |
| `theme` | tabla | Paleta activa |
| `username` | string | Usuario actual |
| `sessions` | tabla | Sesiones X disponibles |
| `current_idx` | int | Índice de la sesión seleccionada |
| `spacer(n)` | función | Text de altura fija, para separar en un `Group` |
| `centered(w)` | función | Group horizontal con spacers laterales |
| `clock_str()` | función | Hora actual en `HH:MM` |
| `date_str()` | función | Fecha actual en español |

### Layouts disponibles

- **`centered`** — reloj arriba-izquierda. Card centrada verticalmente
  con avatar, nombre, input, pills de sesión y power.
- **`win10`** — inspirado en la pantalla de login de Windows 10.
  Reloj grande abajo-izquierda con fecha al lado, pills de sesión
  arriba-derecha, power abajo-derecha, avatar y nombre centrados.

---

## 7. Componentes

Lefty aporta:

- **`src/main.lua`** — entry point. Parsea argumentos, construye la
  ventana, corre el event loop y maneja el flujo greetd.
- **`src/ui.lua`** — árbol de widgets del greeter. Construye todos
  los widgets y los pasa al layout vía `ctx`. Expone los callbacks
  `on_login` y `on_power`, y los accesos `current_username` y
  `record_login`.
- **`src/layouts/*.lua`** — composición visual.
- **`run`** — arranque. Resuelve `LUA_PATH` con las dos raíces
  (Lefty y LaneTK) y ejecuta `luajit`.
- **`tools/install.sh`** — instalación en `/opt/`.
- **`tools/start-greeter.sh`** — wrapper de producción que greetd
  invoca.
- **`tools/test-greeter.sh`** — arranca Lefty en Xephyr para probar
  la UI sin greetd ni VT.

Lefty consume de LaneTK:

- `lib.greetd` — cliente del protocolo greetd.
- `lib.xsessions` — lectura de `/usr/share/xsessions/*.desktop`.
- `lib.data.users` — usuarios del sistema desde `/etc/passwd`.
- `lib.data.last_user` — último login persistido.
- `lib.data.inicio` — avatar, hostname, etc.
- `lib.theme` — paleta activa.
- `lib.icon_theme` — iconos del tema GTK activo.
- `lib.widgets.*` — árbol de widgets.
- `lib.server`, `lib.window`, `lib.xcb` — infraestructura.

---

## 8. Documentación extendida

- **`docs/APENDICE-E.md`** — bugs de integración con greetd, causas
  raíz, técnicas de debugging y anti-patrones.
