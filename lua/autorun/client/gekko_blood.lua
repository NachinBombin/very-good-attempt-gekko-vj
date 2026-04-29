-- ============================================================
--  lua/autorun/client/gekko_blood.lua
--  Standalone client blood system for npc_vj_gekko.
--  Receives "GekkoBloodHit" net message from init.lua.
--  Completely independent of cl_init.lua.
-- ============================================================
if SERVER then return end

local BLOOD_MATS = {
    "effects/blood",
    "effects/blood2",
    "effects/blood3",
    "effects/blood4",
}
local BR, BG, BB = 175, 8, 8
local GRAVITY    = Vector(0, 0, -600)

-- Shared helper: spawn count particles from origin using a direction factory
local function SpawnBlood(origin, count, speed_min, speed_max, die_min, die_max, dir_fn)
    local emitter = ParticleEmitter(origin, false)
    if not emitter then return end
    for _ = 1, count do
        local p = emitter:Add(BLOOD_MATS[math.random(#BLOOD_MATS)], origin)
        if p then
            p:SetVelocity(dir_fn() * math.Rand(speed_min, speed_max))
            p:SetGravity(GRAVITY)
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(die_min, die_max))
            p:SetStartAlpha(240)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(4, 14))
            p:SetEndSize(0)
            p:SetColor(BR, BG, BB)
            p:SetRoll(math.Rand(0, 360))
            p:SetCollide(true)
            p:SetCollideCallback(function(norm, cp)
                util.Decal("Blood", cp:GetPos() + norm, cp:GetPos() - norm * 4)
            end)
        end
    end
    emitter:Finish()
end

-- ============================================================
--  VARIANT 0 — Sustained blood stream (12 seconds)
-- ============================================================
local function Blood_HemoStream(ent)
    local timerName = "gkblood_stream_" .. ent:EntIndex()
    timer.Remove(timerName)
    local endTime = CurTime() + 12
    timer.Create(timerName, 0.05, 0, function()
        if not IsValid(ent) or CurTime() > endTime then
            timer.Remove(timerName)
            return
        end
        local origin = ent:GetPos() + Vector(0, 0, 72)
        local fwd    = ent:GetForward()
        local emitter = ParticleEmitter(origin, false)
        if not emitter then return end
        local p = emitter:Add(BLOOD_MATS[math.random(#BLOOD_MATS)], origin)
        if p then
            local spread = Vector((math.random()-0.5)*0.45,(math.random()-0.5)*0.45,(math.random()-0.5)*0.3)
            p:SetVelocity((fwd + spread) * math.Rand(40, 110))
            p:SetGravity(Vector(0, 0, -250))
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.25, 0.65))
            p:SetStartAlpha(235)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(5, 15))
            p:SetEndSize(math.Rand(1, 4))
            p:SetColor(BR, BG, BB)
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-3, 3))
            p:SetCollide(true)
            p:SetCollideCallback(function(norm, cp)
                util.Decal("Blood", cp:GetPos() + norm, cp:GetPos() - norm * 4)
            end)
        end
        -- secondary drip
        if math.random() < 0.35 then
            local dp = emitter:Add(BLOOD_MATS[math.random(#BLOOD_MATS)],
                origin + Vector((math.random()-0.5)*4,(math.random()-0.5)*4,0))
            if dp then
                dp:SetVelocity(Vector((math.random()-0.5)*18,(math.random()-0.5)*18,-math.Rand(10,30)))
                dp:SetGravity(Vector(0,0,-200))
                dp:SetLifeTime(0)
                dp:SetDieTime(math.Rand(0.4, 1.0))
                dp:SetStartAlpha(200)
                dp:SetEndAlpha(0)
                dp:SetStartSize(math.Rand(3, 9))
                dp:SetEndSize(0)
                dp:SetColor(BR, BG, BB)
                dp:SetRoll(math.Rand(0, 360))
                dp:SetCollide(true)
                dp:SetCollideCallback(function(norm, cp)
                    util.Decal("Blood", cp:GetPos() + norm, cp:GetPos() - norm * 4)
                end)
            end
        end
        emitter:Finish()
    end)
end

-- ============================================================
--  VARIANT 1 — Geyser (upward burst)
-- ============================================================
local function Blood_Geyser(origin)
    SpawnBlood(origin, math.random(22, 38), 90, 320, 0.4, 1.3, function()
        return Vector(
            (math.random()-0.5) * 0.7,
            (math.random()-0.5) * 0.7,
            math.Rand(0.6, 1.0)
        ):GetNormalized()
    end)
end

-- ============================================================
--  VARIANT 2 — Radial ring (360 horizontal)
-- ============================================================
local function Blood_RadialRing(origin)
    local count = math.random(24, 40)
    local emitter = ParticleEmitter(origin, false)
    if not emitter then return end
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local p = emitter:Add(BLOOD_MATS[math.random(#BLOOD_MATS)], origin)
        if p then
            local dir = Vector(math.cos(angle), math.sin(angle), math.Rand(-0.1, 0.4)):GetNormalized()
            p:SetVelocity(dir * math.Rand(180, 480))
            p:SetGravity(GRAVITY)
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.5, 1.1))
            p:SetStartAlpha(245)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(6, 15))
            p:SetEndSize(0)
            p:SetColor(BR, BG, BB)
            p:SetRoll(math.Rand(0, 360))
            p:SetCollide(true)
            p:SetCollideCallback(function(norm, cp)
                util.Decal("Blood", cp:GetPos() + norm, cp:GetPos() - norm * 4)
            end)
        end
    end
    emitter:Finish()
end

-- ============================================================
--  VARIANT 3 — Burst cloud (omnidirectional)
-- ============================================================
local function Blood_BurstCloud(origin)
    SpawnBlood(origin, math.random(32, 52), 140, 420, 0.4, 1.0, function()
        return Vector(
            (math.random()-0.5) * 2,
            (math.random()-0.5) * 2,
            (math.random()-0.5) * 2
        ):GetNormalized()
    end)
end

-- ============================================================
--  VARIANT 4 — Arc shower (forward-biased)
-- ============================================================
local function Blood_ArcShower(origin, forward)
    SpawnBlood(origin, math.random(28, 48), 180, 580, 0.4, 1.0, function()
        return (forward + Vector(
            (math.random()-0.5) * 0.8,
            (math.random()-0.5) * 0.8,
            math.Rand(0.2, 0.7)
        )):GetNormalized()
    end)
end

-- ============================================================
--  VARIANT 5 — Ground pool (low horizontal spread)
-- ============================================================
local function Blood_GroundPool(origin)
    SpawnBlood(origin + Vector(0,0,10), math.random(22, 40), 80, 280, 0.35, 0.9, function()
        local a = math.Rand(0, math.pi * 2)
        return Vector(math.cos(a), math.sin(a), math.Rand(-0.05, 0.2)):GetNormalized()
    end)
end

-- ============================================================
--  NET RECEIVER
-- ============================================================
net.Receive("GekkoBloodHit", function()
    local ent     = net.ReadEntity()
    local variant = net.ReadUInt(3)
    if not IsValid(ent) then return end

    local origin  = ent:GetPos() + Vector(0, 0, 60)
    local forward = ent:GetForward()

    if     variant == 0 then Blood_HemoStream(ent)
    elseif variant == 1 then Blood_Geyser(origin)
    elseif variant == 2 then Blood_RadialRing(origin)
    elseif variant == 3 then Blood_BurstCloud(origin)
    elseif variant == 4 then Blood_ArcShower(origin, forward)
    elseif variant == 5 then Blood_GroundPool(origin)
    end
end)
