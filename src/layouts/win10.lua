-- Layout "win10": pantalla de login de Windows 10.
--
-- Reloj + fecha grandes abajo-izquierda. Power abajo-derecha.
-- Pills de sesion arriba-derecha. Centro: avatar, nombre, input.
-- Sin card.
--
-- Estructura: un Overlay da a todos sus hijos el rect completo.
-- El "center_col" ocupa todo pero centra su contenido (spacers
-- con weight 1). Los FloatingBlock tambien reciben el rect
-- completo y anclan en su esquina.

local W = require("lib.widgets")

local M = {}

function M.build(ctx)
    local avatar          = ctx.avatar
    local pass_input      = ctx.pass_input
    local go_btn          = ctx.go_btn
    local error_lbl       = ctx.error_lbl
    local pills_container = ctx.pills_container
    local power_row       = ctx.power_row
    local theme           = ctx.theme
    local spacer          = ctx.spacer
    local centered        = ctx.centered
    local FloatingBlock   = ctx.FloatingBlock
    local Overlay         = ctx.Overlay

    -- Reloj grande + fecha, propios de este layout.
    local clock_lbl = W.Text.new {
        text = ctx.clock_str(),
        font = "DejaVu Sans Thin 56",
        r = 0.98, g = 0.98, b = 0.98,
        align = "left", valign = "center",
    }
    local date_lbl = W.Text.new {
        text = ctx.date_str(),
        font = "DejaVu Sans 14",
        r = theme.fg_rgb[1], g = theme.fg_rgb[2], b = theme.fg_rgb[3],
        align = "left", valign = "center",
    }
    ctx.srv:add_timer(1000, function()
        clock_lbl:set_text(ctx.clock_str())
        date_lbl:set_text(ctx.date_str())
    end)

    local name_big = W.Text.new {
        text = ctx.username,
        font = "DejaVu Sans Bold 22",
        r = theme.fg_rgb[1], g = theme.fg_rgb[2], b = theme.fg_rgb[3],
        align = "center", valign = "center",
    }

    local input_row = W.Group.new {
        orientation = "horizontal",
        spacing = 6,
        children = {
            { widget = W.Text.new { text = "" }, weight = 1 },
            { widget = pass_input, weight = 0 },
            { widget = go_btn,     weight = 0 },
            { widget = W.Text.new { text = "" }, weight = 1 },
        },
    }

    -- Center col: ocupa todo el rect y centra verticalmente.
    local center_col = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        padding = 0,
        children = {
            { widget = spacer(0), weight = 1 },
            { widget = centered(avatar), weight = 0 },
            { widget = spacer(24), weight = 0 },
            { widget = centered(name_big), weight = 0 },
            { widget = spacer(20), weight = 0 },
            { widget = input_row, weight = 0 },
            { widget = spacer(10), weight = 0 },
            { widget = centered(error_lbl), weight = 0 },
            { widget = spacer(0), weight = 1 },
        },
    }

    -- Reloj flotante abajo-izquierda.
    local clock_block = FloatingBlock.new {
        content = W.Group.new {
            orientation = "vertical",
            spacing = 4,
            padding = 40,
            children = {
                { widget = clock_lbl, weight = 0 },
                { widget = date_lbl,  weight = 0 },
            },
        },
        anchor = "bottom-left",
        block_width = 500,
        block_height = 160,
    }

    -- Pills flotantes arriba-derecha.
    pills_container.align = "right"

    local pills_block = FloatingBlock.new {
        content = W.Group.new {
            orientation = "horizontal",
            padding = 24,
            children = {
                { widget = W.Text.new { text = "" }, weight = 1 },
                { widget = pills_container, weight = 0 },
            },
        },
        anchor = "top-right",
        block_width = 600,
        block_height = 80,
    }

    -- Power flotante abajo-derecha.
    local power_block = FloatingBlock.new {
        content = W.Group.new {
            orientation = "vertical",
            padding = 40,
            children = {
                { widget = W.Text.new { text = "" }, weight = 1 },
                { widget = power_row, weight = 0 },
            },
        },
        anchor = "bottom-right",
        block_width = 200,
        block_height = 160,
    }

    -- Overlay: todos los hijos reciben el rect completo.
    -- El orden decide stacking: center_col primero, capas
    -- flotantes despues (dibujan encima).
    local ov = Overlay.new {}
    ov:add(center_col)
    ov:add(clock_block)
    ov:add(pills_block)
    ov:add(power_block)
    return ov
end

return M
