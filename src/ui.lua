-- Tab Greeter: pantalla de login.
--
-- Uso:
--   local tab = require("lib.tabs.greeter").new(srv, theme, {
--       on_login = function(username, password, session_id) ... end,
--       on_power = function(action) ... end,  -- "poweroff"|"reboot"|"suspend"
--   })
--
-- Layout:
--   Reloj (arriba izq)                      (arriba der) bienvenida
--
--                    [avatar 140]
--                    ansmoun
--                    [input password]
--                    [Entrar]
--                    [bspwm] [awesome] [i3]      (pills)
--                    [⏻] [⟲] [☾]                   (power)

local W         = require("lib.widgets")
local Area      = require("lib.area")
local cairo     = require("lib.cairo")
local pango     = require("lib.pango")
local xsessions = require("lib.xsessions")
local S         = require("lib.data.session")
local D_inicio  = require("lib.data.inicio")
local users_mod = require("lib.data.users")
local last_user = require("lib.data.last_user")
local log       = require("lib.log")

local M = {}

-- Directorio base de los iconos PNG. Se resuelve en orden:
--   1. Variable de entorno LANETK_ICONS_DIR (override manual)
--   2. $HOME/proyectos/lanetk/icons-png (desarrollo)
--   3. /opt/lanetk/icons-png (instalacion)
-- El primero que exista gana. Se usa para resolver los iconos de
-- los pills de sesion, los power buttons, y el ojo del input.
-- Busca el archivo de configuracion de lefty. Orden:
--   1. $LEFTY_CONFIG (env var, override manual)
--   2. /etc/greetd/lefty.conf (instalacion de sistema)
--   3. $HOME/.config/lefty/config.conf (usuario, para desarrollo)
-- Devuelve una tabla con las claves parseadas (key=value simples).
local function load_config()
    local paths = {
        os.getenv("LEFTY_CONFIG"),
        "/etc/greetd/lefty.conf",
        (os.getenv("HOME") or "") .. "/.config/lefty/config.conf",
    }
    for _, p in ipairs(paths) do
        if p and p ~= "" then
            local f = io.open(p, "r")
            if f then
                local conf = { _path = p }
                for line in f:lines() do
                    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                    if k and v and v ~= "" and v:sub(1, 1) ~= "#" then
                        conf[k] = v
                    end
                end
                f:close()
                return conf
            end
        end
    end
    return {}
end

local function resolve_icons_dir()
    local env = os.getenv("LANETK_ICONS_DIR")
    if env and env ~= "" then
        local f = io.open(env .. "/32/tab-eye.png", "rb")
        if f then f:close(); return env end
    end
    local home = os.getenv("HOME") or ""
    local cands = {
        home .. "/proyectos/lanetk/icons-png",
        "/opt/lanetk/icons-png",
    }
    for _, d in ipairs(cands) do
        local f = io.open(d .. "/32/tab-eye.png", "rb")
        if f then f:close(); return d end
    end
    return nil
end

local ICONS_DIR = resolve_icons_dir()

-- Forzar locale espanol para los nombres de dias y meses.
-- Si el locale no existe, os.date sigue en el locale actual.
os.setlocale("es_VE.UTF-8", "time")

-- ══════════════════════════════════════════════════════════════════
-- Avatar circular
-- ══════════════════════════════════════════════════════════════════

local Avatar = setmetatable({}, { __index = Area })
Avatar.__index = Avatar

function Avatar.new(opts)
    local self = setmetatable(Area.new(opts), Avatar)
    self.size       = opts.size or 140
    self.initial    = opts.initial or "?"
    self.accent_rgb = opts.accent_rgb or { 0.5, 0.7, 0.9 }
    self.bg_rgb     = opts.bg_rgb     or { 0.1, 0.1, 0.15 }
    self.surface    = nil
    self.min_w, self.max_w = self.size, self.size
    self.min_h, self.max_h = self.size, self.size
    if opts.path then
        local s = cairo.load_png(opts.path)
        if s then self.surface = s end
    end
    return self
end

function Avatar:draw(cr)
    local s = self.size
    local cx = self.x0 + s / 2
    local cy = self.y0 + s / 2
    local r = s / 2 - 2

    -- Anillo exterior
    cairo.set_rgb(cr,
        self.accent_rgb[1], self.accent_rgb[2], self.accent_rgb[3])
    cairo.new_path(cr)
    cairo.arc(cr, cx, cy, r + 1, 0, 2 * math.pi)
    cairo.fill(cr)

    cairo.save(cr)
    cairo.new_path(cr)
    cairo.arc(cr, cx, cy, r - 1, 0, 2 * math.pi)
    cairo.clip(cr)

    if self.surface then
        local nw = cairo.surface_width(self.surface)
        local nh = cairo.surface_height(self.surface)
        if nw > 0 and nh > 0 then
            local target = (r - 1) * 2
            local scale = math.max(target / nw, target / nh)
            local dw = nw * scale
            local dh = nh * scale
            cairo.draw_surface(cr, self.surface,
                cx - dw / 2, cy - dh / 2, dw, dh)
        end
    else
        cairo.set_rgb(cr,
            self.bg_rgb[1], self.bg_rgb[2], self.bg_rgb[3])
        cairo.new_path(cr)
        cairo.rectangle(cr, cx - r, cy - r, 2 * r, 2 * r)
        cairo.fill(cr)
        local initial = self.initial:sub(1, 1):upper()
        local iw, ih = pango.measure(initial, "DejaVu Sans Bold 60")
        pango.draw_text(cr, cx - iw/2, cy - ih/2, initial,
            "DejaVu Sans Bold 60", { r = 0.9, g = 0.9, b = 0.9 })
    end
    cairo.restore(cr)
    cairo.new_path(cr)
end

-- ══════════════════════════════════════════════════════════════════
-- Card con fondo semitransparente
-- ══════════════════════════════════════════════════════════════════

local Card = setmetatable({}, { __index = Area })
Card.__index = Card

function Card.new(opts)
    local self = setmetatable(Area.new(opts), Card)
    self.bg_rgb  = opts.bg_rgb or { 0.06, 0.06, 0.08 }
    self.alpha   = opts.alpha  or 0.9
    self.radius  = opts.radius or 16
    self.content = opts.content
    return self
end

function Card:set_window(win)
    self.window = win
    if self.content and self.content.set_window then
        self.content:set_window(win)
    elseif self.content then
        self.content.window = win
    end
end

function Card:askMinMax(minw, minh, maxw, maxh)
    if self.content then
        return self.content:askMinMax(minw, minh, maxw, maxh)
    end
    return minw, minh, maxw, maxh
