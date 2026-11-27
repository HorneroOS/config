-- HorneroOS — Hyprland Lua configuration (the only Hyprland config;
-- the legacy hyprlang config and module tree were retired with this
-- migration, mirroring the Lua-only dotfiles migration).
--
-- Factory/user lifecycle (HorneroOS/config#184):
-- - Factory modules load from /etc/xdg/hypr/hyprland.lua.d/ when present
--   (override via HORNERO_HYPR_FACTORY_DIR), falling back per-file to the
--   sibling hyprland.lua.d/ directory so non-packaged and hermetic --dest
--   installs keep working identically. This ensures pacman upgrades reach
--   existing users even when stale /etc/skel copies sit in ~/.config/hypr/.
-- - User override hooks (monitors-user.lua, keybindings-user.lua,
--   window-rules-user.lua) always load from the user's hyprland.lua.d/
--   directory first, falling back to factory_dir if absent.
-- - To pin a custom local copy of a factory module, replace its
--   load_factory("...") line below with load_user("...").
--
-- Module order mirrors the retired hyprlang config source order, with
-- the old inline general/decoration/gesture/misc sections living in
-- static.lua and gestures.lua. Animation profiles stay selectable at
-- runtime through horneroctl; animations.lua is the startup default.
-- Hornero Signal Day borders are opt-in: uncomment the signal-day.lua
-- load_factory line below (applying a theme regenerates the border cache instead).
-- luacheck: globals hl hornero_helpers

local user_dir = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/hyprland.lua.d/"
local system_factory_dir = "/etc/xdg/hypr/hyprland.lua.d/"

local function file_exists(path)
	local fh = io.open(path, "r")
	if fh then
		fh:close()
		return true
	end
	return false
end

local function resolve_factory_dir()
	local env_dir = os.getenv("HORNERO_HYPR_FACTORY_DIR")
	if env_dir and env_dir ~= "" then
		if env_dir:sub(-1) ~= "/" then
			env_dir = env_dir .. "/"
		end
		return env_dir
	end
	if file_exists(system_factory_dir .. "static.lua") then
		return system_factory_dir
	end
	return user_dir
end

local factory_dir = resolve_factory_dir()

local function load_factory(mod)
	if file_exists(factory_dir .. mod) then
		return dofile(factory_dir .. mod)
	end
	return dofile(user_dir .. mod)
end

local function load_user(mod)
	if file_exists(user_dir .. mod) then
		return dofile(user_dir .. mod)
	end
	if file_exists(factory_dir .. mod) then
		return dofile(factory_dir .. mod)
	end
end

load_factory("monitors.lua")
load_user("monitors-user.lua")
load_factory("autostart.lua")
load_factory("environment.lua")
load_factory("input.lua")
load_factory("gestures.lua")
load_factory("layout.lua")
-- Managed rebinds (hornero-keybinds.lua) wrap hl.bind before any bind loads.
load_factory("keybindings-overlay.lua")
hornero_helpers = load_factory("helpers.lua")
load_factory("keybindings.lua")
load_user("keybindings-user.lua")
load_factory("window-rules.lua")
load_user("window-rules-user.lua")
load_factory("animations.lua")
load_factory("smart-colors.lua")
-- load_factory("signal-day.lua") -- opt-in Hornero Signal Day borders
load_factory("plugins.lua")
load_factory("static.lua")
