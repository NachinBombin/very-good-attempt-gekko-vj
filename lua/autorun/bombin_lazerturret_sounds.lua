-- ============================================================
--  Bombin Addons - Laser Turret | Sound Registration
-- ============================================================
AddCSLuaFile()

local lazPath = "weapons/overcharged/special_lazer/"

sound.Add({
    name    = "OVG_LaserGun.Charging",
    channel = CHAN_WEAPON,
    volume  = 1.0,
    level   = 90,
    sound   = lazPath .. "laz_start.wav"
})

sound.Add({
    name    = "OVG_LaserGun.FireStart",
    channel = CHAN_STATIC,
    volume  = 1.0,
    level   = 90,
    sound   = {
        lazPath .. "loop/loopstart1.wav",
        lazPath .. "loop/loopstart2.wav",
    }
})

sound.Add({
    name    = "OVG_LaserGun.FireLoop",
    channel = CHAN_WEAPON,
    volume  = 0.7,
    level   = 90,
    sound   = lazPath .. "laz_loop.wav"
})

sound.Add({
    name    = "OVG_LaserGun.FireEnd",
    channel = CHAN_WEAPON,
    volume  = 0.55,
    level   = 90,
    sound   = lazPath .. "laz_end.wav"
})

sound.Add({
    name    = "OVG_LaserGun.Empty",
    channel = CHAN_WEAPON,
    volume  = 0.55,
    level   = 90,
    sound   = lazPath .. "laz_noammo.wav"
})
