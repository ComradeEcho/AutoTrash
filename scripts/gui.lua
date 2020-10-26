local gui = require("__flib__.gui")
local table =require("__flib__.table")
local constants = require("constants")

local lib_control = require '__AutoTrash__.lib_control'
local format_number = lib_control.format_number
local format_request = lib_control.format_request
local format_trash = lib_control.format_trash
local convert_to_slider = lib_control.convert_to_slider
local convert_from_slider = lib_control.convert_from_slider
local display_message = lib_control.display_message
local item_prototype = lib_control.item_prototype
local in_network = lib_control.in_network
local get_non_equipment_network = lib_control.get_non_equipment_network
local set_requests = lib_control.set_requests
local pause_trash = lib_control.pause_trash
local unpause_trash = lib_control.unpause_trash
local presets = require("presets")

local function tonumber_max(n)
    n = tonumber(n)
    return (n and n > constants.max_request) and constants.max_request or n
end

local function get_network_data(player)
    local character = player.character
    if not character then return end
    local network = get_non_equipment_network(character)
    local requester = character.get_logistic_point(defines.logistic_member_index.character_requester)
    if not (network and requester and network.valid and requester.valid) then
        return
    end
    local on_the_way = requester.targeted_items_deliver
    local available = network.get_contents()
    local item_count = player.get_main_inventory().get_contents()
    local cursor_stack = player.cursor_stack
    cursor_stack = (cursor_stack and cursor_stack.valid_for_read) and {[cursor_stack.name] = cursor_stack.count} or {}
    local get_inventory, inventory = player.get_inventory, defines.inventory
    local armor = get_inventory(inventory.character_armor).get_contents()
    local gun = get_inventory(inventory.character_guns).get_contents()
    local ammo = get_inventory(inventory.character_ammo).get_contents()

    return available, on_the_way, item_count, cursor_stack, armor, gun, ammo
end

local at_gui = {
    defines = {
        trash_above_requested = "trash_above_requested",
        trash_unrequested = "trash_unrequested",
        trash_network = "trash_network",
        pause_trash = "pause_trash",
        pause_requests = "pause_requests",
        network_button = "network_button",
    },
}

function at_gui.register_handlers()
    for name, id in pairs(defines.events) do
        if string.sub(name, 1, 6) == "on_gui" then
            script.on_event(id, at_gui.dispatch_handlers)
        end
    end
end

function at_gui.dispatch_handlers(event_data)
    event_data.player = game.get_player(event_data.player_index)
    event_data.pdata = global._pdata[event_data.player_index]
    return gui.dispatch_handlers(event_data)
end

local function import_presets(player, pdata, add_presets, stack)
    if stack and stack.valid_for_read then
        if stack.is_blueprint and stack.is_blueprint_setup() then
            local preset, cc_found = presets.import(stack.get_blueprint_entities(), stack.blueprint_icons)
            if cc_found then
                pdata.config_tmp = preset
                player.print({"string-import-successful", "AutoTrash configuration"})
                pdata.selected = false
                at_gui.update_buttons(pdata)
                at_gui.update_sliders(pdata)
                at_gui.mark_dirty(pdata)
                --named preset
                if stack.label and stack.label ~= "Autotrash_configuration" then
                    local textfield = pdata.gui.main.preset_textfield
                    local preset_name = string.sub(stack.label, 11)
                    if add_presets and at_gui.add_preset(player, pdata, preset_name, preset) then
                        pdata.selected_presets = {[preset_name] = true}
                        at_gui.update_presets(pdata)
                    end
                    textfield.text = preset_name
                    player.clean_cursor()
                    textfield.focus()
                end
            else
                player.print({"", {"error-while-importing-string"}, " ", {"autotrash_import_error"}})
            end
            return true
        elseif add_presets and stack.is_blueprint_book then
            local book_inventory = stack.get_inventory(defines.inventory.item_main)
            local any_cc = false
            for i = 1, #book_inventory do
                local bp = book_inventory[i]
                if bp.valid_for_read and bp.is_blueprint_setup() then
                    local config, cc = presets.import(bp.get_blueprint_entities(), bp.blueprint_icons)
                    if cc then
                        any_cc = true
                        at_gui.add_preset(player, pdata, bp.label, config)
                    end
                end
            end
            if any_cc then
                at_gui.update_presets(pdata)
            else
                player.print({"", {"error-while-importing-string"}, " ", {"autotrash_import_error"}})
            end
            return true
        end
    end
    return false
end

at_gui.toggle_setting = {
    trash_above_requested = function(player, pdata)
        set_requests(player, pdata)
        return pdata.flags.trash_above_requested
    end,
    trash_unrequested = function(player, pdata)
        set_requests(player, pdata)
        return pdata.flags.trash_unrequested
    end,
    trash_network = function(player, pdata)
        if pdata.flags.trash_network and not pdata.main_network then
            player.print("No main network set")
            pdata.flags.trash_network = false
            return false
        end

        if pdata.flags.trash_network and in_network(player, pdata) then
            unpause_trash(player, pdata)
            at_gui.update_main_button(pdata)
        end
        return pdata.flags.trash_network
    end,
    pause_trash = function(player, pdata)
        if pdata.flags.pause_trash then
            pause_trash(player, pdata)
        else
            unpause_trash(player, pdata)
        end
        at_gui.update_main_button(pdata)
        return pdata.flags.pause_trash
    end,
    pause_requests = function(player, pdata)
        if pdata.flags.pause_requests then
            lib_control.pause_requests(player, pdata)
        else
            lib_control.unpause_requests(player, pdata)
        end
        at_gui.update_main_button(pdata)
        at_gui.update_status_display(player, pdata)
        return pdata.flags.pause_requests
    end,
}