end

function Card:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    if self.content then
        self.content:layout(x0, y0, x1, y1)
    end
end

function Card:draw(cr)
    local r = self.bg_rgb
    cairo.set_rgba(cr, r[1], r[2], r[3], self.alpha)
    cairo.new_path(cr)
    cairo.rounded_rect(cr,
        self.x0, self.y0, self:getWidth(), self:getHeight(),
        self.radius)
    cairo.fill(cr)
    if self.content then self.content:draw(cr) end
end

function Card:getByXY(x, y)
    if self.content then
        local hit = self.content:getByXY(x, y)
        if hit then return hit end
    end
    return Area.getByXY(self, x, y)
end

-- ══════════════════════════════════════════════════════════════════
-- Pill de sesion
-- ══════════════════════════════════════════════════════════════════
--
-- El rect del pill se reasigna desde afuera en cada frame (por el
-- PillDock que lo contiene). El pill NO cambia su min_w/max_w ni
-- pide relayout: solo dibuja su fondo con ancho interpolado por
-- hover_t, y el PillDock reposiciona.

local SessionPill = setmetatable({}, { __index = Area })
SessionPill.__index = SessionPill

function SessionPill.new(opts)
    local self = setmetatable(Area.new(opts), SessionPill)
    self._hover_visual = true
    self.label       = opts.label or "?"
    self.id          = opts.id
    self.on_click_cb = opts.on_click
    self.selected    = opts.selected or false
    self.theme       = opts.theme
    self.pad_x       = opts.pad_x or 10
    self.pad_y       = opts.pad_y or 6
    self.gap_icon    = opts.gap_icon or 8
    self.icon_size   = opts.icon_size or 22
    self.font        = opts.font or "DejaVu Sans 10"
    self.icon_path   = opts.icon_path

    if self.icon_path then
        local ok, s = pcall(cairo.load_png_cached, self.icon_path)
        if ok and s then self.icon_surface = s end
    end

    local tw, th = pango.measure(self.label, self.font)
    self.tw, self.th = tw, th

    -- Anchos que el PillDock usa para posicionar.
    self.icon_only_w = self.pad_x * 2 + self.icon_size
    self.expanded_w  = self.pad_x * 2 + self.icon_size
                       + self.gap_icon + tw
    self.row_h = math.max(th, self.icon_size) + self.pad_y * 2

    -- min/max fijos al expandido: el pill nunca pide menos, y el
    -- PillDock le asigna el rect real.
    self.min_w = self.expanded_w
    self.max_w = self.expanded_w
    self.min_h = self.row_h
    self.max_h = self.row_h

    self.hover_t = 0
    self._hover_handle = nil

    return self
end

-- Ancho actual del fondo (interpolado por hover_t).
function SessionPill:current_w()
    return self.icon_only_w + (self.expanded_w - self.icon_only_w) * self.hover_t
end

function SessionPill:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
    self:_animate_hover(v and 1 or 0)
end

function SessionPill:_animate_hover(target)
    local anim = require("lib.anim")
    if self._hover_handle then
        self._hover_handle:cancel()
        self._hover_handle = nil
    end
    local from = self.hover_t
    if math.abs(target - from) < 0.001 then
        self.hover_t = target
        if self._dock then self._dock:tick() end
        return
    end
    if anim.is_ready() then
        local dur = math.max(20, 180 * math.abs(target - from))
        self._hover_handle = anim.tween_custom(self,
            function(eased)
                self.hover_t = from + (target - from) * eased
                if self._dock then self._dock:tick() end
            end,
            dur, anim.EASE.out_cubic,
            function()
                self.hover_t = target
                self._hover_handle = nil
                if self._dock then self._dock:tick() end
            end)
    else
        self.hover_t = target
        if self._dock then self._dock:tick() end
    end
end

function SessionPill:set_selected(v)
    if self.selected == v then return end
    self.selected = v
    self:damage()
end

function SessionPill:draw(cr)
    local T = self.theme
    local x, y = self.x0, self.y0
    local h = self:getHeight()
    local t = self.hover_t
    local bg_w = self:current_w()
    local r = h / 2

    local bg_rgb, fg_rgb
    if self.selected then
        bg_rgb = T.accent_rgb
        fg_rgb = T.bg_rgb
    elseif self.hover then
        bg_rgb = T.bg_focus_rgb
        fg_rgb = T.fg_rgb
    else
        bg_rgb = T.bg_card_rgb
        fg_rgb = T.muted_rgb
    end

    cairo.set_rgba(cr, bg_rgb[1], bg_rgb[2], bg_rgb[3],
        self.selected and 1.0 or 0.6)
    cairo.new_path(cr)
    cairo.rounded_rect(cr, x, y, bg_w, h, r)
    cairo.fill(cr)

    if self.icon_surface then
        local iy = y + (h - self.icon_size) / 2
        local ix = x + self.pad_x
        cairo.draw_surface_tinted(cr, self.icon_surface,
            ix, iy, self.icon_size, self.icon_size,
            fg_rgb[1], fg_rgb[2], fg_rgb[3])
    end

    if t > 0.01 then
        local tx = x + self.pad_x + self.icon_size + self.gap_icon
        local ty = y + (h - self.th) / 2
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.rectangle(cr, x + self.icon_only_w - 4, y, bg_w, h)
        cairo.clip(cr)
        pango.draw_text(cr, tx, ty, self.label, self.font,
            { r = fg_rgb[1], g = fg_rgb[2], b = fg_rgb[3] })
        cairo.restore(cr)
        cairo.new_path(cr)
    end
end

function SessionPill:on_mouse_press(mx, my, button)
    if button == 1 and self.on_click_cb then
        self.on_click_cb(self.id)
    end
end


-- ══════════════════════════════════════════════════════════════════
-- PillDock: contenedor que posiciona los pills en cada frame segun
-- su hover_t actual. El conjunto queda centrado horizontalmente
-- dentro del rect que le asigna el padre. Solo se daña el rect del
-- dock, no toda la ventana.
-- ══════════════════════════════════════════════════════════════════

local PillDock = setmetatable({}, { __index = Area })
PillDock.__index = PillDock

function PillDock.new(opts)
    opts = opts or {}
    local self = setmetatable(Area.new(opts), PillDock)
    self.children = {}
    self.spacing = opts.spacing or 2
    self.row_h   = opts.row_height or 40
    -- Alineacion del conjunto dentro del rect del dock:
    --   "left" | "center" (default) | "right"
    self.align   = opts.align or "center"
    self.min_w, self.max_w = 0, 10000
    self.min_h, self.max_h = self.row_h, self.row_h
    return self
