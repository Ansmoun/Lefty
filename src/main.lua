-- Greeter de LaneTK: pantalla de login.
--
-- Uso:
--   ./run apps/greeter.lua                -- modo standalone (default)
--   ./run apps/greeter.lua --greeter      -- modo real (dentro de greetd)
--   ./run apps/greeter.lua --user X       -- forzar usuario X
--
-- En modo standalone abre una ventana normal. En modo greeter abre
-- una ventana fullscreen override_redirect y espera el flujo greetd.
--
-- El flujo greetd (create_session, post_auth, start_session) lo
-- maneja este daemon via lib/greetd.lua. La UI es lib/tabs/greeter.lua.

local Server = require("lib.server")
local Window = require("lib.window")
local theme  = require("lib.theme")
local cairo  = require("lib.cairo")
local anim   = require("lib.anim")
local log    = require("lib.log")
local W      = require("lib.widgets")

-- ── Argumentos ────────────────────────────────────────────────────
local mode = "standalone"
local forced_user = nil
local forced_layout = nil
local forced_size = nil   -- { w, h } o nil
for i, a in ipairs(arg or {}) do
    if a == "--greeter" then mode = "greeter"
    elseif a == "--standalone" then mode = "standalone"
    elseif a == "--user" and arg[i + 1] then forced_user = arg[i + 1]
    elseif a == "--layout" and arg[i + 1] then forced_layout = arg[i + 1]
    elseif a == "--size" and arg[i + 1] then
        local w, h = arg[i + 1]:match("^(%d+)x(%d+)$")
        if w and h then forced_size = { tonumber(w), tonumber(h) } end
    end
end

-- ── Estado ────────────────────────────────────────────────────────
local srv = Server.new()
local T = theme.load()
anim.init(srv, { fps = 30 })
log.info("greeter", "modo=%s user=%s", mode, tostring(forced_user))

local greetd = require("lib.greetd")

local win = nil
local tab = nil
local cli = nil

-- ── Poweroff / reboot / suspend ──────────────────────────────────
local function do_power(action)
    log.info("greeter", "power action: %s", action)
    if action == "poweroff" then
        os.execute("loginctl poweroff >/dev/null 2>&1 &")
    elseif action == "reboot" then
        os.execute("loginctl reboot >/dev/null 2>&1 &")
    elseif action == "suspend" then
        os.execute("loginctl suspend >/dev/null 2>&1 &")
    end
end

-- ── Flujo greetd ─────────────────────────────────────────────────
local function on_greetd_msg(kind, data)
    log.info("greeter", "greetd: %s", kind)

    if kind == "auth_message" then
        local atype = data.auth_message_type
        local amsg = data.auth_message
        if atype == "secret" then
            -- Pedir contrasena al usuario. La UI ya la tiene en el
            -- campo; aca ya se la pasamos desde el callback on_login.
            -- Este caso se da cuando greetd pide un factor adicional
            -- (por ejemplo, cambio de contrasena obligatorio).
            tab.set_error(amsg or "Se requiere mas informacion")
        elseif atype == "visible" then
            tab.set_error(amsg or "Se requiere entrada adicional")
        elseif atype == "info" then
            log.info("greeter", "greetd info: %s", amsg)
            cli:post_auth_response(nil, on_greetd_msg)
        elseif atype == "error" then
            log.warn("greeter", "greetd error msg: %s", amsg)
            tab.set_error(amsg or "Error de autenticacion")
            tab.clear_password()
        end

    elseif kind == "success" then
        if not cli._session_started then
            cli._session_started = true
            -- Registrar el usuario para que el proximo arranque lo
            -- preseleccione. Si falla, no es critico.
            if tab.record_login then tab.record_login() end
            -- Arrancar la sesion elegida.
            local sess = tab.current_session()
            if not sess then
                tab.set_error("No hay sesiones disponibles")
                return
            end
            local xsessions = require("lib.xsessions")
            local cmd = xsessions.build_command(sess.id)
            if not cmd then
                tab.set_error("Sesion no reconocida: " .. sess.id)
                return
            end
            log.info("greeter", "start_session: %s", table.concat(cmd, " "))

            -- Persistir la eleccion del WM en /tmp/lanetk-wm-choice.
            -- No escribimos directo a ~/.config/lanetk/wm porque
            -- greeter no tiene permiso de escritura en el home del
            -- usuario real. bin/lanetk-session lee este archivo
            -- temporal y lo persiste al home del usuario una vez
            -- arrancada la sesion.
            local wm_path = "/tmp/lanetk-wm-choice"
            local wf = io.open(wm_path, "w")
            if wf then
                wf:write(sess.id .. "\n")
                wf:close()
                log.info("greeter", "WM guardado en %s: %s", wm_path, sess.id)
            else
                log.warn("greeter", "no pude escribir %s", wm_path)
            end
            -- start_session no espera respuesta. greetd va a matar
            -- al wrapper y lanzar la sesion del usuario. Salir con
            -- os.exit(0) directo es lo correcto: el proceso muere,
            -- sus fds se cierran (incluido el session-worker
            -- heredado), y greetd puede avanzar. Depender del event
            -- loop para salir deja el proceso vivo si algo quedo
            -- registrado en el Server.
            cli:start_session(cmd)
            log.info("greeter", "saliendo (os.exit 0)")
            os.exit(0)
        end

    elseif kind == "error" then
        local etype = data.error_type or "error"
        local desc = data.description or "Error desconocido"
        log.warn("greeter", "greetd error: %s - %s", etype, desc)
        tab.set_error(desc)
        tab.clear_password()
        tab.focus_password()
        cli._session_started = false

    elseif kind == "io_error" then
        log.error("greeter", "io_error: %s", tostring(data))
        tab.set_error("Error de comunicacion con greetd")

    elseif kind == "parse_error" then
        log.error("greeter", "parse_error: %s", tostring(data))
        tab.set_error("Respuesta invalida de greetd")
    end