at_gui.templates = {
    slot_table = {
        main = function(btns, pdata)
            local ret = {type = "table", column_count = constants.slot_columns, style = "at_filter_group_table", save_as = "main.slot_table",
                style_mods = {minimal_height = constants.slot_table_height}, children = {}}
            for i=1, btns do
                ret.children[i] = gui.templates.slot_table.button(i, pdata)
            end
            ret.children[btns+1] = {type = "flow", name = "count_change", direction="vertical", style_mods = {vertical_spacing=0}, children={
                {type = "button", caption="-", handlers="slots.decrease", style = "slot_count_change_button"},
                {type = "button", caption="+", handlers = "slots.increase", style = "slot_count_change_button"}
            }}
            return ret
        end,
        button = function(i, pdata)
            local style = (i == pdata.selected) and "at_button_slot_selected" or "at_button_slot"
            local config = pdata.config_tmp.config[i]
            local req = config and config.request or "0"
            local trash = config and config.trash or "∞"
            return {type = "choose-elem-button", name = i, elem_mods = {elem_value = config and config.name, locked = config and i ~= pdata.selected}, handlers = "slots.item_button", elem_type = "item", style = style, children = {
                {type = "label", style = "at_request_label_top", ignored_by_interaction = true, caption = config and req or ""},
                {type = "label", style = "at_request_label_bottom", ignored_by_interaction = true, caption = config and trash or ""}
            }}
        end,
        count_change = function()
            return {type = "flow", name = "count_change", direction="vertical", style_mods = {vertical_spacing=0}, children={
                {type = "button", caption="-", handlers="slots.decrease", style = "slot_count_change_button"},
                {type = "button", caption="+", handlers = "slots.increase", style = "slot_count_change_button"}
            }}
        end,
    },
    frame_action_button = {type = "sprite-button", style = "frame_action_button", mouse_button_filter={"left"}},
    pushers = {
        horizontal = {type = "empty-widget", style_mods = {horizontally_stretchable = true}},
        vertical = {type = "empty-widget", style_mods = {vertically_stretchable = true}}
    },
    import_export_window = function(bp_string, mode)
        local caption = bp_string and {"gui.export-to-string"} or {"gui-blueprint-library.import-string"}
        local button_caption = bp_string and {"gui.close"} or {"gui-blueprint-library.import"}
        local button_handler = bp_string and "import.close_button" or "import.import_button"
        return {type = "frame", save_as = "window.main", style = "inner_frame_in_outer_frame", direction = "vertical", children = {
                {type = "flow", save_as = "window.titlebar", children = {
                    {type = "label", style = "frame_title", caption = caption, elem_mods = {ignored_by_interaction = true}},
                    {type = "empty-widget", style = "flib_titlebar_drag_handle", elem_mods = {ignored_by_interaction = true}},
                    {template = "frame_action_button", sprite = "utility/close_white", hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black",
                        handlers = "import.close_button", save_as = "close_button"}
                }},
                {type = "text-box", text = bp_string, save_as = "window.textbox", elem_mods = {word_wrap = true}, style_mods = {width=400, height = 250}},
                {type = "flow", direction = "horizontal", children={
                        {template = "pushers.horizontal"},
                        {type = "label", name = "mode", caption = mode, visible = false},
                        {type = "button", handlers = button_handler, style = "dialog_button", caption = button_caption}
                }}
            }}
    end,

    settings = function(flags, pdata)
        return {type = "frame", style = "bordered_frame", style_mods = {right_padding = 8, horizontally_stretchable = "on"}, children = {
            {type = "flow", direction = "vertical", save_as = "main.trash_options", children = {
                {
                    type = "checkbox",
                    name = at_gui.defines.trash_above_requested,
                    caption = {"auto-trash-above-requested"},
                    state = flags.trash_above_requested,
                    handlers = "settings.toggle"
                },
                {
                    type = "checkbox",
                    name = at_gui.defines.trash_unrequested,
                    caption = {"auto-trash-unrequested"},
                    state = flags.trash_unrequested,
                    handlers = "settings.toggle"
                },
                {
                    type = "checkbox",
                    name = at_gui.defines.trash_network,
                    caption = {"auto-trash-in-main-network"},
                    state = flags.trash_network,
                    handlers = "settings.toggle"
                },
                {
                    type = "checkbox",
                    name = at_gui.defines.pause_trash,
                    caption = {"auto-trash-config-button-pause"},
                    tooltip = {"auto-trash-tooltip-pause"},
                    state = flags.pause_trash,
                    handlers = "settings.toggle"
                },
                {
                    type = "checkbox",
                    name = at_gui.defines.pause_requests,
                    caption = {"auto-trash-config-button-pause-requests"},
                    tooltip = {"auto-trash-tooltip-pause-requests"},
                    state = flags.pause_requests,
                    handlers = "settings.toggle"
                },
                {
                    type = "button",
                    name = at_gui.defines.network_button,
                    caption = pdata.main_network and {"auto-trash-unset-main-network"} or {"auto-trash-set-main-network"},
                    handlers = "settings.change_network"
                },
                {template = "pushers.horizontal"}
            }},
            -- {template = "pushers.vertical"},
        }}
    end,

    preset = function(preset_name, pdata)
        local style = pdata.selected_presets[preset_name] and "at_preset_button_selected" or "at_preset_button"
        local rip_style = pdata.death_presets[preset_name] and "at_preset_button_small_selected" or "at_preset_button_small"
        return {type = "flow", direction = "horizontal", name = preset_name, children = {
            {type = "button", style = style, caption = preset_name, name = preset_name, handlers = "presets.load"},
            {type = "sprite-button", style = rip_style, sprite = "autotrash_rip", handlers = "presets.change_death_preset", tooltip = {"autotrash_tooltip_rip"}},
            {type = "sprite-button", style = "at_delete_preset", sprite = "utility/trash", handlers = "presets.delete"},
        }}
    end,

    presets = function(pdata)
        local ret = {}
        local i = 1
        for name in pairs(pdata.presets) do
            ret[i] = gui.templates.preset(name, pdata)
            i = i + 1
        end
        return ret
    end,
}
gui.add_templates(at_gui.templates)

