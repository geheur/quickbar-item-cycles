local function print(...)
	local args = table.pack(...)
	for i=1,args.n do
		args[i] = tostring(args[i])
	end
	game.print(table.concat(args, " "))
end

local function initialize_global_variables()
	local function initialize_variable(name, default_value)
		global[name] = global[name] or default_value
	end
	initialize_variable("players", {})
end

local default_cycles = {
	{"transport-belt", "fast-transport-belt", "express-transport-belt"},
	{"underground-belt", "fast-underground-belt", "express-underground-belt"},
	{"splitter", "fast-splitter", "express-splitter"},
	{"inserter", "fast-inserter", "stack-inserter", "filter-inserter", "stack-filter-inserter"},
}

local function get_player_data(player_index)
	local player_data = global.players[player_index]
	if not player_data then
		player_data = {
			elements = {},
			default_quickbar_state = {},
			space_quickbar = {},
			solid_quickbar = {},
			cycles = default_cycles,
			player = game.get_player(player_index),
		}
		global.players[player_index] = player_data
	end
	return player_data
end

local function replace_on_quick_bar(player_data, replacee, replacement)
	--print("swapping", replacee, replacement)
	local found = false
	local player = player_data.player
	for i=1,100 do
		local slot = player.get_quick_bar_slot(i)
		if slot and slot.name == replacee then
			found = true
			player.set_quick_bar_slot(i, game.item_prototypes[replacement])
			player_data.default_quickbar_state[i] = player_data.default_quickbar_state[i] or replacee
		end
	end

	if not found then return end

	-- Unselect the quickbar slot. Otherwise the next press of the quickbar slot will just unselect the item instead of selecting the new item.
	if player.hand_location then
		local hand_slot = player.hand_location.slot -- store this value as clear_cursor will change it
		-- this actually unselects the quickbar slot.
		player.clear_cursor()

		-- re-pick-up the item
		local hand_stack = player.get_main_inventory()[hand_slot]
		player.cursor_stack.swap_stack(hand_stack)
		player.hand_location = {inventory = defines.inventory.item_main, slot = hand_slot}
	elseif player.cursor_ghost then
		player.clear_cursor()
		player.cursor_ghost = game.item_prototypes[replacee]
	end
end

local function reset_quick_bar(player_data)
	for i,v in pairs(player_data.default_quickbar_state) do
		player_data.player.set_quick_bar_slot(i, game.item_prototypes[v])
	end
	player_data.default_quickbar_state = {}
	player_data.last_stack = nil
	player_data.last_cycle = nil
end


script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
	local player = game.get_player(event.player_index)
	local player_data = get_player_data(event.player_index)
	local stack = player.cursor_stack
	local ghost = player.cursor_ghost
	local name = stack.valid_for_read and stack.prototype.name or ghost and ghost.name or nil
	--print("=== cursor stack changed: ", player_data.last_stack and player_data.last_stack or "nil", "->", name and name or "empty")

	if not name then -- cursor cleared
		reset_quick_bar(player_data)
		return
	end

	if name == player_data.last_stack then return end -- ignore quantity changes
	player_data.last_stack = name

	-- Try the current cycle first if it exists. This makes a difference when multiple cycles contain the same item. The current cycle should have priority. Example use case: in space exploration, I like to have "pipe -> pump -> tank" but also "space pipe -> pump -> tank".
	if player_data.last_cycle then
		local cycle = player_data.cycles[player_data.last_cycle]
		for i,item in ipairs(cycle) do
			if item == name then
				local next_item = i == #cycle and cycle[1] or cycle[i + 1]
				replace_on_quick_bar(player_data, name, next_item)
				return
			end
		end
	end

	for cycle_index,cycle in ipairs(player_data.cycles) do
		if #cycle <= 1 then goto continue end
		for i,item in ipairs(cycle) do
			if item == name then
				if cycle_index ~= player_data.last_cycle then
					reset_quick_bar(player_data)
					player_data.last_cycle = cycle_index
				end
				local next_item = i == #cycle and cycle[1] or cycle[i + 1]
				--print("swapping", next_item)
				replace_on_quick_bar(player_data, name, next_item)
				return
			end
		end
		::continue::
	end
end)

-- local s = ""
script.on_init(function(event)
	-- s = s.."init "
	initialize_global_variables()
end)
--[[
script.on_load(function(event)
	s = s.."load "
end)
--]]
script.on_configuration_changed(function(event)
	-- s = s.."conf "
	initialize_global_variables()
end)

