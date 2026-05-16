-- ============================================================
-- npc_vj_gekko / muzzleflash_system.lua
-- Client-side projected-light muzzle flash system for Gekko.
-- Adapted from l4d_mf_client.lua player addon logic.
--
-- Net message: "GekkoMuzzleFlash"
--   Vector pos
--   Vector normal
--   UInt8  preset  (1=MG, 2=MISSILE, 3=BUSHMASTER, 4=NIKITA)
-- ============================================================
if SERVER then return end

-- ============================================================
-- PRESETS
-- farz ~157-240 units = 4+ metres of illumination radius
-- MG is brightest flash but short lifetime and throttled
-- ============================================================
local PRESETS = {
    [1] = { -- MG
        fov        = 150,
        nearz      = 2,
        farz       = 380,
        brightness = 2.8,
        lifetime   = 0.042,
        color      = { r = 255, g = 190, b = 90 },
        scaleMin   = 0.90,
        scaleMax   = 1.15,
        texture    = "effects/muzzleflash_light",
    },
    [2] = { -- MISSILE / SALVO / TOPMISSILE / TRACKMISSILE / ORBITRPG
        fov        = 145,
        nearz      = 2,
        farz       = 440,
        brightness = 3.4,
        lifetime   = 0.060,
        color      = { r = 255, g = 160, b = 55 },
        scaleMin   = 1.10,
        scaleMax   = 1.35,
        texture    = "effects/muzzleflash_light",
    },
    [3] = { -- BUSHMASTER 25mm
        fov        = 160,
        nearz      = 2,
        farz       = 500,
        brightness = 3.2,
        lifetime   = 0.055,
        color      = { r = 255, g = 175, b = 70 },
        scaleMin   = 1.00,
        scaleMax   = 1.25,
        texture    = "effects/muzzleflash_light",
    },
    [4] = { -- NIKITA launch
        fov        = 150,
        nearz      = 2,
        farz       = 500,
        brightness = 3.6,
        lifetime   = 0.070,
        color      = { r = 255, g = 145, b = 40 },
        scaleMin   = 1.15,
        scaleMax   = 1.40,
        texture    = "effects/muzzleflash_light",
    },
}

-- ============================================================
-- ACTIVE FLASH TABLE
-- ============================================================
local ActiveFlashes = {}

local function SpawnGekkoFlash(pos, normal, presetID)
    local p = PRESETS[presetID] or PRESETS[1]

    local scale = p.scaleMin + math.random() * (p.scaleMax - p.scaleMin)

    local proj = ProjectedTexture()
    if not proj then return end

    local tex = p.texture
    if tex == "" then tex = "effects/muzzleflash_light" end

    -- Convert the firing direction vector to a proper Angle for ProjectedTexture.
    -- GMod's ProjectedTexture points along the FORWARD axis of the angle.
    -- Vector:Angle() returns pitch/yaw correctly but pitch sign must be negated
    -- because ProjectedTexture uses a left-handed pitch convention.
    local ang = normal:Angle()
    ang.p = -ang.p

    proj:SetTexture(tex)
    proj:SetFOV(p.fov * scale)
    proj:SetNearZ(p.nearz)
    proj:SetFarZ(p.farz * scale)
    proj:SetBrightness(p.brightness * scale)
    proj:SetColor(Color(p.color.r, p.color.g, p.color.b))
    if proj.SetEnableShadows then proj:SetEnableShadows(false) end -- perf: no shadows on flash

    proj:SetPos(pos)
    proj:SetAngles(ang)
    proj:Update()

    table.insert(ActiveFlashes, {
        proj    = proj,
        dieTime = CurTime() + p.lifetime,
    })
end

-- ============================================================
-- LIFETIME CLEANUP
-- ============================================================
hook.Add("Think", "GekkoMuzzleFlash_Cleanup", function()
    local now = CurTime()
    for i = #ActiveFlashes, 1, -1 do
        local d = ActiveFlashes[i]
        if not IsValid(d.proj) or now > d.dieTime then
            if IsValid(d.proj) then d.proj:Remove() end
            table.remove(ActiveFlashes, i)
        end
    end
end)

-- ============================================================
-- NET RECEIVER
-- ============================================================
net.Receive("GekkoMuzzleFlash", function()
    local pos      = net.ReadVector()
    local normal   = net.ReadVector()
    local presetID = net.ReadUInt(3)  -- 3 bits covers 1-7
    SpawnGekkoFlash(pos, normal, presetID)
end)