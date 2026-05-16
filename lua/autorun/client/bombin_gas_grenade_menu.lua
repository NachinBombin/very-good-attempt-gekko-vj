--[[-------------------------------------------------------------------------
    Bombin Gas Grenade - Client Options Panel

    Found in: Options -> Bombin Addons -> Gas Grenade

    ConVars use FCVAR_USERINFO (userinfo = true, 4th arg) so the server
    can read them via player:GetInfoNum(). Settings apply on the next spawn.
---------------------------------------------------------------------------]]

if SERVER then return end

local ADDON_TITLE    = "Gas Grenade"
local ADDON_CATEGORY = "Bombin Addons"

-- 3rd arg = save to cfg, 4th arg = userinfo (must be true for GetInfoNum to work server-side)
CreateClientConVar("bombin_gasg_min_size",     "0.85",  true, true)
CreateClientConVar("bombin_gasg_max_size",     "1.75",  true, true)
CreateClientConVar("bombin_gasg_min_duration", "18",    true, true)
CreateClientConVar("bombin_gasg_max_duration", "35",    true, true)

CreateClientConVar("bombin_gasg_basespread",   "12",    true, true)
CreateClientConVar("bombin_gasg_spreadspeed",  "18",    true, true)
CreateClientConVar("bombin_gasg_speed",        "20",    true, true)
CreateClientConVar("bombin_gasg_startsize",    "16",    true, true)
CreateClientConVar("bombin_gasg_endsize",      "72",    true, true)
CreateClientConVar("bombin_gasg_rate",         "48",    true, true)
CreateClientConVar("bombin_gasg_jetlength",    "180",   true, true)
CreateClientConVar("bombin_gasg_windangle",    "0",     true, true)
CreateClientConVar("bombin_gasg_windspeed",    "0",     true, true)
CreateClientConVar("bombin_gasg_twist",        "8",     true, true)
CreateClientConVar("bombin_gasg_roll",         "4",     true, true)

CreateClientConVar("bombin_gasg_colorr",       "68",    true, true)
CreateClientConVar("bombin_gasg_colorg",       "68",    true, true)
CreateClientConVar("bombin_gasg_colorb",       "68",    true, true)
CreateClientConVar("bombin_gasg_renderamt",    "245",   true, true)

CreateClientConVar("bombin_gasg_soundvolume",  "0.9",   true, true)
CreateClientConVar("bombin_gasg_soundpitch",   "100",   true, true)

-- ----------------------------------------------------------------
-- Category registration
-- ----------------------------------------------------------------
hook.Add("PopulateToolMenus", "BombinGasGrenadeAddCategory", function()
    spawnmenu.AddToolMenuCategory("Options", ADDON_CATEGORY)
end)

local function BuildGasGrenadeOptions()
    spawnmenu.AddToolMenuOption("Options", ADDON_CATEGORY, "BombinGasGrenadePanel", ADDON_TITLE, "", "", function(panel)
        panel:ClearControls()

        panel:Help("BOMBIN GAS GRENADE")
        panel:Help(
            "Spawns a black HL2 grenade that releases gas.\n" ..
            "Each spawn rolls random size and duration between your min/max.\n" ..
            "Gas fades out naturally after the timer ends.\n" ..
            "Settings apply to the NEXT grenade you spawn."
        )

        -- ----------------------------------------------------------------
        -- Random Roll Settings
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Random Roll Settings  -----")
        panel:NumSlider("Min Gas Size", "bombin_gasg_min_size", 0.10, 10, 2)
        panel:ControlHelp("Lowest random size multiplier allowed on spawn.")

        panel:NumSlider("Max Gas Size", "bombin_gasg_max_size", 0.10, 10, 2)
        panel:ControlHelp("Highest random size multiplier allowed on spawn.")

        panel:NumSlider("Min Gas Duration (seconds)", "bombin_gasg_min_duration", 1, 300, 1)
        panel:ControlHelp("Shortest random gas duration.")

        panel:NumSlider("Max Gas Duration (seconds)", "bombin_gasg_max_duration", 1, 300, 1)
        panel:ControlHelp("Longest random gas duration.")

        -- ----------------------------------------------------------------
        -- Smoke Settings
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Smoke Settings  -----")
        panel:NumSlider("Base Spread", "bombin_gasg_basespread", 0, 256, 0)
        panel:ControlHelp("Starting width of the gas.")

        panel:NumSlider("Spread Speed", "bombin_gasg_spreadspeed", 0, 256, 0)
        panel:ControlHelp("How quickly the gas widens.")

        panel:NumSlider("Speed", "bombin_gasg_speed", 1, 256, 0)
        panel:ControlHelp("How fast the gas travels upward.")

        panel:NumSlider("Start Size", "bombin_gasg_startsize", 1, 256, 0)
        panel:ControlHelp("Particle size at the source.")

        panel:NumSlider("End Size", "bombin_gasg_endsize", 1, 512, 0)
        panel:ControlHelp("Particle size later in the plume.")

        panel:NumSlider("Rate", "bombin_gasg_rate", 1, 256, 0)
        panel:ControlHelp("How dense the emission is.")

        panel:NumSlider("Jet Length", "bombin_gasg_jetlength", 1, 1024, 0)
        panel:ControlHelp("How far the gas can project.")

        panel:NumSlider("Wind Angle", "bombin_gasg_windangle", -180, 180, 0)
        panel:ControlHelp("Direction of wind influence.")

        panel:NumSlider("Wind Speed", "bombin_gasg_windspeed", 0, 256, 0)
        panel:ControlHelp("Strength of wind influence.")

        panel:NumSlider("Twist", "bombin_gasg_twist", -360, 360, 0)
        panel:ControlHelp("Spiral motion in the smoke.")

        panel:NumSlider("Roll", "bombin_gasg_roll", -360, 360, 0)
        panel:ControlHelp("Roll variation in the smoke.")

        -- ----------------------------------------------------------------
        -- Appearance
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Gas Appearance  -----")
        panel:NumSlider("Gas Red",   "bombin_gasg_colorr", 0, 255, 0)
        panel:ControlHelp("Red color channel.")

        panel:NumSlider("Gas Green", "bombin_gasg_colorg", 0, 255, 0)
        panel:ControlHelp("Green color channel.")

        panel:NumSlider("Gas Blue",  "bombin_gasg_colorb", 0, 255, 0)
        panel:ControlHelp("Blue color channel.")

        panel:NumSlider("Gas Alpha", "bombin_gasg_renderamt", 1, 255, 0)
        panel:ControlHelp("Opacity. Higher = less transparent.")

        -- ----------------------------------------------------------------
        -- Sound
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Sound  -----")
        panel:NumSlider("Sound Volume", "bombin_gasg_soundvolume", 0, 1, 2)
        panel:ControlHelp("Base loop volume before the last 5-second fade.")

        panel:NumSlider("Sound Pitch", "bombin_gasg_soundpitch", 60, 180, 0)
        panel:ControlHelp("Pitch of the gas loop.")

    end)
end

hook.Add("PopulateToolMenu", "BombinGasGrenadeAddOptionsMenu", BuildGasGrenadeOptions)