-- Layout "centered": el actual.
-- Reloj flotante arriba-izquierda, card centrada con avatar, nombre,
-- input, pills y power.
--
-- M.build(ctx) recibe los widgets ya armados (via ctx) y devuelve el
-- Area raiz.

local W = require("lib.widgets")
local Area = require("lib.area")

local M = {}

function M.build(ctx)
    local avatar         = ctx.avatar
    local name_lbl       = ctx.name_lbl
    local pass_input     = ctx.pass_input
    local go_btn         = ctx.go_btn
    local error_lbl      = ctx.error_lbl
    local pills_container= ctx.pills_container
    local power_row      = ctx.power_row
    local clock_lbl      = ctx.clock_lbl
    local date_lbl       = ctx.date_lbl
    local Card           = ctx.Card
    local FloatingBlock  = ctx.FloatingBlock
    local theme          = ctx.theme
    local spacer         = ctx.spacer
    local centered       = ctx.centered

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

    local card_content = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        padding = 32,
        children = {
            { widget = centered(avatar), weight = 0 },
            { widget = spacer(20), weight = 0 },
            { widget = centered(name_lbl), weight = 0 },
            { widget = spacer(28), weight = 0 },
            { widget = input_row, weight = 0 },
            { widget = spacer(10), weight = 0 },
            { widget = centered(error_lbl), weight = 0 },
            { widget = spacer(20), weight = 0 },
            { widget = pills_container, weight = 0 },
            { widget = spacer(24), weight = 0 },
            { widget = centered(power_row), weight = 0 },
        },
    }

    local card = Card.new {
        content = card_content,
        bg_rgb  = theme.bg_card_rgb,
        alpha   = 0.92,
        radius  = 0,
    }

    local clock_block = FloatingBlock.new {
        content = W.Group.new {
            orientation = "vertical",
            spacing = 0,
            padding = 0,
            children = {
                -- Baja el reloj sin afectar su alineacion horizontal.
                -- El padding uniforme del Group movia el texto a la
                -- derecha y hacia abajo. Con un spacer vertical el
                -- desplazamiento es solo hacia abajo.
                { widget = spacer(35), weight = 0 },
                { widget = W.Group.new {
                    orientation = "horizontal",
                    spacing = 12,
                    padding = 0,
                    children = {
                        { widget = spacer(3), weight = 0 },
                        { widget = clock_lbl, weight = 0 },
                        { widget = date_lbl,  weight = 0 },
                    },
                }, weight = 0 },
            },
        },
        block_width = 500,
        block_height = 90,
    }

    local middle_row = W.Group.new {
        orientation = "vertical",
        padding = 0,
        children = {
            { widget = W.Text.new { text = "" }, weight = 1 },
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {
                    { widget = W.Text.new { text = "" }, weight = 0,
                      min_width = 40, max_width = 40 },
                    { widget = card, weight = 1 },
                    { widget = W.Text.new { text = "" }, weight = 0,
                      min_width = 40, max_width = 40 },
                },
            }, weight = 0 },
            { widget = W.Text.new { text = "" }, weight = 1 },
        },
    }

    return W.Group.new {
        orientation = "vertical",
        spacing = 0,
        padding = 0,
        children = {
            { widget = clock_block, weight = 0 },
            { widget = middle_row,  weight = 1 },
        },
    }
end

return M
