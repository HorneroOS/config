-- Hornero Light — opt-in light variant (retired hornero-light.conf).
-- Not loaded by default; uncomment its dofile line in ../hyprland.lua.
-- Loaded after smart-colors.lua, so these values take precedence.
-- luacheck: globals hl

hl.config({
	general = {
		col = {
			active_border = { colors = { "rgba(b24827ee)", "rgba(96590aee)" }, angle = 45 },
			inactive_border = "rgba(d9c2a6aa)",
		},
	},
	group = {
		col = {
			border_active = "rgba(b24827ee)",
			border_inactive = "rgba(d9c2a6aa)",
			border_locked_active = "rgba(96590aee)",
			border_locked_inactive = "rgba(f1e3ceaa)",
		},
		groupbar = {
			col = {
				active = "rgba(b24827ee)",
				inactive = "rgba(fffdf7ee)",
				locked_active = "rgba(96590aee)",
				locked_inactive = "rgba(f1e3ceee)",
			},
		},
	},
	decoration = {
		shadow = {
			color = "rgba(2b1a1133)",
		},
	},
})
