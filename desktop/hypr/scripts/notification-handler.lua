#!/usr/bin/env lua

-- Copyright (C) 2019-2025 Ulises Jeremias Cornejo Fandos
-- Licensed under MIT.
--
-- Notification action handler for Mako
-- Handles interactive notification actions (media controls, app launching, etc.)
--
-- Usage:
--     notification-handler.lua [ACTION] [APP_NAME] [SUMMARY] [BODY]
--
-- Actions:
--     middle       Handle middle button click
--     left         Handle left button click
--     right        Handle right button click
--
-- Options:
--     -h, --help   Show this help message
--
-- Lua port of notification-handler.sh (same CLI, stdout/stderr, and
-- exit codes). The shell original sourced easy-options only to split
-- positional arguments; positional handling is identical here.

local ACTION = arg[1] or ""
local APP_NAME = arg[2] or ""
local SUMMARY = arg[3] or ""
local BODY = arg[4] or ""

if ACTION == "-h" or ACTION == "--help" then
	print("Usage: notification-handler.lua [ACTION] [APP_NAME] [SUMMARY] [BODY]")
	print("Actions: middle, left, right")
	print("Options: -h, --help   Show this help message")
	os.exit(0)
end

local function log(level, message)
	if level == "ERROR" or level == "WARN" then
		io.stderr:write(string.format("[%s] %s\n", level, message))
	elseif level == "INFO" then
		print("[INFO] " .. message)
	else
		print(message)
	end
end

local function has(cmd)
	return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == true
end

local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
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

local function handle_media_notification(app_name, action)
	if not MEDIA_APPS[app_name] then
		return
	end
	local commands = {
		middle = { "play-pause", "Media play/pause toggled" },
		left = { "previous", "Previous track" },
		right = { "next", "Next track" },
	}
	local entry = commands[action]
	if entry and has("playerctl") then
		os.execute("playerctl " .. entry[1])
		log("INFO", entry[2])
	end
end

local function handle_app_notification(app_name, action, summary, _body)
	if BROWSER_APPS[app_name] then
		if action == "left" and summary:find("https?://") then
			os.execute("xdg-open " .. shell_quote(summary) .. " 2>/dev/null || true")
		end
	elseif CHAT_APPS[app_name] then
		if action == "left" then
			-- Lua-provider dispatch syntax; only simple class names are
			-- interpolated, anything else falls back to launching.
			local ok = false
			if app_name:match("^[A-Za-z0-9_.-]+$") then
				ok = os.execute(
					"hyprctl dispatch "
						.. shell_quote(string.format('hl.dsp.focus({ window = "class:%s" })', app_name))
						.. " 2>/dev/null"
				) == true
			end
			if not ok then
				os.execute("exo-open --launch " .. shell_quote(app_name) .. " 2>/dev/null || true")
			end
		end
	end
end

if ACTION == "" then
	log("ERROR", "No action specified")
	os.exit(1)
end

handle_media_notification(APP_NAME, ACTION)
handle_app_notification(APP_NAME, ACTION, SUMMARY, BODY)
