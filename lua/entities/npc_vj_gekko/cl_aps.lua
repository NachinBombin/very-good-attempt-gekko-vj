-- ============================================================
-- npc_vj_gekko / cl_aps.lua
-- CLIENT  —  APS visual receivers
--
-- v4.7 CHANGES:
--   NEW — Dual laser beams.
--     GekkoAPSLaser now carries a 4-bit slot index (0 or 1).
--     Beam table key is  entIndex .. "_" .. slotIndex  so two
--     independent beams per Gekko never overwrite each other.
--   FIX — Burst sound guaranteed 1 second (server-side fix;
--     no client change required for that fix).
-- ============================================================

if SERVER then return end

-- ============================================================
-- LASER STATE
-- _GekkoAPS_Lasers[key] = { src, dst, dieTime }
-- key = tostring(entIndex) .. "_" .. tostring(slotIndex)
-- Supports up to APS_MAX_LOCK_SLOTS=2 simultaneous beams per
-- Gekko without one beam overwriting the other.
-- ============================================================
_GekkoAPS_Lasers = _GekkoAPS_Lasers or {}

local LASER_MAT   = Material("effects/laser1")
local LASER_COLOR = Color(255, 30, 30, 230)
local LASER_WIDTH = 6
local LASER_TTL   = 0.12   -- 120ms persistence per tick

-- ============================================================
-- NET: GekkoAPSLaser
-- Sent each think tick while a threat is being tracked.
-- Carries a 4-bit slotIndex so two independent beams can
-- coexist without overwriting each other in the table.
-- ============================================================
net.Receive("GekkoAPSLaser", function()
    local src      = net.ReadVector()
    local dst      = net.ReadVector()
    local entIdx   = net.ReadUInt(16)
    local slotIdx  = net.ReadUInt(4)

    local key = tostring(entIdx) .. "_" .. tostring(slotIdx)
    _GekkoAPS_Lasers[key] = {
        src     = src,
        dst     = dst,
        dieTime = CurTime() + LASER_TTL,
    }
end)

-- ============================================================
-- NET: GekkoAPSIntercept
-- Burst muzzle flash + tracer per pulse.
-- Uses slot 0 beam key for the snap-laser on first shot;
-- that is fine because intercept always fires on a real threat
-- and the laser fades out in 80ms anyway.
-- ============================================================
net.Receive("GekkoAPSIntercept", function()
    local src       = net.ReadVector()
    local dir       = net.ReadVector()
    local targetPos = net.ReadVector()
    local firstShot = net.ReadBool()
    local entIdx    = net.ReadUInt(16)

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

    -- On first pulse: snap laser slot 0 to intercept point for 80ms
    if firstShot then
        local key = tostring(entIdx) .. "_0"
        _GekkoAPS_Lasers[key] = {
            src     = src,
            dst     = targetPos,
            dieTime = CurTime() + 0.08,
        }
    end
end)

-- ============================================================
-- RENDER: draw all active laser beams
-- Each key is independent; two beams from the same Gekko have
-- different keys and are rendered without interfering.
-- ============================================================
hook.Add("PostDrawTranslucentRenderables", "GekkoAPS_DrawLasers", function()
    local now = CurTime()
    for key, beam in pairs(_GekkoAPS_Lasers) do
        if now > beam.dieTime then
            _GekkoAPS_Lasers[key] = nil
        else
            -- Fade out in the last 30ms
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
