-- ============================================================
-- npc_vj_gekko / cl_aps.lua
-- CLIENT  —  APS visual receivers
--
-- Handles two net messages sent by aps_system.lua:
--   GekkoAPSLaser     — tracking beam while threat is locked
--   GekkoAPSIntercept — burst muzzle flash + tracer at intercept
--
-- Laser beam: 6px wide, alpha 230 (nearly opaque solid red)
-- Laser dies 120ms after the last GekkoAPSLaser message
--   (covers the scan interval gap of 50ms with headroom).
-- ============================================================

if SERVER then return end

-- ============================================================
-- LASER STATE
-- _GekkoAPS_Lasers[entIndex] = { src, dst, dieTime }
-- Keyed by server entity index so multiple Gekkos are independent.
-- ============================================================
_GekkoAPS_Lasers = _GekkoAPS_Lasers or {}

local LASER_MAT      = Material("effects/laser1")
local LASER_COLOR    = Color(255, 30, 30, 230)   -- bright red, nearly opaque
local LASER_WIDTH    = 6                          -- 3× the original 2px
local LASER_TTL      = 0.12                       -- 120ms persistence per tick

-- ============================================================
-- NET: GekkoAPSLaser
-- Server sends this every APS_SCAN_INTERVAL (0.05s) while locked.
-- ============================================================
net.Receive("GekkoAPSLaser", function()
    local src      = net.ReadVector()
    local dst      = net.ReadVector()
    local entIdx   = net.ReadUInt(16)   -- Gekko entity index

    _GekkoAPS_Lasers[entIdx] = {
        src     = src,
        dst     = dst,
        dieTime = CurTime() + LASER_TTL,
    }
end)

-- ============================================================
-- NET: GekkoAPSIntercept
-- Burst muzzle flash + tracer per pulse.
-- firstShot flag: snaps the laser to the intercept point
-- for one final 80ms flash, then clears it.
-- ============================================================
net.Receive("GekkoAPSIntercept", function()
    local src        = net.ReadVector()
    local dir        = net.ReadVector()
    local targetPos  = net.ReadVector()
    local firstShot  = net.ReadBool()
    local entIdx     = net.ReadUInt(16)

    -- Muzzle flash effect at firing point
    local flash = EffectData()
    flash:SetOrigin(src)
    flash:SetNormal(dir)
    flash:SetAngles(dir:Angle())
    util.Effect("MuzzleEffect", flash)

    -- Tracer line from muzzle to intercept
    local tracer = EffectData()
    tracer:SetStart(src)
    tracer:SetOrigin(targetPos)
    tracer:SetScale(5000)
    util.Effect("Tracer", tracer)

    -- On first pulse: snap laser beam to intercept point for 80ms
    if firstShot then
        _GekkoAPS_Lasers[entIdx] = {
            src     = src,
            dst     = targetPos,
            dieTime = CurTime() + 0.08,
        }
    end
end)

-- ============================================================
-- RENDER: draw all active laser beams
-- ============================================================
hook.Add("PostDrawTranslucentRenderables", "GekkoAPS_DrawLasers", function()
    local now = CurTime()
    for idx, beam in pairs(_GekkoAPS_Lasers) do
        if now > beam.dieTime then
            _GekkoAPS_Lasers[idx] = nil
        else
            -- Fade out only in the last 30ms so it feels sharp
            local frac  = math.max(0, (beam.dieTime - now) / 0.03)
            local alpha = math.min(230, LASER_COLOR.a * frac)
            render.SetMaterial(LASER_MAT)
            render.DrawBeam(
                beam.src,
                beam.dst,
                LASER_WIDTH,
                0, 1,
                ColorAlpha(LASER_COLOR, alpha)
            )
        end
    end
end)