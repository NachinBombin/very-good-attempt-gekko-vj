-- ============================================================
-- npc_vj_gekko / impact_light_system.lua
-- CLIENT-side impact light system using ProjectedTexture.
--
-- Net message: "GekkoImpactLight"
--   Vector  hitPos
--   Vector  hitNormal  (surface normal, pointing AWAY from surface)
--   UInt(2) typeID  (1 = MG,  2 = Bushmaster)
--
-- ProjectedTexture points along its forward (angle) axis.
-- We point it INTO the surface (inverse of hitNormal) so the
-- cone illuminates the wall/floor/target that was struck.
-- This is identical to how muzzleflash_system.lua works.
-- ============================================================
if SERVER then return end

local PRESETS = {
    [1] = { -- MG bullet impact: small warm flash
        fov        = 120,
        nearz      = 2,
        farz       = 200,
        brightness = 2.2,
        lifetime   = 0.055,
        color      = { r = 255, g = 200, b = 100 },
        texture    = "effects/muzzleflash_light",
    },
    [2] = { -- Bushmaster 25mm impact: larger, hotter
        fov        = 140,
        nearz      = 2,
        farz       = 340,
        brightness = 3.0,
        lifetime   = 0.10,
        color      = { r = 255, g = 140, b = 40 },
        texture    = "effects/muzzleflash_light",
    },
}

local ActiveLights = {}

local function SpawnImpactLight( hitPos, hitNormal, typeID )
    local p = PRESETS[typeID] or PRESETS[1]
    local proj = ProjectedTexture()
    if not proj then return end

    -- Point INTO the surface: negate the surface normal,
    -- then convert to angle exactly as muzzleflash_system does.
    local intoSurface = -hitNormal
    local ang = intoSurface:Angle()
    ang.p = -ang.p

    proj:SetTexture(p.texture)
    proj:SetFOV(p.fov)
    proj:SetNearZ(p.nearz)
    proj:SetFarZ(p.farz)
    proj:SetBrightness(p.brightness)
    proj:SetColor(Color(p.color.r, p.color.g, p.color.b))
    if proj.SetEnableShadows then proj:SetEnableShadows(false) end
    proj:SetPos(hitPos)
    proj:SetAngles(ang)
    proj:Update()

    table.insert(ActiveLights, {
        proj    = proj,
        dieTime = CurTime() + p.lifetime,
    })
end

hook.Add("Think", "GekkoImpactLight_Cleanup", function()
    local now = CurTime()
    for i = #ActiveLights, 1, -1 do
        local d = ActiveLights[i]
        if not IsValid(d.proj) or now > d.dieTime then
            if IsValid(d.proj) then d.proj:Remove() end
            table.remove(ActiveLights, i)
        end
    end
end)

net.Receive("GekkoImpactLight", function()
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local typeID    = net.ReadUInt(2)
    SpawnImpactLight(hitPos, hitNormal, typeID)
end)