at_gui.handlers = {
    mod_gui_button = {
        on_gui_click = function(e)
            at_gui.toggle(e.player, e.pdata)
        end,
    },
    main = {
        close_button = {
            on_gui_click = function(e)
                at_gui.close(e.pdata)
            end
        },
        window = {
            on_gui_closed = function(e)
                at_gui.close(e.pdata)
            end
        },
        apply_changes = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                pdata.config_new = table.deep_copy(pdata.config_tmp)
                pdata.dirty = false
                pdata.gui.main.reset_button.enabled = false
                if pdata.settings.close_on_apply then
                    at_gui.close(pdata)
                end

                set_requests(player, pdata)
                at_gui.update_status_display(player, pdata)
            end
        },
        reset = {
            on_gui_click = function(e)
                local pdata = e.pdata
                if pdata.flags.dirty then
                    pdata.config_tmp = table.deep_copy(pdata.config_new)
                    e.element.enabled = false
                    pdata.selected_presets = {}
                    pdata.selected = false
                    pdata.flags.dirty = false
                    at_gui.update_sliders(pdata)
                    at_gui.update_buttons(pdata)
                    at_gui.update_presets(pdata)
                end
            end
        },
        export = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                local name
                if table_size(pdata.selected_presets) == 1 then
                    name = "AutoTrash_" .. next(pdata.selected_presets)
                else
                    name = "AutoTrash_configuration"
                end
                local text = presets.export(pdata.config_tmp, name)
                if e.shift then
                    local stack = player.cursor_stack
                    if stack.valid_for_read then
                        player.print("Click with an empty cursor")
                        return
                    else
                        if stack.import_stack(text) ~= 0 then
                            player.print({"failed-to-import-string", name})
                            return
                        end
                    end
                else
                    at_gui.create_import_window(player, pdata, text, "single")
                end
            end
        },
        export_all = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                if not next(pdata.presets) then
                    display_message(player, "", true)
                end
                local text = presets.export_all(pdata)
                if e.shift then
                    local stack = player.cursor_stack
                    if stack.valid_for_read then
                        player.print("Click with an empty cursor")
                        return
                    else
                        if stack.import_stack(text) ~= 0 then
                            player.print({"failed-to-import-string"})
                            return
                        end
                    end
                else
                    at_gui.create_import_window(player, pdata, text, "all")
                end
            end
        },
        import = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                if not import_presets(player, pdata, false, player.cursor_stack) then
                    at_gui.create_import_window(player, pdata, nil, "single")
                end
            end
        },
        import_all = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                if not import_presets(player, pdata, true, player.cursor_stack) then
                    at_gui.create_import_window(player, pdata, nil, "all")
                end
            end
        }
    },
    slots = {
        item_button = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                local elem_value = e.element.elem_value
                local old_selected = pdata.selected
                local index = tonumber(e.element.name)
                if e.button == defines.mouse_button_type.right then
                    if not elem_value then
                        pdata.selected = false
                        at_gui.update_button(pdata, old_selected, pdata.gui.main.slot_table.children[old_selected])
                        at_gui.update_sliders(pdata)
                        return
                    end
                    at_gui.clear_button(pdata, index, e.element)
                elseif e.button == defines.mouse_button_type.left then
                    if e.shift then
                        local config_tmp = pdata.config_tmp
                        local cursor_ghost = player.cursor_ghost
                        if elem_value and not cursor_ghost and not player.cursor_stack.valid_for_read then
                            pdata.selected = index
                            player.cursor_ghost = elem_value
                        elseif cursor_ghost and cursor_ghost.name == config_tmp.config[old_selected].name then
                            if elem_value then--always true, even when shift clicking an empty button with a ghost, since it gets set before on_click
                                local tmp = table.deep_copy(config_tmp.config[index])
                                config_tmp.config[index] = table.deep_copy(config_tmp.config[old_selected])
                                config_tmp.config[index].slot = index
                                if tmp then
                                    tmp.slot = old_selected
                                end
                                config_tmp.config[old_selected] = tmp
                                player.cursor_ghost = nil
                                pdata.selected = index
                                config_tmp.max_slot = index > config_tmp.max_slot and index or config_tmp.max_slot
                                at_gui.mark_dirty(pdata)
                            end
                        end
                        at_gui.update_button(pdata, index, e.element)
                        at_gui.update_button(pdata, old_selected)
                        at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                        at_gui.update_sliders(pdata)
                        return
                    end
                    if not elem_value or old_selected == index then return end
                    pdata.selected = index
                    if old_selected then
                        local old = pdata.gui.main.slot_table.children[old_selected]
                        at_gui.update_button(pdata, old_selected, old)
                    end
                    at_gui.update_button(pdata, index, e.element)
                    at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                    at_gui.update_sliders(pdata)
                end
            end,
            on_gui_elem_changed = function(e)
                local player = e.player
                if player.cursor_ghost then return end--dragging to an empty slot, on_gui_click raised later
                local pdata = e.pdata
                local elem_value = e.element.elem_value
                local old_selected = pdata.selected
                local index = tonumber(e.element.name)
                if elem_value then
                    local item_config = pdata.config_tmp.config[index]
                    if item_config and elem_value == item_config.name then return end
                    for i, v in pairs(pdata.config_tmp.config) do
                        if i ~= index and elem_value == v.name then
                            display_message(player, {"", {"cant-set-duplicate-request", item_prototype(elem_value).localised_name}}, true)
                            pdata.selected = i
                            at_gui.update_button(pdata, i, pdata.gui.main.slot_table.children[i])
                            pdata.gui.main.config_rows.scroll_to_element(pdata.gui.main.slot_table.children[i], "top-third")
                            if item_config then
                                e.element.elem_value = item_config.name
                            else
                                e.element.elem_value = nil
                            end
                            at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                            at_gui.update_sliders(pdata)
                            return
                        end
                    end
                    pdata.selected = index
                    local request_amount = item_prototype(elem_value).default_request_amount
                    local trash_amount = pdata.settings.trash_equals_requests and request_amount or false
                    local config_tmp = pdata.config_tmp
                    config_tmp.config[index] = {
                        name = elem_value, request = request_amount,
                        trash = trash_amount, slot = index
                    }
                    config_tmp.max_slot = index > config_tmp.max_slot and index or config_tmp.max_slot
                    if config_tmp.config[index].request > 0 then
                        config_tmp.c_requests = config_tmp.c_requests + 1
                    end
                    at_gui.mark_dirty(pdata)
                    at_gui.update_button(pdata, index, e.element)
                    if old_selected then
                        at_gui.update_button(pdata, old_selected, pdata.gui.main.slot_table.children[old_selected])
                    end
                    at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                    at_gui.update_sliders(pdata)
                else
                    at_gui.clear_button(pdata, index, e.element)
                end
            end
        },
        decrease = {
            on_gui_click = function (e)
                local player = e.player
                local old_slots = player.character_logistic_slot_count
                local slots = old_slots > 9 and old_slots - 10 or old_slots
                at_gui.decrease_slots(player, e.pdata, slots, old_slots)
            end,
        },
        increase = {
            on_gui_click = function(e)
                local player = e.player
                local old_slots = player.character_logistic_slot_count
                at_gui.increase_slots(player, e.pdata, old_slots + 10, old_slots)
            end,
        },
    },
    presets = {
        save = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                local textfield = pdata.gui.main.preset_textfield
                local name = textfield.text
                if at_gui.add_preset(player, pdata, name) then
                    pdata.selected_presets = {[name] = true}
                    at_gui.update_presets(pdata)
                else
                    textfield.focus()
                end

            end
        },
        load = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                local name = e.element.caption
                if not e.shift and not e.control then
                    pdata.selected_presets = {[name] = true}
                    pdata.config_tmp = table.deep_copy(pdata.presets[name])
                    pdata.selected = false
                    pdata.gui.main.preset_textfield.text = name
                    local slots = player.character_logistic_slot_count
                    local diff = pdata.config_tmp.max_slot - slots
                    if diff > 0 then
                        local inc = math.ceil(diff / 10) * 10
                        at_gui.increase_slots(player, pdata, slots + inc, slots)
                    end
                else
                    local selected_presets = pdata.selected_presets
                    if not selected_presets[name] then
                        selected_presets[name] = true
                    else
                        selected_presets[name] = nil
                    end
                    local tmp = {config = {}, max_slot = 0, c_requests = 0}
                    for key, _ in pairs(selected_presets) do
                        presets.merge(tmp, pdata.presets[key])
                    end
                    pdata.config_tmp = tmp
                    pdata.selected = false
                end
                at_gui.mark_dirty(pdata, true)
                at_gui.update_buttons(pdata)
                at_gui.update_presets(pdata)
                at_gui.update_sliders(pdata)
            end
        },
        delete = {
            on_gui_click = function(e)
                local pdata = e.pdata
                local parent = e.element.parent
                local name = parent.name
                gui.update_filters("presets", e.player_index, {e.element.index, parent.children[1].index, parent.children[2].index}, "remove")
                parent.destroy()
                pdata.selected_presets[name] = nil
                pdata.death_presets[name] = nil
                pdata.presets[name] = nil
                at_gui.update_presets(pdata)
        end
        },
        change_death_preset = {
            on_gui_click = function(e)
                local pdata = e.pdata
                local name = e.element.parent.name
                if not (e.shift or e.control) then
                    pdata.death_presets = {[name] = true}
                else
                    local selected_presets = pdata.death_presets
                    if not selected_presets[name] then
                        selected_presets[name] = true
                    else
                        selected_presets[name] = nil
                    end
                end
                at_gui.update_presets(pdata)
            end,
        },
        textfield = {
            on_gui_click = function(e)
                e.element.select_all()
            end
        }
    },
    sliders = {
        request = {
            on_gui_value_changed = function(e)
                local pdata = e.pdata
                if not pdata.selected then return end
                at_gui.update_request_config(tonumber_max(convert_from_slider(e.element.slider_value)) or 0, pdata)
            end,
            on_gui_text_changed = function(e)
                local pdata = e.pdata
                if not pdata.selected then return end
                at_gui.update_request_config(tonumber_max(e.element.text) or 0, pdata)
            end
        },
        trash = {
            on_gui_value_changed = function(e)
                local pdata = e.pdata
                if not pdata.selected then return end
                local number
                if e.element.slider_value == 42 then
                    number = false
                else
                    number = tonumber_max(convert_from_slider(e.element.slider_value)) or false
                end
                at_gui.update_trash_config(number, pdata)
            end,
            on_gui_text_changed = function(e)
                local pdata = e.pdata
                if not pdata.selected then return end
                at_gui.update_trash_config(tonumber_max(e.element.text) or false, pdata)
            end
        }
    },
    quick_actions = {
        on_gui_selection_state_changed = function(e)
            local pdata = e.pdata
            local element = e.element
            local index = element.selected_index
            if index == 1 then return end

            local config_tmp = pdata.config_tmp
            if index == 2 then
                for _, config in pairs(config_tmp.config) do
                    config.request = 0
                end
                config_tmp.c_requests = 0
            elseif index == 3 then
                for _, config in pairs(config_tmp.config) do
                    config.trash = false
                end
            elseif index == 4 then
                config_tmp.config = {}
                config_tmp.max_slot = 0
                config_tmp.c_requests = 0
                pdata.selected = false
            elseif index == 5 then
                for _, config in pairs(config_tmp.config) do
                    if config.request > 0 then
                        config.trash = config.request
                    end
                end
            elseif index == 6 then
                local c = 0
                for _, config in pairs(config_tmp.config) do
                    if config.trash then
                        config.request = config.trash
                        c = config.request > 0 and c + 1 or c
                    end
                end
                config_tmp.c_requests = c
            end
            element.selected_index = 1
            at_gui.mark_dirty(pdata)
            at_gui.update_sliders(pdata)
            at_gui.update_buttons(pdata)
        end
    },
    settings = {
        toggle = {
            on_gui_checked_state_changed = function(e)
                local pdata = e.pdata
                local name = e.element.name
                if at_gui.toggle_setting[name] then
                    pdata.flags[name] = e.element.state
                    e.element.state = at_gui.toggle_setting[name](e.player, pdata)
                end
            end
        },
        change_network = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                if pdata.main_network then
                    if not pdata.main_network.valid then
                        --ended up with an invalid entity, not much i can do to recover
                        player.print("AutoTrash lost the main network. You will have to set it again.")
                    end
                    pdata.main_network = false
                else
                    pdata.main_network = lib_control.get_network_entity(player)
                    if not pdata.main_network then
                        display_message(player, {"auto-trash-not-in-network"}, true)
                    end
                end
                at_gui.update_settings(pdata)
            end
        }
    },
    import = {
        import_button = {
            on_gui_click = function(e)
                local player = e.player
                local pdata = e.pdata
                local add_presets = e.element.parent.mode.caption == "all"
                local inventory = game.create_inventory(1)

                inventory.insert{name = "blueprint"}
                local stack = inventory[1]
                local result = stack.import_stack(pdata.gui.import.window.textbox.text)
                if result ~= 0 then
                    inventory.destroy()
                    return result
                end
                result = import_presets(player, pdata, add_presets, stack)
                inventory.destroy()
                if not result then
                    player.print({"failed-to-import-string", "Unknown error"})
                end
                gui.handlers.import.close_button.on_gui_click(e)
            end
        },
        close_button = {
            on_gui_click = function(e)
                local pdata = e.pdata
                gui.update_filters("import", e.player_index, nil, "remove")
                pdata.gui.import.window.main.destroy()
                pdata.gui.import = nil
            end
        }
    }
}
gui.add_handlers(at_gui.handlers)

