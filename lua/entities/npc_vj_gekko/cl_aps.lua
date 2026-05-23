-- ============================================================
-- npc_vj_gekko / cl_aps.lua
-- CLIENT  —  APS visual receivers  v4
--
-- Net messages handled:
--   GekkoAPSLaser      — tracking beam while locked
--   GekkoAPSLaserClear — immediate beam kill (death / lost lock)
--   GekkoAPSIntercept  — burst muzzle flash + tracer
--
-- All state is keyed by server entity index so multiple Gekkos
-- are fully independent.
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
local LASER_TTL   = 0.12   -- 120ms per tick (covers 50ms scan interval)

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
-- NET: GekkoAPSIntercept — burst pulse
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
    util.Effect("MuzzleEffect", flash)

    -- Tracer line muzzle → intercept
    local tracer = EffectData()
    tracer:SetStart(src)
    tracer:SetOrigin(targetPos)
    tracer:SetScale(5000)
    util.Effect("Tracer", tracer)

    -- First pulse only: snap laser to intercept point for 80ms
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
