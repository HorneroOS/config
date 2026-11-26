-- Lua equivalent of the retired keyboard, pointer, touchpad, and cursor
-- settings from legacy input module (loaded by hyprland.lua).
-- luacheck: globals hl

hl.config({
	input = {
		-- Inherit XKB layout/options from the session locale/environment when set;
		-- users can override via `horneroctl hardware keyboard layout` or monitors-user/input overrides.
		kb_layout = os.getenv("XKB_DEFAULT_LAYOUT") or "us",
		kb_variant = os.getenv("XKB_DEFAULT_VARIANT") or "",
		kb_model = "",
		kb_options = os.getenv("XKB_DEFAULT_OPTIONS") or "",
		kb_rules = "",
		follow_mouse = 1,
		repeat_rate = 50,
		repeat_delay = 300,
		numlock_by_default = true,
		sensitivity = 0.0,
		accel_profile = "flat",
		force_no_accel = false,
		touchpad = {
			natural_scroll = true,
			disable_while_typing = true,
			clickfinger_behavior = true,
			middle_button_emulation = true,
			tap_to_click = true,
			drag_lock = false,
			scroll_factor = 1.0,
		},
	},
	cursor = {
		-- Do not force no_hardware_cursors globally; hardware cursors work on
		-- modern Intel/AMD/NVIDIA drivers and avoid software-cursor latency.
		-- Set no_hardware_cursors = 1 only in a VM or on an affected GPU.
		no_break_fs_vrr = 0,
		min_refresh_rate = 24,
		hotspot_padding = 1,
		inactive_timeout = 0,
		no_warps = false,
		persistent_warps = false,
		warp_on_change_workspace = 0,
	},
})
