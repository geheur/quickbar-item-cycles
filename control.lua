-- TODO add requirement for space exploration mod.

local function print(...)
	local result = ""
	for i,v in pairs{...} do
		result = result.." "..tostring(v)
	end
	game.print(result)
end

local function initialize_global_variables()
	local function initialize_variable(name, default_value)
		global[name] = global[name] or default_value
	end
	initialize_variable("default_quickbar_state", {})
	initialize_variable("last_stack", {})
	initialize_variable("last_cycle", {})
	initialize_variable("space_quickbar", {})
	initialize_variable("solid_quickbar", {})
end

local cycles = {
	{"transport-belt", "fast-transport-belt", "express-transport-belt"},
	{"underground-belt", "fast-underground-belt", "express-underground-belt"},
	{"splitter", "fast-splitter", "express-splitter"},
	{"inserter", "fast-inserter", "stack-inserter", "filter-inserter", "stack-filter-inserter"},
	{"assembling-machine-3", "assembling-machine-2", "chemical-plant"},
	{"small-electric-pole", "medium-electric-pole"},
	{"big-electric-pole", "substation"},
	{"pipe", "pump", "storage-tank"},
	{"pipe-to-ground", "offshore-pump"},
	{"long-handed-inserter", "steel-chest", "logistic-chest-storage"},
}

local function replace_on_quick_bar(replacee, replacement)
	--print("swapping", replacee, replacement)
	local player = game.get_player(1)
	for i=1,100 do
		local slot = player.get_quick_bar_slot(i)
		if slot and slot.name == replacee then
			player.set_quick_bar_slot(i, game.item_prototypes[replacement])
			global.default_quickbar_state[i] = global.default_quickbar_state[i] or replacee
		end
	end

	-- Unselect the quickbar slot. Otherwise the next press of the quickbar slot will just unselect the item instead of selecting the new item.
	player.clear_cursor()
	local stack = player.get_main_inventory().find_item_stack(replacee)
	if stack then
		local result = player.cursor_stack.swap_stack(stack)
		player.hand_location = {inventory = defines.inventory.item_main, slot = select(2, player.get_main_inventory().find_empty_stack())}
		--print("swapped stack", result)
	else
		player.cursor_ghost = game.item_prototypes[replacee]
	end
end

local function reset_quick_bar()
	for i,v in pairs(global.default_quickbar_state) do
		game.get_player(1).set_quick_bar_slot(i, game.item_prototypes[v])
	end
	global.default_quickbar_state = {}
end

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
	local stack = game.get_player(1).cursor_stack
	local ghost = game.get_player(1).cursor_ghost
	local name = stack.valid_for_read and stack.prototype.name or ghost and ghost.name or nil
	--print("=== cursor stack changed: ", global.last_stack and global.last_stack or "nil", "->", name and name or "empty")

	if not name then -- cursor cleared
		reset_quick_bar()
		global.last_stack = nil
		return
	end

	if name == global.last_stack then return end -- ignore quantity changes
	global.last_stack = name

	for cycle_index,cycle in ipairs(cycles) do
		for i,item in ipairs(cycle) do
			if item == name then
				if cycle_index ~= global.last_cycle then
					reset_quick_bar()
				end
				global.last_cycle = cycle_index
				local next_item = i == #cycle and cycle[1] or cycle[i + 1]
				--print("swapping", next_item)
				replace_on_quick_bar(name, next_item)
				return
			end
		end
	end
end)

local function swap_quickbars(player, quickbar_read, quickbar_write)
	reset_quick_bar()
	for index=1,100 do
		local slot = quickbar_read[index]
		quickbar_write[index] = player.get_quick_bar_slot(index)
		if slot then
			player.set_quick_bar_slot(index, slot)
		end
	end
end

script.on_event(defines.events.on_player_changed_surface, function(event)
	local player = game.get_player(event.player_index)
	local previous_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = event.surface_index})
	local new_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = player.surface.index})
	local was_in_space = is_space(previous_zone)
	local in_space = is_space(new_zone)
	print("changing surface "..previous_zone.name.." ("..(was_in_space and "space" or "not space")..") -> "..new_zone.name.." ("..(in_space and "space" or "not space")..")")
	if --[[entering space]] in_space and not was_in_space then
		swap_quickbars(player, global.space_quickbar, global.solid_quickbar)
	elseif --[[leaving space]] not in_space and was_in_space then
		swap_quickbars(player, global.solid_quickbar, global.space_quickbar)
	end