local function rebuildGui(player_data)
	local elements = player_data.elements

	elements.cycles_scroll_pane.clear()

	local cycles = player_data.cycles
	for cycle_index,cycle in ipairs(cycles) do
		local cycle_flow = elements.cycles_scroll_pane.add{type="flow", name="cycle_flow"..cycle_index, direction="horizontal"}
		for item_index,item in ipairs(cycle) do
			local chooser = cycle_flow.add{type="choose-elem-button", name=item_index, elem_type="item", tags={quickbar_cycles_cycle_index=cycle_index, quickbar_cycles_item_index=item_index}}
			chooser.elem_value=item
		end
		cycle_flow.add{type="choose-elem-button", name="new_item", elem_type="item", tags={quickbar_cycles_cycle_index=cycle_index, quickbar_cycles_item_index=#cycle + 1}}
	end
	local new_cycle_flow = elements.cycles_scroll_pane.add{type="flow", name="new_cycle_flow", direction="horizontal"}
	new_cycle_flow.add{type="choose-elem-button", name="new_item", elem_type="item", tags={quickbar_cycles_cycle_index=#cycles + 1, quickbar_cycles_item_index=1}}
	-- TODO warn for single item cycles
end

-- https://forums.factorio.com/viewtopic.php?t=98713
function add_titlebar(gui, caption, close_button_name)
  local titlebar = gui.add{type = "flow"}
  titlebar.drag_target = gui
  titlebar.add{
    type = "label",
    style = "frame_title",
    caption = caption,
    ignored_by_interaction = true,
  }
  local filler = titlebar.add{
    type = "empty-widget",
    style = "draggable_space",
    ignored_by_interaction = true,
  }
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  titlebar.add{
    type = "sprite-button",
    name = close_button_name,
    style = "frame_action_button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = {"gui.close-instruction"},
  }
end

local function openGui(player_index)
	local player_data = get_player_data(player_index)
	local elements = player_data.elements
	if elements.main_frame and elements.main_frame.valid then
		elements.main_frame.destroy()
		player_data.elements = {}
		return
	end

	local player = game.get_player(player_index)
	local frame = player.gui.screen.add{type="frame", name="quickbar_cycles_configuration_frame", direction="vertical"}
	elements.main_frame = frame
	frame.style.size = {1385, 465}
	frame.auto_center = true
	player.opened = frame
	add_titlebar(frame, "Quickbar Item Cycles", "my-mod-x-button")

	-- local content_frame = frame.add{type="frame", name="content_frame", direction="vertical", --[[style="ugg_content_frame"]]}

	elements.cycles_scroll_pane = frame.add{type="scroll-pane", name="cycles_scroll_pane", horizontal_scroll_policy="never", direction="vertical", --[[style="ugg_controls_flow"]]}
	elements.cycles_scroll_pane.style.horizontally_stretchable = true

	rebuildGui(player_data)
end

script.on_event(defines.events.on_gui_click, function(event)
  if event.element.name == "my-mod-x-button" then
    event.element.parent.parent.destroy()
  end
end)
script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid and event.element.name == "quickbar_cycles_configuration_frame" then
    event.element.destroy()
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
	if not event.element.tags.quickbar_cycles_cycle_index then return end

	local cycle_index, item_index = event.element.tags.quickbar_cycles_cycle_index, event.element.tags.quickbar_cycles_item_index
	local new_value = event.element.elem_value
	local player_data = get_player_data(event.player_index)
	local cycles = player_data.cycles

	if not new_value and (cycle_index > #cycles or item_index > #cycles[cycle_index]) then -- user right-clicked on an already empty choose-elem-button
		-- print("that button is already empty, dummy!")
		return
	end

	-- print("cycle", cycle_index, "item", item_index, "from", cycles[cycle_index] and cycles[cycle_index][item_index] or "new cycle", "to", new_value)

	-- Do not allow two cycles to have the same first item.
	if item_index == 1 then
		local new_first_item = new_value or cycles[cycle_index][2]
		for i,cycle in ipairs(cycles) do
			if i ~= cycle_index and cycle[item_index] == new_first_item then
				print(new_value and "cannot have same item as the start of multiple cycles." or "removing this item would result in two cycles with the same first item, which is not allowed.")
				rebuildGui(player_data)
				return
			end
		end
	end

	-- Do not allow the same item twice in the same cycle.
	if new_value and cycle_index <= #cycles then
		for i,item in ipairs(cycles[cycle_index]) do
			if item == new_value then
				print("cannot have the same item twice in the same cycle.")
				rebuildGui(player_data)
				return
			end
		end
	end

	if new_value then
		cycles[cycle_index] = cycles[cycle_index] or {}
		cycles[cycle_index][item_index] = new_value
	else
		table.remove(cycles[cycle_index], item_index)
		if #cycles[cycle_index] == 0 then
			table.remove(cycles, cycle_index)
		end
	end

	if player_data.last_cycle == cycle_index then reset_quick_bar(player_data) end

	rebuildGui(player_data)
end)

--[[
commands.add_command("reset", nil, function(event)
	print("resetting")
	for i,player_data in pairs(global.players) do
		player_data.cycles = default_cycles
	end
end)
--]]

commands.add_command("qic", nil, function(event)
	openGui(event.player_index)
end)

local function swap_quickbars(player, quickbar_read, quickbar_write)
	for index=1,100 do
		local slot = quickbar_read[index]
		quickbar_write[index] = player.get_quick_bar_slot(index)
		if slot then
			player.set_quick_bar_slot(index, slot)
		end
	end
end

script.on_event(defines.events.on_player_changed_surface, function(event)
	if not settings.get_player_settings(event.player_index)["space-exploration-space-bar-swap"].value then
		return
	end

	local player = game.get_player(event.player_index)
	local previous_zone_type = remote.call("space-exploration", "get_surface_type", {surface_index = event.surface_index})
	local new_zone_type = remote.call("space-exploration", "get_surface_type", {surface_index = player.surface.index})
	local was_in_space = is_space(previous_zone_type)
	local in_space = is_space(new_zone_type)
	-- if previous_zone and new_zone then print("changing surface "..previous_zone.name.." ("..(was_in_space and "space" or "not space")..") -> "..new_zone.name.." ("..(in_space and "space" or "not space")..")") end
	
	if in_space ~= was_in_space then
		local player_data = get_player_data(event.player_index)
		reset_quick_bar(player_data) -- make sure you're saving the base state when you call swap_quickbars.

		if in_space then -- entering space
			swap_quickbars(player, player_data.space_quickbar, player_data.solid_quickbar)
		else -- leaving space
			swap_quickbars(player, player_data.solid_quickbar, player_data.space_quickbar)
		end
	end
end)

-- Based off of space-exploration "zone.lua".
function is_solid(zone_type)
  return not zone_type or zone_type == "planet" or zone_type == "moon"
end

function is_space(zone_type)
  return not is_solid(zone_type)
end
