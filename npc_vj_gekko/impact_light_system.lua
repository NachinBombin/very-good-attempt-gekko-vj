-- ============================================================
-- npc_vj_gekko / impact_light_system.lua
-- CLIENT-side impact light system using ProjectedTexture.
--
-- Net message: "GekkoImpactLight"
--   Vector  hitPos
--   UInt(2) typeID  (1 = MG,  2 = Bushmaster)
--
-- light_dynamic is a no-op visually in GMod.
-- ProjectedTexture is the correct approach (same pattern as
-- muzzleflash_system.lua).
-- ============================================================
if SERVER then return end

-- ============================================================
-- PRESETS
-- ============================================================
local PRESETS = {
    [1] = { -- MG bullet impact: small warm flicker
        fov        = 90,
        nearz      = 2,
        farz       = 160,
        brightness = 2.2,
        lifetime   = 0.055,
        color      = Color(255, 200, 100),
        texture    = "effects/muzzleflash_light",
    },
    [2] = { -- Bushmaster 25mm impact: larger, hotter
        fov        = 110,
        nearz      = 2,
        farz       = 300,
        brightness = 3.0,
        lifetime   = 0.10,
        color      = Color(255, 140, 40),
        texture    = "effects/muzzleflash_light",
    },
}

local ActiveLights = {}

local function SpawnImpactLight( hitPos, typeID )
    local p = PRESETS[typeID] or PRESETS[1]
    local proj = ProjectedTexture()
    if not proj then return end

    -- Point straight down so the light pools on the struck surface.
    proj:SetTexture(p.texture)
    proj:SetFOV(p.fov)
    proj:SetNearZ(p.nearz)
    proj:SetFarZ(p.farz)
    proj:SetBrightness(p.brightness)
    proj:SetColor(p.color)
    if proj.SetEnableShadows then proj:SetEnableShadows(false) end
    proj:SetPos(hitPos)
    proj:SetAngles(Angle(90, 0, 0))
    proj:Update()

    table.insert(ActiveLights, {
        proj    = proj,
        dieTime = CurTime() + p.lifetime,
    })
end

-- ============================================================
-- LIFETIME CLEANUP
-- ============================================================
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

-- ============================================================
-- NET RECEIVER
-- ============================================================
net.Receive("GekkoImpactLight", function()
    local hitPos = net.ReadVector()
    local typeID = net.ReadUInt(2)   -- 2 bits: 1=MG, 2=Bushmaster
    SpawnImpactLight(hitPos, typeID)
end)
