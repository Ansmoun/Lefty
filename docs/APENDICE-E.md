# Apéndice E — Integración con greetd

Registro de los bugs, causas raíz, soluciones y técnicas de debugging
encontrados durante la puesta en marcha de Lefty con greetd 0.10.3 en
Void Linux + Xorg + bspwm. Consultar antes de tocar el flujo de login.

---

## E.1 — Protocolo de greetd: uint32 + JSON, no newline-delimited

**Síntoma**: greetd cierra el socket ~2 segundos después de recibir
`create_session`. El cliente Lua ve `io_error`. El log de greetd dice
`check_children: greeter exited without creating a session` en bucle.

**Causa raíz**: `lib/greetd.lua` mandaba `<JSON>\n` (newline-delimited,
como si fuera un socket de texto). Greetd 0.10.3 usa un framing binario:

    <uint32 length, native byte order> <JSON payload>

Greetd lee los primeros 4 bytes del JSON (por ejemplo `{"us` =
`0x7b227573` ≈ 2 mil millones) como si fuera la longitud del payload.
Espera 2 mil millones de bytes. Timeout interno a los 2s. Cierra.

**Solución**: `_send` y `_read_line` en `lib/greetd.lua` con prefijo de
4 bytes little-endian. Ya está aplicado. Para verificar:

    grep -n 'payload_len\|bit.band\|bit.lshift' src/lib/greetd.lua

**Referencia**: https://man.sr.ht/~kennylevinsen/greetd/ipc.md

---

## E.2 — `startx <cliente>` ignora `~/.xinitrc`

**Síntoma**: al autenticar, arranca el WM "de stock" sin autostart del
toolkit (sin dock, sin wallpaper, sin launcher). O el sistema se cuelga.

**Causa raíz**: `lib/xsessions.lua:build_command` devolvía
`{"startx", "/usr/bin/env", exec}`. Con un cliente explícito, `startx`
lo lanza directo **sin leer `~/.xinitrc`**. Eso rompe la cadena:

    startx -> ~/.xinitrc -> bin/lanetk-session -> autostart + WM

**Solución**: devolver `{"startx"}` a secas. El WM elegido viaja por
`/tmp/lanetk-wm-choice` (ver E.4).

---

## E.3 — El wrapper debe morir RÁPIDO cuando greetd manda SIGTERM

Reglas para `tools/start-greeter.sh`:

1. **`-noreset`, no `-terminate`**. Con `-terminate`, Xorg se suicida
   tras el último cliente (el `xdpyinfo` del health-check) y deja al
   greeter sin servidor.

2. **No `chvt` en cleanup**. Greetd gestiona los VTs. Pelearse con él
   por el VT cuelga el sistema. El rescue script sí puede usarlo, pero
   el wrapper no.

3. **Cleanup sin sleeps largos**. Un `sleep 2` final hace que greetd
   espere 2s por cada autenticación, acumulando timeouts.

4. **Lefty en background (`&`)**, no foreground. Con `sudo` de por
   medio, SIGTERM no llega al proceso hijo. Hay que capturar el PID y
   matarlo explícitamente desde el trap.

5. **Xorg en subshell que cierra fds > 2**. Sin esto, Xorg hereda el
   socket del session-worker de greetd. Al morir el wrapper, Xorg sigue
   vivo (por `-noreset`), mantiene el socket abierto, y greetd nunca
   detecta EOF. Deadlock.

6. **`_kill_xorg_bounded`**: matar Xorg con TERM, esperar hasta 1s,
   luego KILL. Sin esta espera, Xorg queda huérfano manteniendo el VT
   y `/tmp/.X*-lock` ocupados, rompiendo el siguiente intento.

Referencia completa: `tools/start-greeter.sh`.

---

## E.4 — Permisos: greeter no puede escribir en ~/.config/lanetk/

**Síntoma**: Lefty (corriendo como `greeter`) no puede persistir la
elección del WM en `/home/ansmoun/.config/lanetk/wm`.

**Causa**: `/home/ansmoun` es `drwx------`. `greeter` no puede ni mirar
dentro.

**Solución**:

1. Lefty escribe `/tmp/lanetk-wm-choice` (escribible por todos, con
   sticky bit, no colisiona).
2. `bin/lanetk-session` (que ya corre como `ansmoun` después de startx)
   lee el archivo, persiste a `~/.config/lanetk/wm`, y borra el tmp.

