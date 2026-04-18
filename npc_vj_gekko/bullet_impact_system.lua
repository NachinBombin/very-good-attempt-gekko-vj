-- ============================================================
-- npc_vj_gekko / bullet_impact_system.lua
-- Client-side projected-light bullet impact system for Gekko.
-- Mirrors muzzleflash_system.lua exactly in structure.
--
-- Net message: "GekkoBulletImpact"
--   Vector pos
--   Vector normal  (surface hit normal, pointing away from surface)
--   UInt2  preset  (1=MG tracer, 2=BUSHMASTER)
--
-- FOV is randomised per-spawn between 280-360 to simulate a
-- wide hemisphere of light blooming from the impact point.
-- ============================================================
if SERVER then return end

-- ============================================================
-- PRESETS
-- Bushmaster: same illumination envelope as BM muzzle flash
--   (farz 500, brightness 3.2, scaleMin/Max 1.00-1.25).
-- MG tracer:  considerably smaller — short range, dim, fast.
-- ============================================================
local IMPACT_FOV_MIN = 280
local IMPACT_FOV_MAX = 360

local PRESETS = {
    [1] = { -- MG tracer impact
        nearz      = 2,
        farz       = 180,
        brightness = 1.4,
        lifetime   = 0.030,
        color      = { r = 255, g = 200, b = 110 },
        scaleMin   = 0.40,
        scaleMax   = 0.65,
        texture    = "effects/muzzleflash_light",
    },
    [2] = { -- BUSHMASTER 25mm impact
        nearz      = 2,
        farz       = 500,
        brightness = 3.2,
        lifetime   = 0.055,
        color      = { r = 255, g = 175, b = 70 },
        scaleMin   = 1.00,
        scaleMax   = 1.25,
        texture    = "effects/muzzleflash_light",
    },
}

-- ============================================================
-- ACTIVE IMPACT TABLE
-- ============================================================
local ActiveImpacts = {}

local function SpawnGekkoImpact(pos, normal, presetID)
    local p = PRESETS[presetID] or PRESETS[1]

    local scale = p.scaleMin + math.random() * (p.scaleMax - p.scaleMin)

    local proj = ProjectedTexture()
    if not proj then return end

    -- FOV randomised per impact between 280-360 degrees.
    local fov = IMPACT_FOV_MIN + math.random() * (IMPACT_FOV_MAX - IMPACT_FOV_MIN)

    -- ProjectedTexture points along its forward axis.
    -- The impact normal points AWAY from the surface; we want the
    -- light cone to point INTO the surface (toward the wall) so it
    -- illuminates the area around the impact hole.
    -- Negate the normal so the cone points inward, then derive angle.
    local inward = -normal
    local ang    = inward:Angle()
    ang.p        = -ang.p   -- same left-handed pitch fix as muzzleflash_system

    proj:SetTexture(p.texture)
    proj:SetFOV(fov * scale)
    proj:SetNearZ(p.nearz)
    proj:SetFarZ(p.farz * scale)
    proj:SetBrightness(p.brightness * scale)
    proj:SetColor(Color(p.color.r, p.color.g, p.color.b))
    if proj.SetEnableShadows then proj:SetEnableShadows(false) end

    proj:SetPos(pos)
    proj:SetAngles(ang)
    proj:Update()

    table.insert(ActiveImpacts, {
        proj    = proj,
        dieTime = CurTime() + p.lifetime,
    })
end

-- ============================================================
-- LIFETIME CLEANUP
-- ============================================================
hook.Add("Think", "GekkoBulletImpact_Cleanup", function()
    local now = CurTime()
    for i = #ActiveImpacts, 1, -1 do
        local d = ActiveImpacts[i]
        if not IsValid(d.proj) or now > d.dieTime then
            if IsValid(d.proj) then d.proj:Remove() end
            table.remove(ActiveImpacts, i)
        end
    end
end)

-- ============================================================
-- NET RECEIVER
-- ============================================================
net.Receive("GekkoBulletImpact", function()
    local pos      = net.ReadVector()
    local normal   = net.ReadVector()
    local presetID = net.ReadUInt(2)   -- 2 bits covers 1-3
    SpawnGekkoImpact(pos, normal, presetID)
end)