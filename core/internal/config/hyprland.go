package config

import _ "embed"

//go:embed embedded/hyprland.lua
var HyprlandLuaConfig string

//go:embed embedded/hypr-colors.lua
var CyShellColorsLuaConfig string

//go:embed embedded/hypr-layout.lua
var CyShellLayoutLuaConfig string

//go:embed embedded/hypr-binds.lua
var CyShellBindsLuaConfig string

//go:embed embedded/hypr-outputs.lua
var CyShellOutputsLuaConfig string

//go:embed embedded/hypr-cursor.lua
var CyShellCursorLuaConfig string

//go:embed embedded/hypr-windowrules.lua
var CyShellWindowRulesLuaConfig string

//go:embed embedded/hypr-binds-user.lua
var CyShellBindsUserLuaConfig string