at_gui.update_request_config = function(number, pdata)
    local selected = pdata.selected
    local config_tmp = pdata.config_tmp
    local item_config = config_tmp.config[selected]
    if number == item_config.request then return end
    if item_config.request == 0 and number > 0 then
        config_tmp.c_requests = config_tmp.c_requests + 1
    end
    if item_config.request > 0 and number == 0 then
        config_tmp.c_requests = config_tmp.c_requests > 0 and config_tmp.c_requests - 1 or 0
    end
    item_config.request = number
    --prevent trash being set to a lower value than request to prevent infinite robo loop
    if item_config.trash and number > item_config.trash then
        item_config.trash = number
    end
    at_gui.mark_dirty(pdata)
    at_gui.update_sliders(pdata)
    at_gui.update_button(pdata, pdata.selected)
end

at_gui.update_trash_config = function(number, pdata)
    local selected = pdata.selected
    local config_tmp = pdata.config_tmp
    local item_config = config_tmp.config[selected]
    if number == item_config.trash then return end

    if number and item_config.request > number then
        if item_config.request > 0 and number == 0 then
            config_tmp.c_requests = config_tmp.c_requests > 0 and config_tmp.c_requests - 1 or 0
        end
        item_config.request = number
    end
    item_config.trash = number
    at_gui.mark_dirty(pdata)
    at_gui.update_sliders(pdata)
    at_gui.update_button(pdata, pdata.selected)
