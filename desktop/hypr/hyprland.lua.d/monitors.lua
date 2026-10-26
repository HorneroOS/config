-- Lua equivalent of the retired legacy monitors module.
-- Generic autodetect fallback only: no machine-specific outputs
-- (see docs/DECISIONS.md). Hosts keep fixed layouts out of tree.
-- luacheck: globals hl

hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})
