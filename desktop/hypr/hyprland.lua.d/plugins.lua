-- Optional plugin settings (retired legacy plugins module).
-- Every plugin is optional: without ScrollOverview its config keys do
-- not exist, so settings are applied only when the plugin is actually
-- loaded. A plugin-less session stays free of config errors (the Lua
-- equivalent of the legacy noerror guard).
-- luacheck: globals hl

local function plugin_loaded(name)
	if not hl.get_loaded_plugins then
		return false
	end
	local ok, plugins = pcall(hl.get_loaded_plugins)
	if not ok or not plugins then
		return false
	end
	for _, plugin in ipairs(plugins) do
		local pname = type(plugin) == "table" and (plugin.name or plugin.id) or plugin
		if type(pname) == "string" and pname:find(name, 1, true) then
			return true
		end
	end
	return false
end

if plugin_loaded("scrolloverview") then
	hl.config({
		plugin = {
			scrolloverview = {
				gesture_distance = 300,
				scale = 0.5,
				workspace_gap = 100,
				layout = "vertical",
				wallpaper = 0,
				blur = false,
				shadow = {
					enabled = false,
					range = 12,
					render_power = 2,
					color = "rgba(1a1a1a2e)",
				},
			},
		},
	})

	-- 3-finger swipe up toggles the overview on touchpad devices.
	hl.gesture({
		fingers = 3,
		direction = "up",
		action = "scrolloverview:overview",
	})
end