end

at_gui.decrease_slots = function(player, pdata, slots, old_slots)
    if slots < pdata.config_tmp.max_slot then return end
    player.character_logistic_slot_count = slots
    local cols = constants.slot_columns
    local rows = constants.slot_rows
    local width = constants.slot_table_width
    width = (slots <= (rows*cols)) and width or (width + 12)
    local slot_table = pdata.gui.main.slot_table
    for i = old_slots, slots+1, -1 do
        local btn = slot_table.children[i]
        gui.update_filters("slots.item_button", player.index, {btn.index}, "remove")
        btn.destroy()
    end
    if slots == 9 then
        slot_table.count_change.children[1].enabled = false
    end
    pdata.gui.main.config_rows.style.width = width
    pdata.gui.main.config_rows.scroll_to_bottom()
end

at_gui.increase_slots = function(player, pdata, slots, old_slots)
    slots = slots <= 65529 and slots or 65529
    player.character_logistic_slot_count = slots
    local cols = constants.slot_columns
    local rows = constants.slot_rows
    local width = constants.slot_table_width
    width = (slots <= (rows*cols)) and width or (width + 12)


    local slot_table = pdata.gui.main.slot_table
    gui.update_filters("slots.decrease", player.index, nil, "remove")
    gui.update_filters("slots.increase", player.index, nil, "remove")
    slot_table.count_change.destroy()
    for i = old_slots+1, slots do
        gui.build(slot_table, {gui.templates.slot_table.button(i, pdata)})
    end
    gui.build(slot_table, {gui.templates.slot_table.count_change()})

    pdata.gui.main.config_rows.style.width = width
    pdata.gui.main.config_rows.scroll_to_bottom()
end

at_gui.update_buttons = function(pdata)
    if not pdata.flags.gui_open then return end
    local children = pdata.gui.main.slot_table.children
    for i=1, #children-1 do
        at_gui.update_button(pdata, i, children[i])
    end
end

at_gui.get_button_style = function(i, selected, item, available, on_the_way, item_count, cursor_stack, armor, gun, ammo, paused)
    if paused or not (available and on_the_way and item and item.request > 0) then
        return (i == selected) and "at_button_slot_selected" or "at_button_slot"
    end
    if i == selected then
        return "at_button_slot_selected"
    end
    local n = item.name
    local diff = item.request - ((item_count[n] or 0) + (armor[n] or 0) + (gun[n] or 0) + (ammo[n] or 0) + (cursor_stack[n] or 0))

    if diff <= 0 then
        return "at_button_slot"
    else
        local diff2 = diff - (on_the_way[n] or 0) - (available[n] or 0)
        if diff2 <= 0 then
            return "at_button_slot_items_on_the_way", diff
        elseif (on_the_way[n] and not available[n]) then
        --item.name == "locomotive" then
            return "at_button_slot_items_not_enough", diff
        end
        return "at_button_slot_items_not_available", diff
    end
end

