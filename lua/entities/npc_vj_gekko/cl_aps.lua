-- ============================================================
-- npc_vj_gekko / cl_aps.lua
-- CLIENT  —  APS visual receivers  v5
--
-- FIXES v5:
--   1. LASER FADE MATH: alpha divisor was hardcoded 0.03 instead
--      of LASER_TTL, causing frac to blow up to ~4x the intended
--      value and rendering the beam as a solid blinding line.
--      Now: frac = (dieTime - now) / LASER_TTL, clamped 0-1.
--   2. INTERCEPT FLASH: MuzzleEffect scale was unset (defaults to
--      0, rendering nothing). Now set to 2.0 for a punchy flash.
--   3. TRACER: Scale moved from 5000 (HL2 tracers ignore it) to
--      Magnitude=1 so the particle doesn't stretch endlessly.
-- ============================================================

if SERVER then return end

-- ============================================================
-- LASER STATE TABLE
-- _GekkoAPS_Lasers[entIndex] = { src, dst, dieTime }
-- ============================================================
_GekkoAPS_Lasers = _GekkoAPS_Lasers or {}

local LASER_MAT   = Material("effects/laser1")
local LASER_COLOR = Color(255, 30, 30, 230)
local LASER_WIDTH = 6
local LASER_TTL   = 0.12   -- 120 ms per tick (covers 50 ms scan interval)

-- ============================================================
-- NET: GekkoAPSLaser — refresh beam entry
-- ============================================================
net.Receive("GekkoAPSLaser", function()
    local src    = net.ReadVector()
    local dst    = net.ReadVector()
    local entIdx = net.ReadUInt(16)

    _GekkoAPS_Lasers[entIdx] = {
        src     = src,
        dst     = dst,
        dieTime = CurTime() + LASER_TTL,
    }
end)

-- ============================================================
-- NET: GekkoAPSLaserClear — hard-kill beam (death / lost lock)
-- ============================================================
net.Receive("GekkoAPSLaserClear", function()
    local entIdx = net.ReadUInt(16)
    _GekkoAPS_Lasers[entIdx] = nil
end)

-- ============================================================
-- NET: GekkoAPSIntercept — burst muzzle flash + tracer
-- ============================================================
net.Receive("GekkoAPSIntercept", function()
    local src       = net.ReadVector()
    local dir       = net.ReadVector()
    local targetPos = net.ReadVector()
    local firstShot = net.ReadBool()
    local entIdx    = net.ReadUInt(16)

    -- Muzzle flash at firing point
    local flash = EffectData()
    flash:SetOrigin(src)
    flash:SetNormal(dir)
    flash:SetAngles(dir:Angle())
    flash:SetScale(2.0)   -- FIX: was unset (0), nothing rendered
    util.Effect("MuzzleEffect", flash)

    -- Tracer from muzzle to intercept point
    local tracer = EffectData()
    tracer:SetStart(src)
    tracer:SetOrigin(targetPos)
    tracer:SetMagnitude(1)   -- FIX: Scale=5000 had no effect; Magnitude drives particle size
    util.Effect("Tracer", tracer)

    -- First pulse only: snap laser to intercept point for 80 ms
    if firstShot then
        _GekkoAPS_Lasers[entIdx] = {
            src     = src,
            dst     = targetPos,
            dieTime = CurTime() + 0.08,
        }
    end
end)

-- ============================================================
-- RENDER: draw all live laser beams, expire stale entries
-- ============================================================
hook.Add("PostDrawTranslucentRenderables", "GekkoAPS_DrawLasers", function()
    local now = CurTime()
    for idx, beam in pairs(_GekkoAPS_Lasers) do
        if now > beam.dieTime then
            _GekkoAPS_Lasers[idx] = nil
        else
            -- FIX: was dividing by 0.03 (hardcoded) instead of LASER_TTL,
            -- making frac >> 1 for newly-created beams and blowing out alpha.
            local frac  = math.Clamp((beam.dieTime - now) / LASER_TTL, 0, 1)
            local alpha = LASER_COLOR.a * frac
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
