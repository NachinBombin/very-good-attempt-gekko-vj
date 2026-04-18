-- ============================================================
-- npc_vj_gekko / bullet_impact_system.lua
-- Client-side projected-light bullet impact system for Gekko.
-- Mirrors muzzleflash_system.lua exactly in structure.
--
-- Net message: "GekkoBulletImpact"
--   Vector pos
--   Vector normal  (surface hit normal, pointing away from surface)
--   UInt3  preset  (1=MG tracer, 2=BUSHMASTER)
-- ============================================================
if SERVER then return end

-- ============================================================
-- PRESETS
-- FOV is a fixed cone angle (degrees), same convention as
-- muzzleflash_system.  Scale multiplier applied at spawn.
-- Bushmaster: same illumination envelope as BM muzzle flash.
-- MG tracer:  smaller — short range, dim, fast.
-- ============================================================
local PRESETS = {
    [1] = { -- MG tracer impact
        fov        = 120,
        nearz      = 2,
        farz       = 380,
        brightness = 3.4,
        lifetime   = 0.060,
        color      = { r = 255, g = 200, b = 110 },
        scaleMin   = 1.00,
        scaleMax   = 1.55,
        texture    = "effects/muzzleflash_light",
    },
    [2] = { -- BUSHMASTER 25mm impact
        fov        = 150,
        nearz      = 2,
        farz       = 900,
        brightness = 3.2,
        lifetime   = 0.075,
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

    -- Point the light along the surface normal (away from surface,
    -- back toward the shooter).  Identical convention to muzzleflash:
    -- Vector:Angle() gives pitch/yaw, pitch sign negated for
    -- ProjectedTexture's left-handed pitch convention.
    local ang = normal:Angle()
    ang.p = -ang.p

    proj:SetTexture(p.texture)
    proj:SetFOV(math.min(p.fov * scale, 179))  -- clamp: ProjectedTexture hard-caps at 180°
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
    local presetID = net.ReadUInt(3)   -- 3 bits covers 1-7
    SpawnGekkoImpact(pos, normal, presetID)
end)