at_gui.update_button_styles = function(player, pdata)
    local ruleset_grid = pdata.gui.main.slot_table
    if not (ruleset_grid and ruleset_grid.valid) then return end
    local selected = pdata.selected
    local config = pdata.config_tmp
    local available, on_the_way, item_count, cursor_stack, armor, gun, ammo = get_network_data(player)
    if not (available and on_the_way and config.c_requests > 0 and not pdata.flags.pause_requests) then
        local children = ruleset_grid.children
        for i=1, #children-1 do
            children[i].style = (i == selected) and "at_button_slot_selected" or "at_button_slot"
        end
        return
    end
    config = config.config
    local ret = {}
    local buttons = ruleset_grid.children
    for i=1, #buttons-1 do
        local item = config[i]
        local style, diff = at_gui.get_button_style(i, selected, config[i], available, on_the_way, item_count, cursor_stack, armor, gun, ammo)
        if item and item.request > 0 then
            ret[item.name] = {style, diff}
        end
        buttons[i].style = style
    end
    return ret
end

at_gui.update_button = function(pdata, i, button)
    if not (button and button.valid) then
        if not i then return end
        button = pdata.gui.main.slot_table.children[i]
    end
    local req = pdata.config_tmp.config[i]
    if req then
        button.children[1].caption = format_number(format_request(req), true)
        button.children[2].caption = format_number(format_trash(req), true)
        button.elem_value = req.name
        button.locked = i ~= pdata.selected
    else
        button.children[1].caption = ""
        button.children[2].caption = ""
        button.elem_value = nil
        button.locked = false
    end
    button.style = (i == pdata.selected) and "at_button_slot_selected" or "at_button_slot"
end

at_gui.clear_button = function(pdata, index, button)
    local config_tmp = pdata.config_tmp
    if config_tmp.config[index].request > 0 then
        config_tmp.c_requests = config_tmp.c_requests > 0 and config_tmp.c_requests - 1 or 0
    end
    if pdata.selected == index then pdata.selected = false end
    config_tmp.config[index] = nil
    if index == config_tmp.max_slot then
        config_tmp.max_slot = 0
        for i = index-1, 1, -1 do
            if config_tmp.config[i] then
                config_tmp.max_slot = i
                break
            end
        end
    end
    at_gui.mark_dirty(pdata)
    at_gui.update_button(pdata, index, button)
    at_gui.update_sliders(pdata)
end

at_gui.update_sliders = function(pdata)
    if not pdata.flags.gui_open then return end
    if pdata.selected then
        local sliders = pdata.gui.main.sliders
        local item_config = pdata.config_tmp.config[pdata.selected]
        if item_config then
            sliders.request.slider_value = convert_to_slider(item_config.request)
            sliders.request_text.text = format_request(item_config) or 0

            sliders.trash.slider_value = item_config.trash and convert_to_slider(item_config.trash) or 42
            sliders.trash_text.text = format_trash(item_config) or "∞"
        end
    end
    local visible = pdata.selected and true or false
    for _, child in pairs(pdata.gui.main.sliders.table.children) do
        child.visible = visible
    end
end

at_gui.add_preset = function(player, pdata, name, config)
    config = config or pdata.config_tmp
    if name == "" then
        display_message(player, {"auto-trash-storage-name-not-set"}, true)
        return
    end
    if pdata.presets[name] then
        if not pdata.settings.overwrite then
            display_message(player, {"auto-trash-storage-name-in-use"}, true)
            return
        end
        pdata.presets[name] = table.deep_copy(config)
        display_message(player, "Preset " .. name .." updated", "success")
    else
        pdata.presets[name] = table.deep_copy(config)
        gui.build(pdata.gui.main.presets_flow, {gui.templates.preset(name, pdata)})
    end
    return true
end

at_gui.update_presets = function(pdata)
    if not pdata.flags.gui_open then return end
    local children = pdata.gui.main.presets_flow.children
    local selected_presets = pdata.selected_presets
    local death_presets = pdata.death_presets
    for i=1, #children do
        local preset = children[i].children[1]
        local rip = children[i].children[2]
        local preset_name = preset.caption
        preset.style = selected_presets[preset_name] and "at_preset_button_selected" or "at_preset_button"
        rip.style = death_presets[preset_name] and "at_preset_button_small_selected" or "at_preset_button_small"
    end
    local s = table_size(selected_presets)
    if s == 1 then
        pdata.gui.main.preset_textfield.text = next(selected_presets)
    elseif s > 1 then
        pdata.gui.main.preset_textfield.text = ""
    end
end

