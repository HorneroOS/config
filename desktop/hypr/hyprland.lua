-- HorneroOS — Hyprland Lua configuration (the only Hyprland config;
-- the legacy hyprlang legacy hyprlang config + legacy module tree tree was retired
-- with this migration, mirroring the Lua-only dotfiles migration).
--
-- Module order mirrors the retired legacy hyprlang config source order, with
-- the old inline general/decoration/gesture/misc sections living in
-- static.lua and gestures.lua. Animation profiles stay selectable at
-- runtime through horneroctl; animations.lua is the startup default.
-- Hornero Light is opt-in: uncomment its dofile line below (it was the
-- commented-out hornero-light.conf source in the legacy entrypoint).
-- luacheck: globals hl

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/hyprland.lua.d/"

dofile(here .. "monitors.lua")
dofile(here .. "autostart.lua")
dofile(here .. "environment.lua")
dofile(here .. "input.lua")
dofile(here .. "gestures.lua")
dofile(here .. "layout.lua")
dofile(here .. "keybindings.lua")
dofile(here .. "keybindings-user.lua")
dofile(here .. "window-rules.lua")
dofile(here .. "window-rules-user.lua")
dofile(here .. "animations.lua")
dofile(here .. "smart-colors.lua")
-- dofile(here .. "hornero-light.lua") -- opt-in Hornero Light variant
dofile(here .. "plugins.lua")
dofile(here .. "static.lua")
