-- In-process Hyprland helpers (loaded by hyprland.lua before keybindings.lua).
--
-- The gaps, smart-float and notification-action logic used to ship as
-- standalone script files, invoked by path from keybindings. They are only ever used from inside Hyprland, so they now
-- live here as Lua functions on the returned table (also published as the
-- global `hornero_helpers` by hyprland.lua). Keybindings call them
-- directly through `hl.bind(key, function() ... end)` callbacks, and
-- external callers can reach the same functions through the compositor,
-- e.g. `hyprctl eval 'hornero_helpers.smart_float()'`.
-- No standalone script remains.
-- luacheck: globals hl

local M = {}

local function has(cmd)
	return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == true
end

local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function notify(text, timeout)
	if hl and hl.notification and hl.notification.create then
		local ok = pcall(hl.notification.create, { text = text, timeout = timeout or 2000 })
		if ok then
			return
		end
	end
	if has("notify-send") then
		os.execute("notify-send " .. shell_quote(text) .. " -t " .. tostring(timeout or 2000))
	end
end

-- ---------------------------------------------------------------------------
-- Interactive gaps (port of the former gaps-interactive script)
-- ---------------------------------------------------------------------------
-- The standalone script read a numbered menu from stdin, which a
-- keybinding-launched process never really had. The in-process
-- equivalent is interactive in the compositor itself: entering the
-- `gaps` submap, I/O select inner/outer gaps, +/- adjust by 5 (the
-- script's "Increase/Decrease" and "Increase/Decrease All" entries both
-- adjusted only the selected gap, and still do), 0 zeroes the selected
-- gap, R restores its default (6 inner / 18 outer), Esc/Return exits.

local gaps_target = "inner"
local gaps_defaults = { inner = 6, outer = 18 }

local function gap_value(which)
	local key = which == "inner" and "general.gaps_in" or "general.gaps_out"
	if hl and hl.get_config then
		local ok, value = pcall(hl.get_config, key)
		if ok then
			if type(value) == "number" then
				return math.floor(value)
			end
			if type(value) == "table" then
				local first = tonumber(value[1])
				if first then
					return math.floor(first)
				end
			end
			local as_number = tonumber(value)
			if as_number then
				return math.floor(as_number)
			end
		end
	end
	return gaps_defaults[which] or 0
end

local function set_gap(which, value)
	value = math.floor(value)
	if which == "inner" then
		hl.config({ general = { gaps_in = value } })
	else
		hl.config({ general = { gaps_out = value } })
	end
	notify(
		string.format("Gaps Updated: Inner: %d | Outer: %d", gap_value("inner"), gap_value("outer")),
		2000
	)
end

local function adjust_gap(delta)
	set_gap(gaps_target, gap_value(gaps_target) + delta)
end

function M.gaps_interactive()
	gaps_target = "inner"
	notify("Gaps Mode: I inner / O outer, +/- adjust, 0 zero, R defaults, Esc exit", 3000)
	hl.dispatch(hl.dsp.submap("gaps"))
end

-- Exposed for tests / `hyprctl eval`; the submap below is the UI.
M._gap_value = gap_value
M._set_gap = set_gap

hl.define_submap("gaps", function()
	hl.bind("I", function()
		gaps_target = "inner"
		notify(string.format("Inner Gaps (current: %d)", gap_value("inner")), 1500)
	end)
	hl.bind("O", function()
		gaps_target = "outer"
		notify(string.format("Outer Gaps (current: %d)", gap_value("outer")), 1500)
	end)
	hl.bind("equal", function()
		adjust_gap(5)
	end, { repeating = true })
	hl.bind("minus", function()
		adjust_gap(-5)
	end, { repeating = true })
	hl.bind("SHIFT + equal", function()
		adjust_gap(5)
	end, { repeating = true })
	hl.bind("SHIFT + minus", function()
		adjust_gap(-5)
	end, { repeating = true })
	hl.bind("0", function()
		set_gap(gaps_target, 0)
	end)
	hl.bind("R", function()
		set_gap(gaps_target, gaps_defaults[gaps_target])
	end)
	hl.bind("escape", hl.dsp.submap("reset"))
	hl.bind("Return", hl.dsp.submap("reset"))
end)