function at_gui.create_main_window(player, pdata)
    local flags = pdata.flags
    pdata.selected = false
    local cols = constants.slot_columns
    local rows = constants.slot_rows
    local btns = player.character_logistic_slot_count
    local width = constants.slot_table_width
    local height = constants.slot_table_height
    width = (btns <= (rows*cols)) and width or (width + 12)
    local gui_data = gui.build(player.gui.screen,{
        {type = "frame", style = "outer_frame", handlers = "main.window", save_as = "main.window", children = {
            {type = "frame", style = "inner_frame_in_outer_frame", direction = "vertical", style_mods = {maximal_height = 656}, children = {
                {type = "flow", save_as = "main.titlebar.flow", children = {
                    {type = "label", style = "frame_title", caption = "Auto Trash", elem_mods = {ignored_by_interaction = true}},
                    {type = "empty-widget", style = "flib_titlebar_drag_handle", elem_mods = {ignored_by_interaction = true}},
                    {template = "frame_action_button", sprite = "utility/close_white", hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black",
                        handlers = "main.close_button", save_as = "main.titlebar.close_button"}
                }},
                {type = "flow", direction = "horizontal", style_mods = {horizontal_spacing = 12}, children = {
                    {type = "frame", style = "inside_shallow_frame", direction = "vertical", children = {
                        {type = "frame", style = "subheader_frame", children={
                            {type = "label", style = "subheader_caption_label", caption = "Logistics configuration"},
                            {template = "pushers.horizontal"},
                            {type = "sprite-button", style = "tool_button_green", handlers = "main.apply_changes", style_mods = {padding = 0},
                                sprite = "utility/check_mark_white", tooltip = {"module-inserter-config-button-apply"}},
                            {type = "sprite-button", style = "tool_button_red", save_as = "main.reset_button", handlers = "main.reset", sprite = "utility/reset_white"},
                            {type = "sprite-button", style = "tool_button", handlers = "main.export", sprite = "utility/export_slot", tooltip = {"autotrash_export_tt"}},
                            {type = "sprite-button", style = "tool_button", handlers = "main.import", sprite = "mi_import_string", tooltip = {"autotrash_import_tt"}}
                        }},
                        {type = "flow", direction="vertical", style_mods = {padding= 12, top_padding = 8, vertical_spacing = 10}, children = {
                            {type = "frame", style = "deep_frame_in_shallow_frame", children = {
                                {type = "scroll-pane", style = "at_slot_table_scroll_pane", name = "config_rows", save_as = "main.config_rows",
                                    style_mods = {
                                        width = width,
                                    },
                                    children = {
                                        gui.templates.slot_table.main(btns, pdata),
                                    }
                                }
                            }},
                            {type = "frame", style = "bordered_frame", style_mods = {right_padding = 8, horizontally_stretchable = "on"}, children = {
                                {type = "flow", direction = "vertical", children = {
                                    {type = "table", save_as = "main.sliders.table", style_mods = {height = 60}, column_count = 2, children = {
                                        {type = "flow", direction = "horizontal", children = {
                                            {type = "label", caption = {"auto-trash-request"}}
                                        }},
                                        {type ="flow", style = "at_slider_flow", direction = "horizontal", children = {
                                            {type = "slider", save_as = "main.sliders.request", handlers = "sliders.request", minimum_value = 0, maximum_value = 42},
                                            {type = "textfield", save_as = "main.sliders.request_text", handlers = "sliders.request", style = "slider_value_textfield"},
                                            --{type = "sprite-button", style = "tool_button", style_mods = {top_margin = 2}, sprite = "utility/export_slot"}
                                        }},
                                        {type = "flow", direction = "horizontal", children = {
                                            {type = "label", caption={"auto-trash-trash"}},
                                        }},
                                        {type ="flow", style = "at_slider_flow", direction = "horizontal", children = {
                                            {type = "slider", save_as = "main.sliders.trash", handlers = "sliders.trash", minimum_value = 0, maximum_value = 42},
                                            {type = "textfield", save_as = "main.sliders.trash_text", handlers = "sliders.trash", style = "slider_value_textfield"},
                                            --{type = "sprite-button", style = "tool_button", style_mods = {top_margin = 2}, sprite = "utility/export_slot"}
                                        }},
                                    }},
                                    {type = "drop-down", style = "at_quick_actions", handlers = "quick_actions",
                                        items = constants.quick_actions,
                                        selected_index = 1,
                                        tooltip = {"autotrash_quick_actions_tt"}
                                    },
                                    {template = "pushers.horizontal"}
                                }}
                            }},
                            at_gui.templates.settings(flags, pdata),
                        }},

                    }},
                    {type = "frame", style = "inside_shallow_frame", direction = "vertical", children = {
                        {type = "frame", style = "subheader_frame", children={
                            {type = "label", style = "subheader_caption_label", caption = "Presets"},
                            {template = "pushers.horizontal"},
                            {type = "sprite-button", style = "tool_button", handlers = "main.export_all", sprite = "utility/export_slot", tooltip = {"autotrash_export_tt_all"}},
                            {type = "sprite-button", style = "tool_button", handlers = "main.import_all", sprite = "mi_import_string", tooltip = {"autotrash_import_tt_all"}},
                        }},
                        {type = "flow", direction="vertical", style_mods = {maximal_width = 274, padding= 12, top_padding = 8, vertical_spacing = 12}, children = {
                            {type = "flow", children = {
                                {type = "textfield", style = "at_save_as_textfield", save_as = "main.preset_textfield", handlers = "presets.textfield", text = ""},
                                {template = "pushers.horizontal"},
                                {type = "button", caption = {"gui-save-game.save"}, style = "at_save_button", handlers = "presets.save"}
                            }},
                            {type = "frame", style = "deep_frame_in_shallow_frame", children = {
                                {type = "scroll-pane", style_mods = {extra_top_padding_when_activated = 0, extra_left_padding_when_activated = 0, extra_right_padding_when_activated = 0}, children = {
                                    {type = "flow", direction = "vertical", save_as = "main.presets_flow", style_mods = {vertically_stretchable = "on", left_padding = 8, top_padding = 8, width = 230}, children =
                                        gui.templates.presets(pdata),
                                    },
                                }}
                            }},
                        }}
                    }}
                }}
            }},
        }
    }})
    gui_data.main.titlebar.flow.drag_target = gui_data.main.window
    gui_data.main.window.force_auto_center()
    gui_data.main.window.visible = false
    pdata.gui.main = gui_data.main
    pdata.selected = false
end

function at_gui.create_import_window(player, pdata, bp_string, mode)
    if pdata.gui.import and pdata.gui.import.window and pdata.gui.import.window.main.valid then
        local window = pdata.gui.import.window.main
        gui.update_filters("import", player.index, nil, "remove")
        window.destroy()
        pdata.gui.import = nil
    end
    pdata.gui.import = gui.build(player.gui.screen, {gui.templates.import_export_window(bp_string, mode)}, pdata.gui)
    local import_window = pdata.gui.import.window
    import_window.titlebar.drag_target = pdata.gui.import.window.main
    import_window.main.force_auto_center()
    local textbox = import_window.textbox
    if bp_string then
        textbox.read_only = true
    end
    textbox.select_all()
    textbox.focus()
end


function at_gui.init(player, pdata)
    at_gui.destroy(player, pdata)
    at_gui.create_main_window(player, pdata)
    local status_flow = pdata.gui.status_flow
    local visible = player.force.character_logistic_requests
    if status_flow and status_flow then
        status_flow.clear()
    else
        status_flow = mod_gui.get_frame_flow(player).autotrash_status_flow
        if status_flow and status_flow.valid then
            pdata.gui.status_flow = status_flow
            status_flow.clear()
        else
            pdata.gui.status_flow = mod_gui.get_frame_flow(player).add{type = "flow", name = "autotrash_status_flow", direction = "vertical"}
        end
    end
    pdata.gui.status_flow.visible = visible

    local main_button_flow = pdata.gui.mod_gui.flow
    if main_button_flow and main_button_flow.valid then
        main_button_flow.clear()
    else
        pdata.gui.mod_gui.flow = mod_gui.get_button_flow(player).add{type = "flow", direction = "horizontal", name =  "autotrash_main_flow", style = "at_main_flow"}
    end
    pdata.gui.mod_gui.button = pdata.gui.mod_gui.flow.add{type = "sprite-button", name = "at_config_button", style = "at_sprite_button", sprite = "autotrash_trash"}
    gui.update_filters("mod_gui_button", player.index, {pdata.gui.mod_gui.button.index}, "add")
    pdata.gui.mod_gui.flow.visible = visible
