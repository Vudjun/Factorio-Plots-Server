require "util"
require "defines"

local MOV_UPDATE_FREQ = 20 -- Ticks per player update, 3 updates per second is fine.
local CHUNK_SIZE = 32 -- Size of a chunk in tiles
local PLOT_SIZE = 5 -- Chunks in a plot
local ROAD_WIDTH = 10 -- Road width in tiles
local PLOT_SIZE_IN_TILES = PLOT_SIZE * CHUNK_SIZE
local ROAD_HWIDTH = ROAD_WIDTH / 2

local TICKS_PER_HOUR = 216000 -- 60*60*60
local COST_PER_HOUR = 5 -- Cost to rent a plot for an hour
local COST_PER_DAY = COST_PER_HOUR * 24 -- 120
local MINIMUM_RENT_DURATION = 48 -- Minimum initial rent duration in hours

local PRESERVE_TILES = { -- tiles that should never be modified
	"deepwater",
	"deepwater-green",
	"out-of-map",
	"water",
	"water-green",
	"stone-path"
}

local CLAIMED_TILES = { -- tiles that are used to indicate a claimed plot
	"concrete",
	"dirt",
	"dirt-dark",
	"grass-dry",
	"grass-medium",
	"sand",
	"sand-dark"
}

local UNCLAIMED_TILE = "grass" -- tile indicating an unclaimed plot
local ROAD_TILE = "stone-path" -- tile used for the road

