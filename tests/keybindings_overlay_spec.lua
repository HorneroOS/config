-- Behavioural spec for desktop/hypr/hyprland.lua.d/keybindings-overlay.lua.
-- Run by tests/test_keybindings_overlay.sh with a mock `hl` API:
--   lua keybindings_overlay_spec.lua <repo-root> <scratch-dir>
-- luacheck: globals hl hornero_keybinds hornero_helpers

local root, scratch = arg[1], arg[2]
local hypr = root .. "/desktop/hypr/hyprland.lua.d/"

local failures = 0
local function check(cond, label)
	if cond then
		print("TEST-PASS: " .. label)
	else
		failures = failures + 1
		print("TEST-FAIL: " .. label)
	end
end

local function write(path, text)
	local fh = assert(io.open(path, "w"))
	fh:write(text)
	fh:close()
end

-- Mock compositor: live binds keyed by submap|combo, as Hyprland keeps them.
local function new_hl()
	local live, dispatched = {}, {}
	local submap = ""
	local api = {}
	api.bind = function(combo, dispatcher, _opts)
		live[submap .. "|" .. combo] = dispatcher
	end
	api.unbind = function(combo)
		live[submap .. "|" .. combo] = nil
	end
	api.define_submap = function(name, fn)
		local saved = submap
		submap = name
		fn()
		submap = saved
	end
	api.dispatch = function(d)
		dispatched[#dispatched + 1] = d
	end
	-- hl.dsp.window.kill() style chains: every field is callable and indexable.
	local function proxy(name)
		return setmetatable({}, {
			__index = function(_, field)
				return proxy(name .. "." .. field)
			end,
			__call = function(_, arg0)
				return { dsp = name, arg = arg0 }
			end,
		})
	end
	api.dsp = proxy("dsp")
	return api, live, dispatched
end

local function load_overlay(remap_text)
	local path = scratch .. "/hornero-keybinds.lua"
	if remap_text then
		write(path, remap_text)
	else
		os.remove(path)
	end
	-- The spec sets HORNERO_KEYBINDS_OVERLAY_FILE in the wrapper script.
	hornero_keybinds = nil
	local live, dispatched
	hl, live, dispatched = new_hl()
	dofile(hypr .. "keybindings-overlay.lua")
	return live, dispatched
end

-- 1. Canonical form ignores order, case and aliases.
load_overlay(nil)
local c = hornero_keybinds.canonical
check(c("SUPER + CTRL + T") == c("control + super + t"), "canonical ignores modifier order/case/aliases")
check(c("SUPER + Return") == "SUPER + return", "canonical keeps sorted mods and lower-cased key")
check(c("$mainMod + slash") == c("SUPER + slash"), "canonical maps $mainMod to SUPER")

-- 2. No overlay file: binds pass through untouched.
local live = load_overlay(nil)
hl.bind("SUPER + Return", "term")
check(live["|SUPER + Return"] == "term", "missing overlay file leaves binds untouched")

-- 3. A remap moves the bind and follows user unbind/bind pairs.
live = load_overlay('return { version = 1, remap = { { from = "SUPER + Return", to = "SUPER + X" } } }')
hl.bind("SUPER + Return", "term")
check(live["|SUPER + Return"] == nil and live["|SUPER + X"] == "term", "remap moves SUPER + Return to SUPER + X")
hl.unbind("SUPER + Return")
hl.bind("SUPER + Return", "user-term")
check(live["|SUPER + X"] == "user-term", "user unbind/bind pair follows the remap")

-- 4. Swaps translate once (no chaining).
live = load_overlay(
	'return { remap = { { from = "SUPER + A", to = "SUPER + B" }, { from = "SUPER + B", to = "SUPER + A" } } }'
)
hl.bind("SUPER + A", "alpha")
hl.bind("SUPER + B", "beta")
check(live["|SUPER + B"] == "alpha" and live["|SUPER + A"] == "beta", "swap A<->B translates each combo once")

-- 5. Disable, submap isolation, run().
live = load_overlay(
	'return { remap = { { from = "SUPER + K", to = "" }, { from = "escape", to = "SUPER + escape" } } }'
)
hl.bind("SUPER + K", "focus-up")
check(live["|SUPER + K"] == nil, "to = '' disables the bind")
hl.define_submap("resize", function()
	hl.bind("escape", "leave")
end)
check(live["resize|escape"] == "leave", "submap binds are never remapped")
local _, dispatched
live, dispatched = load_overlay(nil)
local ran = false
hl.bind("SUPER + SHIFT + F", function()
	ran = true
end)
hl.bind("SUPER + M", { dsp = "fullscreen" })
check(hornero_keybinds.run("super + shift + f") == true and ran, "run() calls a function bind by combo")
check(hornero_keybinds.run("SUPER + M") and dispatched[1].dsp == "fullscreen", "run() dispatches a dispatcher bind")
check(hornero_keybinds.run("SUPER + Q") == false, "run() reports unknown combos")

-- 6. Data file cannot execute code; malformed files are ignored.
live = load_overlay('os.exit(3) return { remap = {} }')
hl.bind("SUPER + T", "term")
check(live["|SUPER + T"] == "term", "data file runs with an empty environment (os.exit is not reachable)")
live = load_overlay("return {{{ broken")
hl.bind("SUPER + T", "term")
check(live["|SUPER + T"] == "term", "malformed overlay file is ignored")

-- 7. Reloading in the same Lua state never double-wraps.
live = load_overlay('return { remap = { { from = "SUPER + A", to = "SUPER + B" } } }')
local first_raw = hornero_keybinds._raw.bind
local wrapped = hl.bind
local keep = hornero_keybinds
dofile(hypr .. "keybindings-overlay.lua")
check(hornero_keybinds._raw.bind == first_raw and keep._wrapped_bind == wrapped, "reload reuses the raw API")
hl.bind("SUPER + A", "alpha")
check(live["|SUPER + B"] == "alpha", "reload still translates exactly once")

-- 8. The factory keybindings load through the wrapper unchanged.
live = load_overlay(nil)
hornero_helpers = setmetatable({}, {
	__index = function()
		return function() end
	end,
})
dofile(hypr .. "keybindings.lua")
local n = 0
for _ in pairs(live) do
	n = n + 1
end
check(n > 100 and live["|SUPER + slash"] ~= nil, "factory keybindings.lua loads through the wrapper (" .. n .. " binds)")

if failures > 0 then
	os.exit(1)
end
print("TEST-PASS: keybindings overlay contract holds")