end

at_gui.init_status_display = function(player, pdata)
    local status_table = pdata.gui.status_table
    if status_table and status_table.valid then
        status_table.destroy()
        pdata.gui.status_table = nil
    end

    status_table = pdata.gui.status_flow.add{
        type = "table",
        style = "at_request_status_table",
        column_count = pdata.settings.status_columns
    }
    pdata.gui.status_table = status_table

    for _ = 1, pdata.settings.status_count do
        status_table.add{
            type = "sprite-button",
            visible = false
        }
    end
    at_gui.update_status_display(player, pdata)
end

at_gui.update_status_display_cached = function(pdata, cache)
    local status_table = pdata.gui.status_table
    local max_count = pdata.settings.status_count
    local children = status_table.children
    local c = 1
    for name, data in pairs(cache) do
        if c > max_count then return true end
            local style = data[1]
            if style ~= "at_button_slot" then
                local button = children[c]
                button.style = style
                button.sprite = "item/" .. name
                button.number = data[2]
                button.visible = true
                c = c + 1
            end
    end
    for i = c, max_count do
        children[i].visible = false
    end
    return true
end

at_gui.update_status_display = function(player, pdata, cache)
    if cache then return at_gui.update_status_display_cached(pdata, cache) end
    local status_table = pdata.gui.status_table
    local available, on_the_way, item_count, cursor_stack, armor, gun, ammo = get_network_data(player)
    if not (available and not pdata.flags.pause_requests) then
        for _, child in pairs(status_table.children) do
            child.visible = false
        end
        return true
    end

    local max_count = pdata.settings.status_count
    local get_request_slot = player.character.get_request_slot

    local children = status_table.children
    local c = 1
    for i = 1, player.character_logistic_slot_count do
        local item = get_request_slot(i)
        if item and item.count > 0 then
            if c > max_count then return true end
            item.request = item.count
            if item.request > 0 then
                local style, diff = at_gui.get_button_style(i, false, item, available, on_the_way, item_count, cursor_stack, armor, gun, ammo)
                if style ~= "at_button_slot" then
                    local button = children[c]
                    button.style = style
                    button.sprite = "item/" .. item.name
                    button.number = diff
                    button.visible = true
                    c = c + 1
                end
            end
        end
    end
    for i = c, max_count do
        children[i].visible = false
    end
    return true
end

function at_gui.update_main_button(pdata)
    local mainButton = pdata.gui.mod_gui.button
    if not (mainButton and mainButton.valid) then
        return
    end
    local flags = pdata.flags
    if flags.pause_trash and not flags.pause_requests then
        mainButton.sprite = "autotrash_trash_paused"
    elseif flags.pause_requests and not flags.pause_trash then
        mainButton.sprite = "autotrash_requests_paused"
    elseif flags.pause_trash and flags.pause_requests then
        mainButton.sprite = "autotrash_both_paused"
    else
        mainButton.sprite = "autotrash_trash"
    end
    at_gui.update_settings(pdata)
end

function at_gui.update_settings(pdata)
    if not pdata.flags.gui_open then return end
    local frame = pdata.gui.main.trash_options
    if not (frame and frame.valid) then return end
    local flags = pdata.flags
    local def = at_gui.defines

    frame[def.trash_unrequested].state = flags.trash_unrequested
    frame[def.trash_above_requested].state = flags.trash_above_requested
    frame[def.trash_network].state = flags.trash_network
    frame[def.pause_trash].state = flags.pause_trash
    frame[def.pause_requests].state = flags.pause_requests
    frame[def.network_button].caption = pdata.main_network and {"auto-trash-unset-main-network"} or {"auto-trash-set-main-network"}
end

function at_gui.mark_dirty(pdata, keep_presets)
    local reset = pdata.gui.main.reset_button
    reset.enabled = true
    pdata.flags.dirty = true
    if not keep_presets then
        pdata.selected_presets = {}
    end
    at_gui.update_presets(pdata)
end

function at_gui.destroy(player, pdata)
    local player_index = player.index
    if pdata.gui.main and pdata.gui.main.window and pdata.gui.main.window.valid then
        gui.update_filters("main", player_index, nil, "remove")
        pdata.gui.main.window.destroy()
        pdata.gui.main = nil
        pdata.flags.gui_open = false
    end
    if pdata.gui.import and pdata.gui.import.window then
        if pdata.gui.import.window.main then
            pdata.gui.import.window.main.destroy()
        end
        pdata.gui.import = nil
    end
end

function at_gui.open(player, pdata)
    local window_frame = pdata.gui.main.window
    if window_frame and window_frame.valid then
        window_frame.visible = true
        pdata.flags.gui_open = true
        at_gui.update_button_styles(player, pdata)
        at_gui.update_settings(pdata)
        at_gui.update_sliders(pdata)
        at_gui.update_presets(pdata)
    end
    --player.opened = pdata.gui.window
end

function at_gui.close(pdata, no_reset)
    local window_frame = pdata.gui.main.window
    if window_frame and window_frame.valid then
        window_frame.visible = false
        pdata.flags.gui_open = false
        if not no_reset and pdata.settings.reset_on_close then
            pdata.config_tmp = table.deep_copy(pdata.config_new)
            pdata.gui.main.reset_button.enabled = false
            pdata.dirty = false
        end
    end
    --player.opened = nil
end

function at_gui.toggle(player, pdata)
    if pdata.flags.gui_open then
        at_gui.close(pdata)
    else
        at_gui.open(player, pdata)
    end
end
return at_gui