function stringSplit(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={} ; i=1
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end

function isIn(list, item)
	for _, x in pairs(list) do
		if x == item then return true end
	end
	return false
end

function tableAppend(a, b)
	for _, x in pairs(b) do
		table.insert(a, x)
	end
end

function announce(message)
	for _,player in pairs(game.players) do
		player.print(message)
	end
end

function getPlotID(x, y)
	local yName = ""
	local xName = ""
	if y < 0 then
		yName = "N".. math.abs(y)
	else
		yName = "S".. math.abs(y + 1)
	end
	if x < 0 then
		xName = "W".. math.abs(x)
	else
		xName = "E".. math.abs(x + 1)
	end
	return yName.. xName
end

function announceObject(object, depth)
	if type(object) == "table" then
		for i,v in pairs(object) do
			if type(v) == "table" then
				announce(string.rep("  ", depth).. i.. ": (table)")
				announceObject(v, depth + 1)
			elseif type(v) == "userdata" then
				announce(string.rep("  ", depth).. i.. ": (userdata)")
			else
				announce(string.rep("  ", depth).. i.. ": ".. tostring(v))
			end
		end
	else
		announce("Cannot display: ".. type(object))
	end
end

function createGUI(player)
	local plotui = player.gui.top.add({type="flow", name="plots", direction="vertical"})
	plotui.add({type="label", name="plotDisplay", caption="Plot Display", style="caption_label_style"})
	plotui.add({type="button", caption="Manage", name="managePlots"})
	-- plotui.add({type="button", caption="Test", name="test"})
end

function updateGUI(player, plotID)
	local plot = global.plots.plots[plotID]
	if plot == nil then return end
	local caption = nil
	if plot.owner ~= nil then
		local forceData = global.plots.forces[plot.owner]
		caption = "In Plot: ".. plotID.. " (owner: ".. forceData.name.. ")"
	else
		caption = "In Plot: ".. plotID.. " (not owned)"
	end
	player.gui.top.plots.plotDisplay.caption = caption
	local mGui = player.gui.center.plotManage
	if mGui ~= nil then
		updateManagePlots(player, mGui)
		--mGui.destroy()
		--showManagePlots(player)
	end
end

function updateManagePlots(player, mGui)
	local playerData = global.plots.players[player.index]
	local plotData = global.plots.plots[playerData.location]
	mGui.flow.currentPlot.plotDisplay.caption = "Plot: ".. playerData.location
	local myPlots = mGui.flow.myPlots
	local plotHolder = myPlots.plotHolder
	for plotID, plotData in pairs(global.plots.plots) do
		if plotData.owner == player.force.name then
			if plotHolder[plotID] == nil then
				local plotGUI = plotHolder.add({type="flow", name=plotID, direction="horizontal"})
				plotGUI.add({type="label", name="info", caption="INFO", style="caption_label_style"})
				plotGUI.add({type="button", caption="+1", name="addTime-1-".. plotID})
				plotGUI.add({type="button", caption="+12", name="addTime-12-".. plotID})
				plotGUI.add({type="button", caption="+24", name="addTime-24-".. plotID})
				plotGUI.add({type="button", caption="+72", name="addTime-72-".. plotID})
			end
			local timeLeft = math.floor((plotData.expires - game.tick) / TICKS_PER_HOUR)
			plotHolder[plotID].info.caption = plotID.. " - Rented for ".. timeLeft.. " hours"
		elseif plotHolder[plotID] ~= nil then
			plotHolder[plotID].destroy()
		end
	end
end

function showManagePlots(player)
	if player.gui.center.plotManage ~= nil then
		player.gui.center.plotManage.destroy()
		return
	end
	local tile = global.plots.forces[player.force.name].tile
	local mGui = player.gui.center.add({type = "frame", caption = "Manage Plots", name = "plotManage", direction = "vertical"})
	local flow = mGui.add({type="flow", name="flow", direction="horizontal"})
	local currentPlot = flow.add({type="flow", name="currentPlot", direction="vertical"})
	currentPlot.add({type="label", name="plotDisplay", caption="Plot Display", style="caption_label_style"})
	currentPlot.add({type="button", caption="Claim This Plot", name="claimPlot"})
	currentPlot.add({type="label", name="yourTile", caption="Your Plot Tile: ".. tile, style="caption_label_style"})
	local myPlots = flow.add({type="flow", name="myPlots", direction="vertical"})
	myPlots.add({type="label", name="title", caption="My Plots", style="caption_label_style"})
	local plotHolder = myPlots.add({type="flow", name="plotHolder", direction="vertical"})
	updateManagePlots(player, mGui)
end

function newPlayerForce(name)
	local force = game.create_force("PF_".. tostring(global.plots.nextPlayerForce))
	for _, exForce in pairs(game.forces) do
		force.set_cease_fire(exForce.name, true)
	end
	local forceData = {}
	forceData.id = force.name
	forceData.name = name
	forceData.tile = CLAIMED_TILES[(global.plots.nextPlayerForce % #CLAIMED_TILES) + 1]
	global.plots.forces[force.name] = forceData
	global.plots.nextPlayerForce = global.plots.nextPlayerForce + 1
	return force
end

function removeEntities(surface, aabb)
	local entities = surface.find_entities(aabb)
	for _, entity in pairs(entities) do
		if entity.type ~= "player" then
			entity.destroy()
		end
	end
end

function initChunkEntities(surface, area)
	local entities = surface.find_entities(area)
	for _, entity in pairs(entities) do
		if entity.force.name == "enemy" then
			entity.destroy()
		elseif entity.type ~= "player" then
			entity.destructible = false
			-- entity.minable = false
			-- entity.rotatable = false
			-- entity.operable = false
		end
	end
end

function preparePlot(surface, x, y)
	local plotID = getPlotID(x, y)
	local plot = global.plots.plots[plotID]
	if plot == nil then
		plot = {}
		plot.x = x
		plot.y = y
		plot.owner = nil
		plot.id = plotID
		plot.surface = surface.name
		global.plots.plots[plotID] = plot
	end
	return plot
end

function prepareChunk(surface, area)
	local x = area.left_top.x / CHUNK_SIZE
	local y = area.left_top.y / CHUNK_SIZE
	local plotX = math.floor(x / PLOT_SIZE)
	local plotY = math.floor(y / PLOT_SIZE)
	local left = (x * CHUNK_SIZE)
	local up = (y * CHUNK_SIZE)
	local right = left + CHUNK_SIZE
	local down = up + CHUNK_SIZE
	local tileUpdate = {}
	local defaultTile = UNCLAIMED_TILE
	local plot = preparePlot(surface, plotX, plotY)
	if plot.owner ~= nil then
		defaultTile = global.plots.forces[plot.owner].tile
	end
	local isRoadXa = x % PLOT_SIZE == 0
	local isRoadYa = y % PLOT_SIZE == 0
	local isRoadXb = x % PLOT_SIZE == PLOT_SIZE - 1
	local isRoadYb = y % PLOT_SIZE == PLOT_SIZE - 1
	local isRoad = isRoadXa or isRoadXb or isRoadYa or isRoadYb
	local isBlank = true
	for tx = left, right, 1 do
		for ty = up, down, 1 do
			local tile = surface.get_tile(tx, ty)
			if tile.name ~= "out-of-map" then
				isBlank = false
				local tileType = defaultTile
				local doClear = false
				if isRoadXa and tx < left + ROAD_HWIDTH then
					tileType = ROAD_TILE
					doClear = true
				end
				if isRoadXb and tx >= left + CHUNK_SIZE - ROAD_HWIDTH then
					tileType = ROAD_TILE
					doClear = true
				end
				if isRoadYa and ty < up + ROAD_HWIDTH then
					tileType = ROAD_TILE
					doClear = true
				end
				if isRoadYb and ty >= up + CHUNK_SIZE - ROAD_HWIDTH then
					tileType = ROAD_TILE
					doClear = true
				end
				if doClear or not isIn(PRESERVE_TILES, tile.name) then
					table.insert(tileUpdate, {name = tileType, position = {tx, ty}})
				end
			end
		end
	end
	if not isBlank then
		if isRoadXa then
			local aabb = {{left, up}, {left + ROAD_HWIDTH, up + CHUNK_SIZE}}
			removeEntities(surface, aabb)
		end
		if isRoadXb then
			local aabb = {{left + CHUNK_SIZE - ROAD_HWIDTH, up}, {left + CHUNK_SIZE, up + CHUNK_SIZE}}
			removeEntities(surface, aabb)
		end
		if isRoadYa then
			local aabb = {{left, up}, {left + CHUNK_SIZE, up + ROAD_HWIDTH}}
			removeEntities(surface, aabb)
		end
		if isRoadYb then
			local aabb = {{left, up + CHUNK_SIZE - ROAD_HWIDTH}, {left + CHUNK_SIZE, up + CHUNK_SIZE}}
			removeEntities(surface, aabb)
		end
		initChunkEntities(surface, area)
		surface.set_tiles(tileUpdate)
	end
end

function getPlotAABB(x, y)
	local left = (x * PLOT_SIZE_IN_TILES)
	local up = (y * PLOT_SIZE_IN_TILES)
	local right = left + PLOT_SIZE_IN_TILES
	local down = up + PLOT_SIZE_IN_TILES
	return {{left, up}, {right, down}}
end

function charge(player, cost)
	if player.get_item_count("coin") >= cost then
		player.remove_item({name="coin", count=cost})
		return true
	end
	return false
end

function newlyRentedPlot(plotID, force, player, hours)
	local surface = player.surface
	local forceData = global.plots.forces[force.name]
	local plotData = global.plots.plots[plotID]
	local tileType = forceData.tile
	local x = plotData.x
	local y = plotData.y
	local left = (x * PLOT_SIZE_IN_TILES)
	local up = (y * PLOT_SIZE_IN_TILES)
	local right = left + PLOT_SIZE_IN_TILES
	local down = up + PLOT_SIZE_IN_TILES
	local tileUpdate = {}
	for tx = left, right, 1 do
		for ty = up, down, 1 do
			local tile = surface.get_tile(tx, ty)
			if not isIn(PRESERVE_TILES, tile.name) then
				table.insert(tileUpdate, {name = tileType, position = {tx, ty}})
			end
		end
	end
	local aabb = {{left, up}, {right, down}}
	for _, entity in pairs(surface.find_entities(aabb)) do
		if entity.type ~= "player" then
			entity.force = force
		end
	end
	surface.set_tiles(tileUpdate)
end

function expirePlot(plot)
	local plotID = plot.id
	announce("Expiring plot: ".. plotID)
	local surface = game.surfaces[plot.surface]
	local x = plot.x
	local y = plot.y
	local left = (x * PLOT_SIZE_IN_TILES)
	local up = (y * PLOT_SIZE_IN_TILES)
	local right = left + PLOT_SIZE_IN_TILES
	local down = up + PLOT_SIZE_IN_TILES
	local tileUpdate = {}
	for tx = left, right, 1 do
		for ty = up, down, 1 do
			local tile = surface.get_tile(tx, ty)
			if not isIn(PRESERVE_TILES, tile.name) then
				table.insert(tileUpdate, {name = UNCLAIMED_TILE, position = {tx, ty}})
			end
		end
	end
	surface.set_tiles(tileUpdate)
	plot.owner = nil
	plot.expires = nil
	local aabb = {{left, up}, {right, down}}
	for _, entity in pairs(surface.find_entities(aabb)) do
		if entity.type ~= "player" then
			entity.force = game.forces.enemy
		end
	end
end

function rentPlot(plotID, force, player, hours)
	local plot = global.plots.plots[plotID]
	local cost = COST_PER_HOUR * hours
	if plot.owner ~= nil and plot.owner ~= force.name then
		player.print("Cannot rent ".. plotID .. " as it is already owned.")
		return
	end
	if charge(player, cost) then
		plot.owner = force.name
		if plot.expires == nil or plot.expires == 0 then
			plot.expires = game.tick + (hours * TICKS_PER_HOUR)
			newlyRentedPlot(plotID, force, player)
		else
			plot.expires = plot.expires + (hours * TICKS_PER_HOUR)
		end
	else
		player.print("Cannot afford ".. cost.. " coins to rent this plot for ".. hours.. " hours.")
		return
	end
	recalcNextRentExpires()
	updateGUI(player, global.plots.players[player.index].location)
end

function updatePlayer(player, forced)
	local surface = player.surface
	local plotPlayer = global.plots.players[player.index]
	local plotX = math.floor(player.position.x / (CHUNK_SIZE * PLOT_SIZE))
	local plotY = math.floor(player.position.y / (CHUNK_SIZE * PLOT_SIZE))
	local plotID = getPlotID(plotX, plotY)
	local changedLocation = (plotPlayer.location ~= plotID)
	if changedLocation then
		plotPlayer.location = plotID
	end
	updateGUI(player, plotID)
end

local eventTable = {}

script.on_event(defines.events, function(event)
	local fn = eventTable[event.name]
	if fn ~= nil then
		return fn(event)
	end
end)

function doInit()
	global.hasPlotsInit = true
	global.plots = {}
	global.plots.nextPlayerForce = 1
	global.plots.players = {}
	global.plots.plots = {}
	global.plots.forces = {}
	global.plots.spawnSpiral = {}
	global.plots.spawnSpiral.x = 0
	global.plots.spawnSpiral.y = 0
	global.plots.spawnSpiral.direction = 0
	global.plots.spawnSpiral.remaining = 1
	global.plots.spawnSpiral.next = 1

	game.always_day = true
	game.peaceful_mode = true
	game.freeze_daytime(true)

	game.map_settings.enemy_evolution.time_factor = 0
	game.map_settings.enemy_evolution.destroy_factor = 0
	game.map_settings.enemy_evolution.pollution_factor = 0

	recalcNextRentExpires()
end

-- For whatever reason this is never called, I'm doing init on the first tick instead.
script.on_init(function()
	if not global.hasPlotsInit then
		doInit()
	end
end)

function getNextSpawnSpiral()
	local ss = global.plots.spawnSpiral
	local result = {}
	result.x = ss.x
	result.y = ss.y
	if ss.remaining == 0 then
		ss.direction = (ss.direction + 1) % 4
		if ss.direction == 0 or ss.direction == 2 then
			ss.next = ss.next + 1
		end
		ss.remaining = ss.next
	end
	ss.remaining = ss.remaining - 1
	if ss.direction == 0 then
		ss.x = ss.x + 1
	elseif ss.direction == 1 then
		ss.y = ss.y + 1
	elseif ss.direction == 2 then
		ss.x = ss.x - 1
	else
		ss.y = ss.y - 1
	end
	return result
end

function recalcNextRentExpires()
	local earliest = -1
	for plotID, plot in pairs(global.plots.plots) do
		if plot.owner ~= nil then
			if earliest == -1 then
				earliest = plot.expires
			else
				earliest = math.min(earliest, plot.expires)
			end
		end
	end
	global.plots.nextExpires = earliest
end

function cornerClaimed(x, y)
	local plot = global.plots.plots[getPlotID(x, y)]
	if plot ~= nil then
		if plot.owner ~= nil then
			return true
		end
	end
	plot = global.plots.plots[getPlotID(x-1, y)]
	if plot ~= nil then
		if plot.owner ~= nil then
			return true
		end
	end
	plot = global.plots.plots[getPlotID(x-1, y-1)]
	if plot ~= nil then
		if plot.owner ~= nil then
			return true
		end
	end
	plot = global.plots.plots[getPlotID(x, y-1)]
	if plot ~= nil then
		if plot.owner ~= nil then
			return true
		end
	end
	return false
end

function spawnPlayer(player)
	local coords = getNextSpawnSpiral()
	while cornerClaimed(coords.x, coords.y) do
		coords = getNextSpawnSpiral()
	end
	player.teleport({coords.x * PLOT_SIZE_IN_TILES, coords.y * PLOT_SIZE_IN_TILES})
end

eventTable[defines.events.on_player_created] = function(event)
	-- name, tick, player_index
	local player = game.players[event.player_index]
	local force = newPlayerForce(player.name)
	player.force = force
	global.plots.players[event.player_index] = {}
	player.insert{name = "iron-axe", count = 1}
	player.insert{name = "coin", count = 1000}
  player.insert{name="burner-mining-drill", count = 1}
  player.insert{name="stone-furnace", count = 1}
	player.insert{name="iron-plate", count=10}
	player.insert{name = "coal", count = 10}
	player.insert{name = "wood", count = 10}
	spawnPlayer(player)
	createGUI(player)
	updatePlayer(player, true)
end

eventTable[defines.events.on_player_mined_item] = function(event)
	-- name, tick, item_stack, player_index
end

eventTable[defines.events.on_preplayer_mined_item] = function(event)
	-- name, tick, entity, player_index

end

eventTable[defines.events.on_chunk_generated] = function(event)
	-- name, tick, area, surface
	prepareChunk(event.surface, event.area)
end

eventTable[defines.events.on_gui_click] = function(event)
	-- name, tick, element, player_index
	if event.element.name == "managePlots" then
		showManagePlots(game.players[event.player_index])
	end
	if event.element.name == "test" then
		local player = game.players[event.player_index]
		spawnPlayer(player)
	end
	if event.element.name == "claimPlot" then
		local player = game.players[event.player_index]
		local plotID = global.plots.players[player.index].location
		local plot = global.plots.plots[plotID]
		if plot == nil then
			player.print("Could not find plot ".. plotID)
		end
		local force = player.force
		local owner = plot.owner
		if owner ~= nil then
			if owner == force.name then
				player.print("You already own this plot.")
			else
				player.print("Someone else already owns this plot.")
			end
			return
		end
		rentPlot(plotID, force, player, MINIMUM_RENT_DURATION)
	end
	local split = stringSplit(event.element.name, "-")
	if #split == 3 then
		if split[1] == "addTime" then
			local player = game.players[event.player_index]
			local plotID = global.plots.players[player.index].location
			local force = player.force
			local hours = tonumber(split[2])
			local plotID = split[3]
			rentPlot(plotID, force, player, hours)
		end
	end
end

eventTable[defines.events.on_tick] = function(event)
	-- name, tick
	if not global.hasPlotsInit then
		doInit()
	end
	if event.tick == global.plots.nextExpires then
		for plotID, plot in pairs(global.plots.plots) do
			if plot.expires == event.tick then
				expirePlot(plot)
			end
		end
		recalcNextRentExpires()
	end
	for _, player in pairs(game.players) do
		if player.connected and event.tick % MOV_UPDATE_FREQ == player.index % MOV_UPDATE_FREQ then
			updatePlayer(player, false)
		end
	end
end

function hasAccess(player, x, y, ename)
	local plotX = math.floor(x / PLOT_SIZE_IN_TILES)
	local plotY = math.floor(y / PLOT_SIZE_IN_TILES)
	local plotID = getPlotID(plotX, plotY)
	local relX = x - (plotX * PLOT_SIZE_IN_TILES)
	local relY = y - (plotY * PLOT_SIZE_IN_TILES)
	if relX <= ROAD_HWIDTH or relX >= PLOT_SIZE_IN_TILES - ROAD_HWIDTH or relY <= ROAD_HWIDTH or relY >= PLOT_SIZE_IN_TILES - ROAD_HWIDTH then
		player.print("You may not build on the road.")
		return false
	end
	local plot = global.plots.plots[plotID]
	if plot.owner == nil then
		player.print("You may not interact with unowned plots. Rent the plot first.")
		return
	end
	fname = plot.owner
	if game.forces[fname] ~= player.force then
		player.print("This plot is owned by somebody else, so you can't do stuff here.")
		return false
	end
	return true
end

eventTable[defines.events.on_built_entity] = function(event)
	-- name, tick, created_entity, player_index
	local entity = event.created_entity
	local x = entity.position.x
	local y = entity.position.y
	local player = game.players[event.player_index]
	if not hasAccess(player, x, y, entity.name) then
		local name = entity.name
		entity.destroy()
		player.insert({name=name, count=1})
	else
		entity.destructible = false
	end
end

--[[
eventTable[defines.events.EVENTNAMEEVENTNAME] = function(event)
	announceObject(event, 0)
end
]]
