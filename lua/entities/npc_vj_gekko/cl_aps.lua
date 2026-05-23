-- ============================================================
-- npc_vj_gekko / cl_aps.lua
-- CLIENT  —  APS visual receivers
--
-- FIXES v3.3:
--   FIX 3: Both net receivers now correctly read the entity index
--     UInt(16) that the server writes. Previously this was read
--     but never written on the server side, silently corrupting
--     all subsequent net reads on those messages.
--   FIX 2: Laser beam is now only visible when GekkoAPSLaser is
--     received (which only fires just before interception). During
--     outer tracking the laser is silent. Beam fades out 120ms
--     after the last message, same as before.
--   FIX 4: GekkoAPSIntercept dir vector now points at the
--     intercept position (set correctly by server), so
--     MuzzleEffect faces the target instead of world origin.
-- ============================================================

if SERVER then return end

-- ============================================================
-- LASER STATE
-- _GekkoAPS_Lasers[entIndex] = { src, dst, dieTime }
-- ============================================================
_GekkoAPS_Lasers = _GekkoAPS_Lasers or {}

local LASER_MAT   = Material("effects/laser1")
local LASER_COLOR = Color(255, 30, 30, 230)
local LASER_WIDTH = 6
local LASER_TTL   = 0.12   -- 120ms persistence per tick

-- ============================================================
-- NET: GekkoAPSLaser
-- Sent only when a threat is inside intercept radius.
-- FIX 3: now reads entity index written by server.
-- ============================================================
net.Receive("GekkoAPSLaser", function()
    local src    = net.ReadVector()
    local dst    = net.ReadVector()
    local entIdx = net.ReadUInt(16)   -- FIX 3: server now writes this

    _GekkoAPS_Lasers[entIdx] = {
        src     = src,
        dst     = dst,
        dieTime = CurTime() + LASER_TTL,
    }
end)

-- ============================================================
-- NET: GekkoAPSIntercept
-- Burst muzzle flash + tracer per pulse.
-- FIX 3: reads entity index.
-- FIX 4: dir now correctly faces interceptPos (set by server).
-- ============================================================
net.Receive("GekkoAPSIntercept", function()
    local src       = net.ReadVector()
    local dir       = net.ReadVector()   -- FIX 4: server now sends correct dir
    local targetPos = net.ReadVector()
    local firstShot = net.ReadBool()
    local entIdx    = net.ReadUInt(16)   -- FIX 3: server now writes this

    -- Muzzle flash at firing point, aimed at intercept
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

    -- On first pulse: snap laser to intercept point for 80ms
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
            -- Fade in the last 30ms
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