**Contrato**:
- Si existe `/tmp/lanetk-wm-choice` -> usarlo y persistir.
- Si no -> leer `~/.config/lanetk/wm`.
- Si ninguno -> default `bspwm`.

---

## E.5 — Sincronización ~/proyectos/lanetk vs /opt/lanetk

**Síntoma**: fix aplicado en el working copy, pero el bug persiste.

**Causa**: Lefty corre desde `/opt/lanetk` (install.sh copia el
toolkit). El desarrollo vive en `~/proyectos/lanetk`. Son dos copias
independientes.

**Regla**: cualquier cambio a un archivo del toolkit que Lefty use
debe copiarse a mano a `/opt/lanetk/` hasta que haya un `install.sh`
real que automatice la sincronización.

**Verificar** después de cada fix:

    diff ~/proyectos/lanetk/src/lib/<archivo>.lua /opt/lanetk/src/lib/<archivo>.lua

Si difiere, el fix no llegó al runtime.

---

## E.6 — Técnicas de debugging

### RUST_LOG=debug para greetd

Greetd es Rust. Sin `RUST_LOG`, no loguea nada a stdout. Para ver qué
hace internamente:

    sudo env RUST_LOG=debug greetd -c /tmp/config.toml 2>&1 | tee /tmp/greetd.log

### log.debug con SEND/RECV en el cliente Lua

`lib/greetd.lua` tiene dos `log.debug` que imprimen el JSON exacto que
se manda y se recibe. Con `LANETK_LOG=debug` se ven. Sin esto, es
imposible saber si el problema es del cliente o del servidor.

### Logs persistentes en /var/log

Los logs en `/tmp` se pierden con un reinicio forzado. Los logs en
`/var/log` sobreviven. Asegurar owner `greeter:greeter`:

    sudo touch /var/log/lefty-greeter.log
    sudo chown greeter:greeter /var/log/lefty-greeter.log

### Testing manual sin tocar /var/service

Nunca habilitar greetd como servicio hasta que las pruebas manuales
funcionen. Usar:

    sudo greetd -c /tmp/greetd-test.toml

Con config temporal que apunte a un VT no usado (VT4, por ejemplo).
Así si algo se cuelga, se mata con `Ctrl+C` y el sistema sigue vivo.

### Recuperación

- **Cambiar de VT**: `Ctrl+Alt+F2` (o el número que corresponda).
- **Forzar VT desde SSH**: `sudo chvt 1`.
- **Matar todo**: `sudo pkill -9 -f greetd; sudo pkill -9 -f start-greeter;
  sudo pkill -9 lefty; sudo pkill -9 -f 'Xorg.*:1'` (o el display que sea).
- **Limpiar locks huérfanos**: `sudo rm -f /tmp/.X1-lock /tmp/.X11-unix/X1`.

---

## E.7 — Anti-patrones

- **Tocar `/var/service` antes de probar a mano**. Un servicio greetd
  mal configurado cuelga el sistema al arrancar.
- **`pkill -9` masivo**. Puede matar la sesión activa. Usar el pattern
  más específico posible.
- **Asumir que un fix en working copy llegó a /opt**. Ver E.5.
- **`startx <cliente>` en `xsessions.lua`**. Ver E.2.
- **`-terminate` en Xorg del wrapper**. Ver E.3.
- **`chvt` en el wrapper**. Ver E.3.
- **Persistir desde greeter al home del usuario**. Ver E.4.
- **Confiar en `tee` como `ansmoun` hacia `/var/log`**. Falla sin error.

---

## E.8 — Estado final del flujo de autenticación

    greetd (VT4)
      -> start-greeter.sh (wrapper)
         -> Xorg :N -noreset
         -> Lefty --greeter
            -> [usuario autentica]
            -> escribe /tmp/lanetk-wm-choice = "bspwm"
            -> create_session + post_auth + start_session(["startx"])
      -> wrapper muere rápido, Xorg muere, locks se liberan
      -> greetd ejecuta: startx
         -> ~/.xinitrc
            -> bin/lanetk-session
               -> lee /tmp/lanetk-wm-choice
               -> persiste a ~/.config/lanetk/wm
               -> aplica xrandr (monitores)
               -> apps/autostart.lua (wallpaper, bar, launcher, screenshot)
               -> exec bspwm

Cualquier desviación de esa cadena es un bug en una de las piezas.