end

local function on_login(username, password, session)
    log.info("greeter", "login attempt: %s (session=%s)",
        username, session and session.id or "?")
    tab.set_error("")

    if not cli then
        cli = greetd.connect()
        if not cli then
            tab.set_error("No se pudo conectar a greetd")
            return
        end
    end

    cli._session_started = false

    -- create_session -> auth_message (secret) -> post_auth(password)
    -- -> success -> start_session
    cli:create_session(username, function(kind, data)
        on_greetd_msg(kind, data)
        -- Si greetd pide la contrasena, la mandamos nosotros.
        if kind == "auth_message" and data.auth_message_type == "secret" then
            cli:post_auth_response(password, on_greetd_msg)
        end
    end)
end

-- ── Construccion ──────────────────────────────────────────────────
local function build_ui()
    local username = forced_user or os.getenv("USER") or "user"
    local greeter_mod = require("ui")
    tab = greeter_mod.new(srv, T, {
        username = username,
        layout   = forced_layout,
        on_login = on_login,
        on_power = do_power,
    })
    return tab.widget
end

-- ── Ventana ───────────────────────────────────────────────────────
local function build_window()
    local root = build_ui()

    local win_opts
    if mode == "greeter" then
        -- Modo real: fullscreen, sin decoracion, sin WM.
        -- El wrapper ya apago el monitor inactivo y posiciono el
        -- activo en 0,0. La ventana cubre todo.
        -- El tamano lo resolvemos despues con xrandr o con una
        -- heuristica: usamos on_measure para consultar la pantalla.
        win_opts = {
            kind = "menu",  -- override_redirect
            width = "screen", height = "screen",
            x = 0, y = 0,
            disable_q_close = true,
            on_draw = function(cr, w, h)
                local bg = T.bg_rgb
                cairo.set_rgb(cr, bg[1], bg[2], bg[3])
                cairo.paint(cr)
            end,
            on_key = function(key)
                -- Sin Esc: no hay forma de salir del greeter sin
                -- autenticar. Ctrl+Alt+F* lo maneja el kernel.
                if key.pressed and key.name == "Return" then
                    -- El TextInput ya maneja Enter. No hacer nada.
                end
            end,
        }
    else
        -- Modo standalone: ventana normal para probar la UI.
        -- Si --size se paso, usar ese tamano. Util para Xephyr.
        local w = 500
        local h = 620
        if forced_size then
            w = forced_size[1]
            h = forced_size[2]
        end
        win_opts = {
            kind = "normal",
            width = w, height = h,
            x = "center", y = "center",
            title = "LaneTK — Greeter (standalone)",
            disable_q_close = true,
            on_draw = function(cr, w, h)
                local bg = T.bg_rgb
                cairo.set_rgb(cr, bg[1], bg[2], bg[3])
                cairo.paint(cr)
            end,
            on_key = function(key)
                if key.pressed and key.name == "Escape"
                   and not key.mods.ctrl and not key.mods.alt
                   and not key.mods.super then
                    win:close("escape")
                end
            end,
        }
    end

    win = Window.new(srv, win_opts)
    win:set_root(root)
    if tab.start then tab.start() end
end

build_window()
srv:run()

if tab and tab.stop then tab.stop() end
if cli then cli:close() end
log.info("greeter", "adios")