-- ---------------------------------------------------------------------------
-- Smart float (port of the former smart-float script)
-- ---------------------------------------------------------------------------
-- Floats the active window at 80% of the active monitor (capped at
-- 1400x900), centers it and notifies; if already floating, tiles it.

local MAX_WIDTH = 1400
local MAX_HEIGHT = 900

function M.smart_float()
	if not (hl and hl.get_active_window) then
		return
	end
	local win = hl.get_active_window()
	if not win then
		return
	end
	local monitor = nil
	if hl.get_active_monitor then
		monitor = hl.get_active_monitor()
	end
	monitor = monitor or win.monitor
	local monitor_width = (monitor and tonumber(monitor.width)) or 0
	local monitor_height = (monitor and tonumber(monitor.height)) or 0

	local optimal_width = math.floor(monitor_width * 80 / 100)
	local optimal_height = math.floor(monitor_height * 80 / 100)
	local final_width = optimal_width < MAX_WIDTH and optimal_width or MAX_WIDTH
	local final_height = optimal_height < MAX_HEIGHT and optimal_height or MAX_HEIGHT

	if not win.floating then
		hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
		hl.dispatch(hl.dsp.window.resize({ x = final_width, y = final_height, relative = false }))
		hl.dispatch(hl.dsp.window.center())
		notify(string.format("Smart Float: Window: %dx%d", final_width, final_height), 1500)
	else
		hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
		notify("Smart Float: Window tiled", 1500)
	end
end

-- ---------------------------------------------------------------------------
-- Notification actions (port of the former notification-handler script)
-- ---------------------------------------------------------------------------
-- Verified callers: none in this repo. No systemd unit, D-Bus service,
-- mako/dunst/swaync config or keybinding referenced the standalone
-- script (the shell owns org.freedesktop.Notifications and materialize
-- shadows those daemons), so it is not kept standalone either. A
-- notification daemon that wants these actions can invoke the function
-- through the compositor, e.g.
--   hyprctl eval 'hornero_helpers.notification_action("left", "Spotify", "", "")'
-- Keeping it here preserves the logic (media keys via playerctl, URL
-- opening for browsers, focus-or-launch for chat apps) without a file
-- that only Hyprland-adjacent callers could ever reach.

local function log(level, message)
	if level == "ERROR" or level == "WARN" then
		io.stderr:write(string.format("[%s] %s\n", level, message))
	elseif level == "INFO" then
		print("[INFO] " .. message)
	else
		print(message)
	end
end

local MEDIA_APPS = { Spotify = true, spotify = true, mpv = true, vlc = true, rhythmbox = true }
local BROWSER_APPS = {
	["zen-browser"] = true,
	Zen = true,
	["app.zen_browser.Zen"] = true,
	["brave-browser"] = true,
	firefox = true,
	chromium = true,
}
local CHAT_APPS = { discord = true, Slack = true, ["telegram-desktop"] = true }

local MEDIA_COMMANDS = {
	middle = { "play-pause", "Media play/pause toggled" },
	left = { "previous", "Previous track" },
	right = { "next", "Next track" },
}

function M.notification_action(action, app_name, summary, _body)
	action = action or ""
	app_name = app_name or ""
	summary = summary or ""

	if action == "-h" or action == "--help" then
		print("Usage: hornero_helpers.notification_action(ACTION, APP_NAME, SUMMARY, BODY)")
		print("Actions: middle, left, right")
		return true
	end
	if action == "" then
		log("ERROR", "No action specified")
		return false
	end

	if MEDIA_APPS[app_name] then
		local entry = MEDIA_COMMANDS[action]
		if entry and has("playerctl") then
			hl.exec_cmd("playerctl " .. entry[1])
			log("INFO", entry[2])
		end
	end

	if BROWSER_APPS[app_name] then
		if action == "left" and summary:find("https?://") then
			hl.exec_cmd("xdg-open " .. shell_quote(summary))
		end
	elseif CHAT_APPS[app_name] then
		if action == "left" then
			local ok = false
			if app_name:match("^[A-Za-z0-9_.-]+$") and hl.dispatch and hl.dsp and hl.dsp.focus then
				ok = pcall(hl.dispatch, hl.dsp.focus({ window = "class:" .. app_name }))
			end
			if not ok then
				hl.exec_cmd("exo-open --launch " .. shell_quote(app_name))
			end
		end
	end
	return true
end

return M