end

function PillDock:add(child)
    child.parent = self
    child._dock = self
    self.children[#self.children + 1] = child
    if self.window then
        if child.set_window then child:set_window(self.window)
        else child.window = self.window end
    end
    return child
end

function PillDock:set_window(win)
    self.window = win
    for _, c in ipairs(self.children) do
        if c.set_window then c:set_window(win)
        else c.window = win end
    end
end

function PillDock:_total_current_w()
    local total = 0
    for i, c in ipairs(self.children) do
        if i > 1 then total = total + self.spacing end
        total = total + c:current_w()
    end
    return total
end

-- Reposiciona y daña. Se llama desde el callback del tween de
-- hover del pill, en cada frame.
function PillDock:tick()
    self:_position()
    if self.window then
        self.window:add_damage(self.x0, self.y0, self.x1, self.y1)
    end
end

function PillDock:_position()
    if self.x1 <= self.x0 then return end
    local total = self:_total_current_w()
    local cx
    if self.align == "left" then
        cx = self.x0
    elseif self.align == "right" then
        cx = self.x1 - total
    else
        cx = self.x0 + (self:getWidth() - total) / 2
    end
    local y  = self.y0
    local h  = self:getHeight()
    for i, c in ipairs(self.children) do
        local w = c:current_w()
        c:layout(cx, y, cx + w, y + h)
        cx = cx + w + self.spacing
    end
end

function PillDock:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    self:_position()
end

function PillDock:draw(cr)
    for _, c in ipairs(self.children) do
        c:draw(cr)
    end
end

function PillDock:getByXY(x, y)
    for _, c in ipairs(self.children) do
        local hit = c:getByXY(x, y)
        if hit then return hit end
    end
    return nil
end

function PillDock:askMinMax(minw, minh, maxw, maxh)
    -- Ancho reservado = suma de los pills en su estado EXPANDIDO.
    -- Garantiza que el rect del dock contenga el conjunto aunque
    -- todos se expandan a la vez. Con el ancho colapsado, expandir
    -- un pill desborda el rect y rompe el render.
    local total_expanded = 0
    for i, c in ipairs(self.children) do
        if i > 1 then total_expanded = total_expanded + self.spacing end
        total_expanded = total_expanded + (c.expanded_w or 0)
    end
    return minw + total_expanded, minh + self.min_h,
           maxw + total_expanded, maxh + self.max_h
end

function PillDock:on_mouse_move(mx, my)
    for _, c in ipairs(self.children) do
        local gx = self.x0 + mx
        local gy = self.y0 + my
        local inside = gx >= c.x0 and gx < c.x1 and gy >= c.y0 and gy < c.y1
        c:set_hover(inside)
    end
end


-- ══════════════════════════════════════════════════════════════════
-- UserPill: pill de seleccion de usuario. Similar a SessionPill
-- pero el "icono" es el avatar circular del usuario (no se tinta).
-- Al hover se expande y muestra el nombre.
-- ══════════════════════════════════════════════════════════════════

local UserPill = setmetatable({}, { __index = Area })
UserPill.__index = UserPill

function UserPill.new(opts)
    local self = setmetatable(Area.new(opts), UserPill)
    self._hover_visual = true
    self.id          = opts.id              -- username
    self.label       = opts.label or self.id
    self.avatar_path = opts.avatar_path
    self.on_click_cb = opts.on_click
    self.selected    = opts.selected or false
    self.theme       = opts.theme
    self.pad_x       = opts.pad_x or 6
    self.pad_y       = opts.pad_y or 4
    self.gap_icon    = opts.gap_icon or 6
    self.icon_size   = opts.icon_size or 28
    self.font        = opts.font or "DejaVu Sans 10"

    -- Cargar avatar (si existe)
    if self.avatar_path then
        local s = cairo.load_png(self.avatar_path)
        if s then self.avatar_surface = s end
    end

    local tw, th = pango.measure(self.label, self.font)
    self.tw, self.th = tw, th

    self.icon_only_w = self.pad_x * 2 + self.icon_size
    self.expanded_w  = self.pad_x * 2 + self.icon_size + self.gap_icon + tw
    self.row_h = math.max(th, self.icon_size) + self.pad_y * 2

    self.min_w = self.expanded_w
    self.max_w = self.expanded_w
    self.min_h = self.row_h
    self.max_h = self.row_h

    self.hover_t = 0
    self._hover_handle = nil
    return self
end

function UserPill:current_w()
    return self.icon_only_w + (self.expanded_w - self.icon_only_w) * self.hover_t
end

function UserPill:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
    self:_animate_hover(v and 1 or 0)
end

function UserPill:_animate_hover(target)
    local anim = require("lib.anim")
    if self._hover_handle then
        self._hover_handle:cancel()
        self._hover_handle = nil
    end
    local from = self.hover_t
    if math.abs(target - from) < 0.001 then
        self.hover_t = target
        if self._dock then self._dock:tick() end
        return
    end
    if anim.is_ready() then
        local dur = math.max(20, 180 * math.abs(target - from))
        self._hover_handle = anim.tween_custom(self,
            function(eased)
                self.hover_t = from + (target - from) * eased
                if self._dock then self._dock:tick() end
            end,
            dur, anim.EASE.out_cubic,
            function()
                self.hover_t = target
                self._hover_handle = nil
                if self._dock then self._dock:tick() end
            end)
    else
        self.hover_t = target
        if self._dock then self._dock:tick() end
    end
end

function UserPill:set_selected(v)
    if self.selected == v then return end
    self.selected = v
    self:damage()
end

function UserPill:draw(cr)
    local T = self.theme
    local x, y = self.x0, self.y0
    local h = self:getHeight()
    local t = self.hover_t
    local bg_w = self:current_w()
    local r = h / 2

    local bg_rgb, fg_rgb
    if self.selected then
        bg_rgb = T.accent_rgb
        fg_rgb = T.bg_rgb
    elseif self.hover then
        bg_rgb = T.bg_focus_rgb
        fg_rgb = T.fg_rgb
    else
        bg_rgb = T.bg_card_rgb
        fg_rgb = T.muted_rgb
    end

    cairo.set_rgba(cr, bg_rgb[1], bg_rgb[2], bg_rgb[3],
        self.selected and 1.0 or 0.6)
    cairo.new_path(cr)
    cairo.rounded_rect(cr, x, y, bg_w, h, r)
    cairo.fill(cr)

    -- Avatar circular
    local ix = x + self.pad_x
    local iy = y + (h - self.icon_size) / 2
    local icx = ix + self.icon_size / 2
    local icy = iy + self.icon_size / 2
    local ir = self.icon_size / 2

    if self.avatar_surface then
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.arc(cr, icx, icy, ir, 0, 2 * math.pi)
        cairo.clip(cr)
        local nw = cairo.surface_width(self.avatar_surface)
        local nh = cairo.surface_height(self.avatar_surface)
        if nw > 0 and nh > 0 then
            local target = ir * 2
            local scale = math.max(target / nw, target / nh)
            cairo.draw_surface(cr, self.avatar_surface,
                icx - nw * scale / 2, icy - nh * scale / 2,
                nw * scale, nh * scale)
        end
        cairo.restore(cr)
        cairo.new_path(cr)
    else
        -- Fallback: circulo con inicial
        cairo.set_rgb(cr, fg_rgb[1], fg_rgb[2], fg_rgb[3])
        cairo.new_path(cr)
        cairo.arc(cr, icx, icy, ir, 0, 2 * math.pi)
        cairo.fill(cr)
        local initial = (self.label or "?"):sub(1, 1):upper()
        local iw, ih = pango.measure(initial, "DejaVu Sans Bold 12")
        cairo.set_rgb(cr,
            self.selected and T.accent_rgb[1] or 0.1,
            self.selected and T.accent_rgb[2] or 0.1,
            self.selected and T.accent_rgb[3] or 0.1)
        pango.draw_text(cr, icx - iw/2, icy - ih/2, initial,
            "DejaVu Sans Bold 12",
            { r = bg_rgb[1], g = bg_rgb[2], b = bg_rgb[3] })
    end

    -- Texto
    if t > 0.01 then
        local tx = x + self.pad_x + self.icon_size + self.gap_icon
        local ty = y + (h - self.th) / 2
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.rectangle(cr, x + self.icon_only_w - 4, y, bg_w, h)
        cairo.clip(cr)
        pango.draw_text(cr, tx, ty, self.label, self.font,
            { r = fg_rgb[1], g = fg_rgb[2], b = fg_rgb[3] })
        cairo.restore(cr)
        cairo.new_path(cr)
    end
end

function UserPill:on_mouse_press(mx, my, button)
    if button == 1 and self.on_click_cb then
        self.on_click_cb(self.id)
    end
end


-- ══════════════════════════════════════════════════════════════════
-- UserPill: pill de seleccion de usuario.
-- ══════════════════════════════════════════════════════════════════

local UserPill = setmetatable({}, { __index = Area })
UserPill.__index = UserPill

function UserPill.new(opts)
    local self = setmetatable(Area.new(opts), UserPill)
    self._hover_visual = true
    self.id          = opts.id
    self.label       = opts.label or self.id
    self.avatar_path = opts.avatar_path
    self.on_click_cb = opts.on_click
    self.selected    = opts.selected or false
    self.theme       = opts.theme
    self.pad_x       = opts.pad_x or 6
    self.pad_y       = opts.pad_y or 4
    self.gap_icon    = opts.gap_icon or 6
    self.icon_size   = opts.icon_size or 28
    self.font        = opts.font or "DejaVu Sans 10"

    if self.avatar_path then
        local s = cairo.load_png(self.avatar_path)
        if s then self.avatar_surface = s end
    end

    local tw, th = pango.measure(self.label, self.font)
    self.tw, self.th = tw, th

    self.icon_only_w = self.pad_x * 2 + self.icon_size
    self.expanded_w  = self.pad_x * 2 + self.icon_size + self.gap_icon + tw
    self.row_h = math.max(th, self.icon_size) + self.pad_y * 2

    self.min_w = self.expanded_w
    self.max_w = self.expanded_w
    self.min_h = self.row_h
    self.max_h = self.row_h

    self.hover_t = 0
    self._hover_handle = nil
    return self
end

function UserPill:current_w()
    return self.icon_only_w + (self.expanded_w - self.icon_only_w) * self.hover_t
end

function UserPill:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
    self:_animate_hover(v and 1 or 0)
end

function UserPill:_animate_hover(target)
    local anim = require("lib.anim")
    if self._hover_handle then
        self._hover_handle:cancel()
        self._hover_handle = nil
    end
    local from = self.hover_t
    if math.abs(target - from) < 0.001 then
        self.hover_t = target
        if self._dock then self._dock:tick() end
        return
    end
    if anim.is_ready() then
        local dur = math.max(20, 180 * math.abs(target - from))
        self._hover_handle = anim.tween_custom(self,
            function(eased)
                self.hover_t = from + (target - from) * eased
                if self._dock then self._dock:tick() end
            end,
            dur, anim.EASE.out_cubic,
            function()
                self.hover_t = target
                self._hover_handle = nil
                if self._dock then self._dock:tick() end
            end)
    else
        self.hover_t = target
        if self._dock then self._dock:tick() end
    end
end

function UserPill:set_selected(v)
    if self.selected == v then return end
    self.selected = v
    self:damage()
end

function UserPill:draw(cr)
    local T = self.theme
    local x, y = self.x0, self.y0
    local h = self:getHeight()
    local t = self.hover_t
    local bg_w = self:current_w()
    local r = h / 2

    local bg_rgb, fg_rgb
    if self.selected then
        bg_rgb = T.accent_rgb
        fg_rgb = T.bg_rgb
    elseif self.hover then
        bg_rgb = T.bg_focus_rgb
        fg_rgb = T.fg_rgb
    else
        bg_rgb = T.bg_card_rgb
        fg_rgb = T.muted_rgb
    end

    cairo.set_rgba(cr, bg_rgb[1], bg_rgb[2], bg_rgb[3],
        self.selected and 1.0 or 0.6)
    cairo.new_path(cr)
    cairo.rounded_rect(cr, x, y, bg_w, h, r)
    cairo.fill(cr)

    local ix = x + self.pad_x
    local iy = y + (h - self.icon_size) / 2
    local icx = ix + self.icon_size / 2
    local icy = iy + self.icon_size / 2
    local ir = self.icon_size / 2

    if self.avatar_surface then
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.arc(cr, icx, icy, ir, 0, 2 * math.pi)
        cairo.clip(cr)
        local nw = cairo.surface_width(self.avatar_surface)
        local nh = cairo.surface_height(self.avatar_surface)
        if nw > 0 and nh > 0 then
            local target = ir * 2
            local scale = math.max(target / nw, target / nh)
            cairo.draw_surface(cr, self.avatar_surface,
                icx - nw * scale / 2, icy - nh * scale / 2,
                nw * scale, nh * scale)
        end
        cairo.restore(cr)
        cairo.new_path(cr)
    else
        cairo.set_rgb(cr, fg_rgb[1], fg_rgb[2], fg_rgb[3])
        cairo.new_path(cr)
        cairo.arc(cr, icx, icy, ir, 0, 2 * math.pi)
        cairo.fill(cr)
        local initial = (self.label or "?"):sub(1, 1):upper()
        local iw, ih = pango.measure(initial, "DejaVu Sans Bold 12")
        pango.draw_text(cr, icx - iw/2, icy - ih/2, initial,
            "DejaVu Sans Bold 12",
            { r = bg_rgb[1], g = bg_rgb[2], b = bg_rgb[3] })
    end

    if t > 0.01 then
        local tx = x + self.pad_x + self.icon_size + self.gap_icon
        local ty = y + (h - self.th) / 2
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.rectangle(cr, x + self.icon_only_w - 4, y, bg_w, h)
        cairo.clip(cr)
        pango.draw_text(cr, tx, ty, self.label, self.font,
            { r = fg_rgb[1], g = fg_rgb[2], b = fg_rgb[3] })
        cairo.restore(cr)
        cairo.new_path(cr)
    end
end

function UserPill:on_mouse_press(mx, my, button)
    if button == 1 and self.on_click_cb then
        self.on_click_cb(self.id)
    end
end


-- ══════════════════════════════════════════════════════════════════
-- UserPill: pill de seleccion de usuario.
-- ══════════════════════════════════════════════════════════════════

local UserPill = setmetatable({}, { __index = Area })
UserPill.__index = UserPill

function UserPill.new(opts)
    local self = setmetatable(Area.new(opts), UserPill)
    self._hover_visual = true
    self.id          = opts.id
    self.label       = opts.label or self.id
    self.avatar_path = opts.avatar_path
    self.on_click_cb = opts.on_click
    self.selected    = opts.selected or false
    self.theme       = opts.theme
    self.pad_x       = opts.pad_x or 6
    self.pad_y       = opts.pad_y or 4
    self.gap_icon    = opts.gap_icon or 6
    self.icon_size   = opts.icon_size or 28
    self.font        = opts.font or "DejaVu Sans 10"

    if self.avatar_path then
        local s = cairo.load_png(self.avatar_path)
        if s then self.avatar_surface = s end
    end

    local tw, th = pango.measure(self.label, self.font)
    self.tw, self.th = tw, th

    self.icon_only_w = self.pad_x * 2 + self.icon_size
    self.expanded_w  = self.pad_x * 2 + self.icon_size + self.gap_icon + tw
    self.row_h = math.max(th, self.icon_size) + self.pad_y * 2

    self.min_w = self.expanded_w
    self.max_w = self.expanded_w
    self.min_h = self.row_h
    self.max_h = self.row_h

    self.hover_t = 0
    self._hover_handle = nil
    return self
end

function UserPill:current_w()
    return self.icon_only_w + (self.expanded_w - self.icon_only_w) * self.hover_t
end

function UserPill:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
    self:_animate_hover(v and 1 or 0)
end

function UserPill:_animate_hover(target)
    local anim = require("lib.anim")
    if self._hover_handle then
        self._hover_handle:cancel()
        self._hover_handle = nil
    end
    local from = self.hover_t
    if math.abs(target - from) < 0.001 then
        self.hover_t = target
        if self._dock then self._dock:tick() end
        return
    end
    if anim.is_ready() then
        local dur = math.max(20, 180 * math.abs(target - from))
        self._hover_handle = anim.tween_custom(self,
            function(eased)
                self.hover_t = from + (target - from) * eased
                if self._dock then self._dock:tick() end
            end,
            dur, anim.EASE.out_cubic,
            function()
                self.hover_t = target
                self._hover_handle = nil
                if self._dock then self._dock:tick() end
            end)
    else
        self.hover_t = target
        if self._dock then self._dock:tick() end
    end
end

function UserPill:set_selected(v)
    if self.selected == v then return end
    self.selected = v
    self:damage()
end

function UserPill:draw(cr)
    local T = self.theme
    local x, y = self.x0, self.y0
    local h = self:getHeight()
    local t = self.hover_t
    local bg_w = self:current_w()
    local r = h / 2

    local bg_rgb, fg_rgb
    if self.selected then
        bg_rgb = T.accent_rgb
        fg_rgb = T.bg_rgb
    elseif self.hover then
        bg_rgb = T.bg_focus_rgb
        fg_rgb = T.fg_rgb
    else
        bg_rgb = T.bg_card_rgb
        fg_rgb = T.muted_rgb
    end

    cairo.set_rgba(cr, bg_rgb[1], bg_rgb[2], bg_rgb[3],
        self.selected and 1.0 or 0.6)
    cairo.new_path(cr)
    cairo.rounded_rect(cr, x, y, bg_w, h, r)
    cairo.fill(cr)

    local ix = x + self.pad_x
    local iy = y + (h - self.icon_size) / 2
    local icx = ix + self.icon_size / 2
    local icy = iy + self.icon_size / 2
    local ir = self.icon_size / 2

    if self.avatar_surface then
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.arc(cr, icx, icy, ir, 0, 2 * math.pi)
        cairo.clip(cr)
        local nw = cairo.surface_width(self.avatar_surface)
        local nh = cairo.surface_height(self.avatar_surface)
        if nw > 0 and nh > 0 then
            local target = ir * 2
            local scale = math.max(target / nw, target / nh)
            cairo.draw_surface(cr, self.avatar_surface,
                icx - nw * scale / 2, icy - nh * scale / 2,
                nw * scale, nh * scale)
        end
        cairo.restore(cr)
        cairo.new_path(cr)
    else
        cairo.set_rgb(cr, fg_rgb[1], fg_rgb[2], fg_rgb[3])
        cairo.new_path(cr)
        cairo.arc(cr, icx, icy, ir, 0, 2 * math.pi)
        cairo.fill(cr)
        local initial = (self.label or "?"):sub(1, 1):upper()
        local iw, ih = pango.measure(initial, "DejaVu Sans Bold 12")
        pango.draw_text(cr, icx - iw/2, icy - ih/2, initial,
            "DejaVu Sans Bold 12",
            { r = bg_rgb[1], g = bg_rgb[2], b = bg_rgb[3] })
    end

    if t > 0.01 then
        local tx = x + self.pad_x + self.icon_size + self.gap_icon
        local ty = y + (h - self.th) / 2
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.rectangle(cr, x + self.icon_only_w - 4, y, bg_w, h)
        cairo.clip(cr)
        pango.draw_text(cr, tx, ty, self.label, self.font,
            { r = fg_rgb[1], g = fg_rgb[2], b = fg_rgb[3] })
        cairo.restore(cr)
        cairo.new_path(cr)
    end
end

function UserPill:on_mouse_press(mx, my, button)
    if button == 1 and self.on_click_cb then
        self.on_click_cb(self.id)
    end
end


-- ══════════════════════════════════════════════════════════════════
-- PowerButton: icono PNG chico con hover
-- ══════════════════════════════════════════════════════════════════

local PowerButton = setmetatable({}, { __index = Area })
PowerButton.__index = PowerButton

function PowerButton.new(opts)
    local self = setmetatable(Area.new(opts), PowerButton)
    self._hover_visual = true
    self.icon_path = opts.icon_path
    self.action    = opts.action
    self.on_click_cb = opts.on_click
    self.theme     = opts.theme
    self.size      = opts.size or 28
    self.color        = opts.color or { 0.6, 0.6, 0.65 }
    self.color_hover  = opts.color_hover or { 0.95, 0.95, 0.95 }
    local s = cairo.load_png(opts.icon_path)
    self.surface = s
    self.min_w, self.max_w = self.size + 12, self.size + 12
    self.min_h, self.max_h = self.size + 12, self.size + 12
    return self
end

function PowerButton:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
end

function PowerButton:draw(cr)
    if not self.surface then return end
    local c = self.hover and self.color_hover or self.color
    local x = self.x0 + (self:getWidth() - self.size) / 2
    local y = self.y0 + (self:getHeight() - self.size) / 2
    cairo.draw_surface_tinted(cr, self.surface, x, y,
        self.size, self.size, c[1], c[2], c[3])
end

function PowerButton:on_mouse_press(mx, my, button)
    if button == 1 and self.on_click_cb then
        self.on_click_cb(self.action)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- Overlay: contenedor que da a todos sus hijos el rect COMPLETO
-- del padre. Los hijos se superponen y se dibujan en orden de
-- insercion (el ultimo encima). Cada hijo decide donde pintar
-- dentro del rect. Util para layouts con elementos anclados a
-- esquinas (win10, gnome).
-- ══════════════════════════════════════════════════════════════════

local Overlay = setmetatable({}, { __index = Area })
Overlay.__index = Overlay

function Overlay.new(opts)
    opts = opts or {}
    local self = setmetatable(Area.new(opts), Overlay)
    self.children = {}
    return self
end

function Overlay:add(child)
    child.parent = self
    self.children[#self.children + 1] = child
    if self.window then
        if child.set_window then child:set_window(self.window)
        else child.window = self.window end
    end
    return child
end

function Overlay:set_window(win)
    self.window = win
    for _, c in ipairs(self.children) do
        if c.set_window then c:set_window(win)
        else c.window = win end
    end
end

function Overlay:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    for _, c in ipairs(self.children) do
        c:layout(x0, y0, x1, y1)
    end
end

function Overlay:draw(cr)
    for _, c in ipairs(self.children) do
        c:draw(cr)
    end
end

function Overlay:getByXY(x, y)
    -- De atras hacia adelante: el ultimo hijo tiene prioridad.
    for i = #self.children, 1, -1 do
        local hit = self.children[i]:getByXY(x, y)
        if hit then return hit end
    end
    return nil
end

function Overlay:askMinMax(minw, minh, maxw, maxh)
    return minw, minh, maxw, maxh
end


-- ══════════════════════════════════════════════════════════════════
-- FloatingBlock: dibuja contenido en (x0, y0) sin ocupar espacio
-- en el flujo. Reserva 0 de alto y el ancho que le da el padre.
-- Util para el reloj: flota sobre el contenido sin empujarlo.
-- ══════════════════════════════════════════════════════════════════

local FloatingBlock = setmetatable({}, { __index = Area })
FloatingBlock.__index = FloatingBlock

function FloatingBlock.new(opts)
    local self = setmetatable(Area.new(opts), FloatingBlock)
    self.content = opts.content
    self.anchor  = opts.anchor or "top-left"
    self.block_w = opts.block_width or 500
    self.block_h = opts.block_height or 120
    self.min_h, self.max_h = 0, 0
    self.min_w, self.max_w = 0, 10000
    return self
end

function FloatingBlock:set_window(win)
    self.window = win
    if self.content and self.content.set_window then
        self.content:set_window(win)
    elseif self.content then
        self.content.window = win
    end
end

function FloatingBlock:askMinMax(minw, minh, maxw, maxh)
    return minw, minh, maxw, maxh
end

function FloatingBlock:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    if not self.content then return end
    -- El contenido recibe un rect acotado, anclado segun
    -- self.anchor. El alto del bloque es fijo (no ocupa espacio en
    -- el flujo del padre).
    local bw = self.block_w
    local bh = self.block_h
    local cx0, cy0
    if self.anchor == "top-right" then
        cx0 = x1 - bw
        cy0 = y0
    elseif self.anchor == "bottom-left" then
        cx0 = x0
        cy0 = y1 - bh
    elseif self.anchor == "bottom-right" then
        cx0 = x1 - bw
        cy0 = y1 - bh
    else  -- top-left
        cx0 = x0
        cy0 = y0
    end
    self.content:layout(cx0, cy0, cx0 + bw, cy0 + bh)
end

function FloatingBlock:draw(cr)
    if self.content then self.content:draw(cr) end
end

function FloatingBlock:getByXY(x, y)
    if self.content then
        local hit = self.content:getByXY(x, y)
        if hit then return hit end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- Helpers
-- ══════════════════════════════════════════════════════════════════

local function spacer(h)
    local s = W.Text.new { text = "", font = "DejaVu Sans 1" }
    s.min_h, s.max_h = h, h
    return s
end

local function hspacer(w)
    local s = W.Text.new { text = "", font = "DejaVu Sans 1" }
    s.min_w, s.max_w = w, w
    return s
end

local function centered(widget)
    return W.Group.new {
        orientation = "horizontal",
        children = {
            { widget = W.Text.new { text = "" }, weight = 1 },
            { widget = widget, weight = 0 },
            { widget = W.Text.new { text = "" }, weight = 1 },
        },
    }
end

-- ══════════════════════════════════════════════════════════════════
-- Tab
-- ══════════════════════════════════════════════════════════════════

function M.new(srv, theme, opts)
    opts = opts or {}
    log.info("greeter", "factory inicio")

    -- Username a autenticar. Prioridad:
    --   1. opts.username (CLI o caller)
    --   2. ~/.config/lefty/config.conf, clave default_user
    --   3. $USER
    local cfg = load_config()
    log.info("greeter", "config: %s", cfg._path or "(defaults)")

    -- Descubrir los usuarios reales del sistema desde /etc/passwd.
    -- Filtra uid >= 1000, shell valido, y excluye usuarios del
    -- sistema (greeter, nobody) mas los que el config liste.
    local users_blacklist = {}
    if cfg.users_blacklist then
        for name in cfg.users_blacklist:gmatch("[^,]+") do
            users_blacklist[#users_blacklist + 1] = name:gsub("%s+", "")
        end
    end
    local users = users_mod.list({ blacklist = users_blacklist })
    log.info("greeter", "%d usuarios detectados", #users)

    if #users == 0 then
        log.error("greeter", "no hay usuarios validos en /etc/passwd")
    end

    -- Elegir el usuario inicial:
    --   1. opts.username (CLI override)
    --   2. last_user (ultimo login exitoso) si esta en la lista
    --   3. el primero de la lista
    local function find_user_idx(name)
        for i, u in ipairs(users) do
            if u.username == name then return i end
        end
        return nil
    end

    local current_user_idx = nil
    if opts.username then
        current_user_idx = find_user_idx(opts.username)
    end
    if not current_user_idx then
        local last = last_user.get()
        if last then current_user_idx = find_user_idx(last) end
    end
    if not current_user_idx and #users > 0 then
        current_user_idx = 1
    end

    local function current_user()
        if not current_user_idx then return nil end
        return users[current_user_idx]
    end

    -- Forward declarations. Se definen abajo, pero los closures de
    -- on_submit y on_click las capturan. Sin el forward, la
    -- referencia se resuelve como global (nil) al construirlas.
    local get_current_username
    local record_login

    local username = current_user() and current_user().username
        or os.getenv("USER") or "user"

    -- Avatar path: pasa el username explicito.
    local avatar_path = D_inicio.find_avatar(username)

    -- Sesiones X
    local sessions = xsessions.list()
    local current_idx = 1
    do
        local saved = S.get_wm()
        if saved then
            for i, s in ipairs(sessions) do
                if s.id == saved then current_idx = i; break end
            end
        end
    end

    -- ══ Widgets ═══════════════════════════════════════════════════

    -- Avatar. Se actualiza dinamicamente cuando el usuario cambia.
    local avatar = Avatar.new {
        size       = 140,
        initial    = (username or "?"):sub(1, 1),
        path       = avatar_path,
        accent_rgb = theme.accent_rgb,
        bg_rgb     = theme.bg_card_rgb,
    }

    -- Nombre. Se actualiza dinamicamente.
    local name_lbl = W.Text.new {
        text = username or "?",
        font = "DejaVu Sans Bold 18",
        r = theme.fg_rgb[1],
        g = theme.fg_rgb[2],
        b = theme.fg_rgb[3],
        align = "center", valign = "center",
    }

    -- Subtitulo
    local sub_lbl = W.Text.new {
        text = "Ingresa tu contrasena para continuar",
        font = "DejaVu Sans 10",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
        align = "center", valign = "center",
    }

    -- Funcion para actualizar avatar + nombre cuando cambia el
    -- usuario seleccionado. Se llama desde el on_click del UserPill.
    local function update_user_visuals()
        local u = current_user()
        if not u then return end
        name_lbl:set_text(u.username)
        local new_path = D_inicio.find_avatar(u.username)
        avatar:set_path(new_path)
    end

    -- Toggle de ojo: alterna entre mascara (●●●) y texto plano.
    -- Vive DENTRO del input como right_widget.
    local EYE_DIR = (ICONS_DIR or os.getenv("HOME") ..
        "/proyectos/lanetk/icons-png") .. "/32/"

    local pass_input -- forward: el eye lo necesita
    local eye_btn    -- forward: el on_click del eye lo necesita

    eye_btn = W.Icon.new {
        path = EYE_DIR .. "tab-eye.png",
        width = 14, height = 14,
        valign = "center",
        on_click = function()
            pass_input.mask = not pass_input.mask
            if pass_input.mask then
                eye_btn:set_path(EYE_DIR .. "tab-eye.png")
            else
                eye_btn:set_path(EYE_DIR .. "tab-eye-off.png")
            end
            pass_input:damage()
        end,
    }

    pass_input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 10",
        padding_x = 8, padding_y = 3,
        min_height = 22,
        min_width  = 240,
        corner_radius = 5,
        mask = true,
        color_bg = theme.bg_focus,
        color_border = theme.separator,
        color_text = theme.fg_rgb,
        color_cursor = theme.accent_rgb,
        placeholder = "Contrasena",
        color_placeholder = theme.muted_rgb,
        right_widget = eye_btn,
        right_widget_width = 14,
        right_widget_gap = 4,
        on_submit = function(text)
            if opts.on_login then
                opts.on_login(get_current_username(), text,
                    sessions[current_idx])
            end
        end,
    }
    pass_input.opts.on_focus_request = function()
        pass_input:set_focused(true)
    end

    -- Error label
    local error_lbl = W.Text.new {
        text = "",
        font = "DejaVu Sans 10",
        r = theme.urgent_rgb[1],
        g = theme.urgent_rgb[2],
        b = theme.urgent_rgb[3],
        align = "center", valign = "center",
    }


    -- Boton de submit: cuadrado con flecha.
    local go_btn = W.Button.new {
        text = "\u{2192}",  -- →
        font = "DejaVu Sans Bold 12",
        padding_x = 8, padding_y = 2,
        corner_radius = 5,
        color_hover = theme.accent_rgb,
        color_text = theme.fg_rgb,
        on_click = function()
            if opts.on_login then
                opts.on_login(get_current_username(), pass_input:get_text(),
                    sessions[current_idx])
            end
        end,
    }
    go_btn.min_w = 26
    go_btn.max_w = 26

    -- UserDock: pills de usuario. Solo se construye si hay 2+
    -- usuarios. Con un solo usuario no tiene sentido mostrarlo.
    local user_dock = nil
    if #users >= 2 then
        user_dock = PillDock.new {
            spacing = 2,
            row_height = 40,
            align = "center",
        }
        local user_pills = {}
        local function update_user_selection()
            for _, p in ipairs(user_pills) do
                p:set_selected(p.id == (current_user() and
                    current_user().username or ""))
            end
        end
        for _, u in ipairs(users) do
            local uavatar = D_inicio.find_avatar(u.username)
            local up = UserPill.new {
                id          = u.username,
                label       = u.username,
                avatar_path = uavatar,
                theme       = theme,
                selected    = false,
                on_click    = function(id)
                    current_user_idx = find_user_idx(id)
                    update_user_selection()
                    update_user_visuals()
                end,
            }
            user_pills[#user_pills + 1] = up
            user_dock:add(up)
        end
        update_user_selection()
    end

    -- Pills de sesion. Cada pill intenta cargar el icono del
    -- entorno desde icons-png/88/sessions/<id>.png. Si no existe,
    -- usa default.png.
    local SESSIONS_ICON_DIR = (ICONS_DIR or os.getenv("HOME") ..
        "/proyectos/lanetk/icons-png") .. "/88/sessions/"

    local function icon_path_for(id)
        local cand = SESSIONS_ICON_DIR .. id:lower() .. ".png"
        local f = io.open(cand, "rb")
        if f then f:close(); return cand end
        return SESSIONS_ICON_DIR .. "default.png"
    end

    local pills = {}
    local function update_pills()
        for _, pill in ipairs(pills) do
            pill:set_selected(pill.id == sessions[current_idx].id)
        end
    end
    for _, s in ipairs(sessions) do
        local pill = SessionPill.new {
            label     = s.Name,
            id        = s.id,
            theme     = theme,
            selected  = false,
            icon_path = icon_path_for(s.id),
            on_click  = function(id)
                for i, ss in ipairs(sessions) do
                    if ss.id == id then current_idx = i; break end
                end
                update_pills()
            end,
        }
        pills[#pills + 1] = pill
    end

    pills_container = PillDock.new {
        spacing = 2,
        row_height = 44,
    }
    for _, p in ipairs(pills) do
        pills_container:add(p)
    end

    -- Reloj
    local clock_lbl = W.Text.new {
        text = os.date("%H:%M"),
        font = "DejaVu Sans Bold 24",
        r = theme.fg_rgb[1],
        g = theme.fg_rgb[2],
        b = theme.fg_rgb[3],
        align = "left", valign = "center",
    }
    local date_lbl = W.Text.new {
        text = os.date("%A, %d de %B"),
        font = "DejaVu Sans 11",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
        align = "left", valign = "center",
    }
    srv:add_timer(1000, function()
        clock_lbl:set_text(os.date("%H:%M"))
        date_lbl:set_text(os.date("%A, %d de %B"))
    end)

    -- Power buttons (iconos de icons-png/88/logout/)
    local ICON_DIR = (ICONS_DIR or os.getenv("HOME") ..
        "/proyectos/lanetk/icons-png") .. "/88/logout/"
    local pwr_power = PowerButton.new {
        icon_path = ICON_DIR .. "power.png",
        action    = "poweroff",
        theme     = theme,
        on_click  = function(a) if opts.on_power then opts.on_power(a) end end,
    }
    local pwr_reboot = PowerButton.new {
        icon_path = ICON_DIR .. "reboot.png",
        action    = "reboot",
        theme     = theme,
        on_click  = function(a) if opts.on_power then opts.on_power(a) end end,
    }
    local pwr_suspend = PowerButton.new {
        icon_path = ICON_DIR .. "suspend.png",
        action    = "suspend",
        theme     = theme,
        on_click  = function(a) if opts.on_power then opts.on_power(a) end end,
    }

    local power_row = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        children = {
            { widget = pwr_power,   weight = 0 },
            { widget = pwr_reboot,  weight = 0 },
            { widget = pwr_suspend, weight = 0 },
        },
    }

    -- ══ Armado del ctx para el layout ════════════════════════════
    -- Los widgets ya estan construidos. Ahora armamos un "contexto"
    -- con todo lo que el layout necesita, y delegamos la composicion
    -- al modulo elegido.

    local ctx = {
        -- Widgets de contenido
        user_dock      = user_dock,
        avatar         = avatar,
        name_lbl       = name_lbl,
        pass_input     = pass_input,
        go_btn         = go_btn,
        eye_btn        = eye_btn,
        error_lbl      = error_lbl,
        pills_container= pills_container,
        power_row      = power_row,
        clock_lbl      = clock_lbl,
        date_lbl       = date_lbl,

        -- Power buttons individuales (los layouts que quieran
        -- recomponer el row a su gusto los usan).
        pwr_power      = pwr_power,
        pwr_reboot     = pwr_reboot,
        pwr_suspend    = pwr_suspend,

        -- Clases y helpers (el layout los puede usar)
        Card           = Card,
        FloatingBlock  = FloatingBlock,
        Overlay        = Overlay,
        PillDock       = PillDock,
        PowerButton    = PowerButton,
        SessionPill    = SessionPill,

        -- Contexto del greeter
        srv            = srv,
        theme          = theme,
        username       = username,
        sessions       = sessions,
        current_idx    = current_idx,

        -- Helpers
        spacer         = spacer,
        centered       = centered,

        -- Horas / fechas (los layouts que quieran fuentes distintas
        -- a las de centered las usan para construir sus propios Text).
        clock_str = function() return os.date("%H:%M") end,
        date_str  = function() return os.date("%A, %d de %B") end,
    }

    -- Elegir el layout. Prioridad:
    --   1. opts.layout (pasado por main.lua en CLI)
    --   2. config, clave "layout"
    --   3. "centered"
    local layout_name = opts.layout or cfg.layout or "centered"
    log.info("greeter", "layout: %s", layout_name)

    local layout_mod = require("layouts." .. layout_name)
    local layout = layout_mod.build(ctx)

    -- ══ API publica ══════════════════════════════════════════════

    update_pills()

    local function set_error(msg)
        error_lbl:set_text(msg or "")
    end

    get_current_username = function()
        local u = current_user()
        return u and u.username or (os.getenv("USER") or "user")
    end

    -- Registra el usuario autenticado en last_user. Se llama desde
    -- main.lua cuando greetd confirma el success de la autenticacion.
    record_login = function()
        local u = current_user()
        if u then
            last_user.set(u.username)
        end
    end
    local function clear_password()
        pass_input:set_text("")
    end
    local function focus_password()
        pass_input:set_focused(true)
    end

    log.info("greeter", "factory OK (user=%s, %d sesiones)",
        username, #sessions)

    return {
        widget = layout,
        start = function()
            focus_password()
        end,
        stop = function() end,

        set_error        = set_error,
        clear_password   = clear_password,
        focus_password   = focus_password,
        current_session  = function() return sessions[current_idx] end,
        current_username = get_current_username,
        record_login     = record_login,
    }
end

return M
