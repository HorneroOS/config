#!/usr/bin/env lua

-- Copyright (C) 2019-2025 Ulises Jeremias Cornejo Fandos
-- Licensed under MIT.
--
-- Interactive gaps management for Hyprland
-- Equivalent to i3-gaps interactive gap mode
--
-- Lua port of gaps-interactive.sh (same menus, stdout, and exit
-- codes). Reads the current value with the Lua-provider dotted
-- `getoption` path and writes it with `hyprctl eval hl.config(...)`,
-- because the Lua provider rejects the legacy `hyprctl keyword`.

local function read(cmd)
	local fh = io.popen(cmd)
	if not fh then
		return ""
	end
	local out = fh:read("*a") or ""
	fh:close()
	return (out:gsub("%s+$", ""))
end

local function get_gap(which)
	local opt = which == "inner" and "general.gaps_in" or "general.gaps_out"
	local custom = read("hyprctl getoption " .. opt .. " -j | jq -r '.custom'")
	return tonumber(custom:match("^%s*(%S+)")) or 0
end

local function set_gap(which, value)
	local opt = which == "inner" and "gaps_in" or "gaps_out"
	value = math.floor(value)
	os.execute(string.format("hyprctl eval 'hl.config({ general = { %s = %d } })'", opt, value))
end

local function has(cmd)
	return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == true
end

-- Returns the chosen label, or nil on EOF/invalid input. Like the
-- shell original (which captured this output in a subshell), the menu
-- text is built but not printed; only the caller's flow is visible.
local function show_menu(title)
	local lines = {
		title,
		"1) Increase (+5)",
		"2) Decrease (-5)",
		"3) Increase All (Shift +5)",
		"4) Decrease All (Shift -5)",
		"5) Set to zero",
		"6) Restore defaults",
	}
	io.write("Choice [1-6]: ")
	io.flush()
	_ = lines
	local n = io.read("*l")
	if not n then
		return nil
	end
	local labels = {
		["1"] = "Increase (+5)",
		["2"] = "Decrease (-5)",
		["3"] = "Increase All (Shift +5)",
		["4"] = "Decrease All (Shift -5)",
		["5"] = "Set to zero",
		["6"] = "Restore defaults",
	}
	return labels[n]
end

-- Main menu
print("Gaps Mode")
print("1) Inner Gaps")
print("2) Outer Gaps")
io.write("Choice [1-2]: ")
io.flush()
local main_n = io.read("*l")
if not main_n then
	os.exit(1)
end
local which
if main_n == "1" then
	which = "inner"
elseif main_n == "2" then
	which = "outer"
else
	os.exit(1)
end

local current = get_gap(which)
local title = (which == "inner" and "Inner Gaps" or "Outer Gaps") .. string.format(" (current: %d)", current)
local choice = show_menu(title)
local default_value = which == "inner" and 6 or 18

if choice == "Increase (+5)" or choice == "Increase All (Shift +5)" then
	set_gap(which, current + 5)
elseif choice == "Decrease (-5)" or choice == "Decrease All (Shift -5)" then
	set_gap(which, current - 5)
elseif choice == "Set to zero" then
	set_gap(which, 0)
elseif choice == "Restore defaults" then
	set_gap(which, default_value)
end

-- Show notification
if has("notify-send") then
	os.execute(
		string.format(
			'notify-send "Gaps Updated" "Inner: %d | Outer: %d" -t 2000',
			get_gap("inner"),
			get_gap("outer")
		)
	)
end
