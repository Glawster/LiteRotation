-- OMP-MANAGED-BEGIN
std = "lua51"
max_line_length = false
codes = true
exclude_files = { ".git/", ".luarocks/", "lua_modules/", "Libs/", "libs/" }
-- WoW's API is thousands of globals; reading an undefined global (113) is not
-- reported. Writing one (111) or mutating one (112, 122) is: that is the classic
-- addon bug. List the globals the addon deliberately sets in `globals` below.
ignore = { "113", "212/self", "211/_.*", "212/_.*", "213/_.*" }
-- OMP-MANAGED-END

-- Globals this addon sets: SavedVariables, slash commands, bindings.
globals = {
    "LiteRotation", -- the addon table, for /dump and other addons
    "LiteRotationDB",
    "SLASH_LITEROTATION1",
    "SlashCmdList",
}
