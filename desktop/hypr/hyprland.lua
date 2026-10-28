-- HorneroOS — Hyprland Lua configuration (the only Hyprland config;
-- the legacy hyprlang config and module tree were retired with this
-- migration, mirroring the Lua-only dotfiles migration).
--
-- Module order mirrors the retired hyprlang config source order, with
-- the old inline general/decoration/gesture/misc sections living in
-- static.lua and gestures.lua. Animation profiles stay selectable at
-- runtime through horneroctl; animations.lua is the startup default.
-- Hornero Light is opt-in: uncomment its dofile line below (it was the
-- commented-out hornero-light.conf source in the legacy entrypoint).
-- luacheck: globals hl hornero_helpers

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/hyprland.lua.d/"

dofile(here .. "monitors.lua")
dofile(here .. "autostart.lua")
dofile(here .. "environment.lua")
dofile(here .. "input.lua")
dofile(here .. "gestures.lua")
dofile(here .. "layout.lua")
hornero_helpers = dofile(here .. "helpers.lua")
dofile(here .. "keybindings.lua")
dofile(here .. "keybindings-user.lua")
dofile(here .. "window-rules.lua")
dofile(here .. "window-rules-user.lua")
dofile(here .. "animations.lua")
dofile(here .. "smart-colors.lua")
-- dofile(here .. "hornero-light.lua") -- opt-in Hornero Light variant
dofile(here .. "plugins.lua")
dofile(here .. "static.lua")
