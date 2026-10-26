#!/usr/bin/env lua

-- Copyright (C) 2019-2025 Ulises Jeremias Cornejo Fandos
-- Licensed under MIT.
--
-- Smart floating mode for Hyprland
-- Toggles floating, centers window, and sets a nice maximum size
--
-- Lua port of smart-float.sh (same CLI, stdout, and exit behavior).
-- Talks to the Lua-config provider through `hyprctl dispatch` with
-- typed dispatcher expressions, as in hyprland-runtime.

local MAX_WIDTH = 1400 -- Maximum window width (pixels)
local MAX_HEIGHT = 900 -- Maximum window height (pixels)

local function read(cmd)
	local fh = io.popen(cmd)
	if not fh then
		return ""
	end
	local out = fh:read("*a") or ""
	fh:close()
	return out
end

local function run(cmd)
	return os.execute(cmd)
end

local function has(cmd)
	return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == true
end

-- Get active window info
local is_floating = read("hyprctl activewindow -j | jq -r '.floating'"):gsub("%s+", "")

-- Get monitor resolution
local monitor_width = tonumber(read("hyprctl monitors -j | jq -r '.[0].width'"):match("%d+")) or 0
local monitor_height = tonumber(read("hyprctl monitors -j | jq -r '.[0].height'"):match("%d+")) or 0

-- Calculate optimal size (80% of monitor or MAX size, whichever is smaller)
local optimal_width = math.floor(monitor_width * 80 / 100)
local optimal_height = math.floor(monitor_height * 80 / 100)

local final_width = optimal_width < MAX_WIDTH and optimal_width or MAX_WIDTH
local final_height = optimal_height < MAX_HEIGHT and optimal_height or MAX_HEIGHT

if is_floating == "false" then
	-- Make floating, center, and resize
	run("hyprctl dispatch 'hl.dsp.window.float({ action = \"toggle\" })'")
	run(string.format("hyprctl dispatch 'hl.dsp.window.resize({ x = %d, y = %d, relative = false })'", final_width, final_height))
	run("hyprctl dispatch 'hl.dsp.window.center()'")

	if has("notify-send") then
		run(string.format('notify-send "Smart Float" "Window: %dx%d" -t 1500 -u low', final_width, final_height))
	end
else
	-- Already floating, just tile it
	run("hyprctl dispatch 'hl.dsp.window.float({ action = \"toggle\" })'")

	if has("notify-send") then
		run('notify-send "Smart Float" "Window tiled" -t 1500 -u low')
	end
end