end)

-- From space-exploration "zone.lua".
function is_solid(zone)
  return zone.type == "planet" or zone.type == "moon"
end

function is_space(zone)
  return not is_solid(zone)
end

local s = ""
script.on_init(function(event)
	s = s.."init "
	initialize_global_variables()
end)
script.on_load(function(event)
	s = s.."load "
end)
script.on_configuration_changed(function(event)
	s = s.."conf "
	initialize_global_variables()
end)

--[[
	/c game.print(game.get_player(1).name)
	/c for name,interface in pairs(remote.interfaces) do if name == "space-exploration" then local s = "" for name,a in pairs(interface) do s = s .. name .. ", " end game.print(s) end end
	/c game.print(remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = game.player.surface.index}).type)
	/c game.print(remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = game.player.surface.index}).name)
	/c local stack = game.get_player(1).get_main_inventory().find_item_stack("fast-inserter") game.print(stack)
--]]
--[[
Is is possible to make a quickbar slot give you an upgraded version of the item when you press its key a second time? e.g. I press "3" for fast inserter, then I press it again and it gives me a stack inserter.
So far I have tried changing the quickbar slot when `on_player_cursor_stack_changed`. The quickbar slot's item changed, but it was still selected, so the next press of that quick bar slot's keybind just unselected the item rather than selecting the upgraded item. I don't think this would work for me because not only would I have to press the key a third time to select that slot, but I wouldn't be able to have the slot reset back to the original thing when I clear the cursor (e.g. with "q"), because I couldn't distinguish the cursor being cleared vs it being pressed again for the upgraded item.
I then tried clearing the stack with player.clear_cursor() in order to clear the quickbar slot's selected state, but I couldn't figure out how to re-select the item again after. `player.cursor_stack.set_stack(player.get_main_inventory().find_item_stack(item_name))` puts an item in my cursor but it's not from my inventory, it's spawned in a new item that didn't exist previously.
--]]

-- Copied from space-exploration/collision-mask-util-extended/control/collision-mask-util-control.lua
-- I found collision mask names in control.lua
function get_named_collision_mask(mask_name)
  local prototype = game.entity_prototypes["collision-mask-"..mask_name]
  if prototype then
    local layer
    for mask_name, collides in pairs(prototype.collision_mask) do
      if layer then
        -- error("\n\n\nA reserved collision mask object "..mask_name.." has been compromised by 1 or more of your installed mods. Object must have only 1 collision mask.\n\n")
      else
        layer = mask_name
      end
    end
    if not layer then
      -- error("\n\n\nA reserved collision mask object "..mask_name.." has been compromised by 1 or more of your installed mods. Object is missing collision_mask.\n\n")
    end
    return layer
  else
    -- error("\n\n\nA reserved collision mask object "..mask_name.." has been removed.\n\n")
  end
end

commands.add_command("a", nil, function(command)
	print("s", s)
	--print("/a ran")
	--print("space-tile", get_named_collision_mask("space-tile"))
	--print("empty-space-tile", get_named_collision_mask("empty-space-tile"))
end)

script.on_event(defines.events.on_tick, function(event)
	initialize_global_variables()
end)

--[[
script.on_event(defines.events.on_player_dropped_item,
	function(event)
		print("built tile")
		for i=1,41 do
			local slot = game.get_player(event.player_index).get_quick_bar_slot(i)
			if i == 41 then
				print(i, slot, slot.name, slot.place_result, slot.place_as_tile_result)
			end
			if (slot and slot.name and slot.place_result) then
				print(i, slot.name, slot.place_result.name, slot.place_result.collision_mask, table.unpack(slot.place_result.collision_mask))
				local bla = {}
				for i,_ in pairs(slot.place_result.collision_mask) do
					bla[#bla + 1] = i
				end
				print(table.unpack(bla))
			end
		end
	end
)
--]]
