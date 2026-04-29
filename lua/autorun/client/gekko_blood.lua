-- ============================================================
--  lua/autorun/client/gekko_blood.lua
--  Standalone blood system for npc_vj_gekko.
--  Receives "GekkoBloodHit" net message from server autorun.
-- ============================================================
if SERVER then return end

-- "decals/trail" is a sprite-compatible reddish trail material
-- confirmed working by the original Hemo fluid stream mod.
-- particle/blood1-4 are HL2 blood drop sprites.
local STREAM_MAT = "decals/trail"
local BURST_MATS = {
    "particle/blood1",
    "particle/blood2",
    "particle/blood3",
    "particle/blood4",
}

local BR, BG, BB = 200, 0, 0
local GRAVITY    = Vector(0, 0, -800)

-- Correct GMod SetCollideCallback signature: function(particle, pos, normal)
-- pos is a Vector with the hit position, normal is the surface normal.
local function BloodDecal(pos, normal)
    util.Decal("Blood", pos + normal, pos - normal * 4)
end

local function RandBurst() return BURST_MATS[math.random(#BURST_MATS)] end

-- Generic spray helper
local function SpawnBlood(origin, mat, count, spd_min, spd_max, die_min, die_max, dir_fn)
    local emitter = ParticleEmitter(origin, false)
    if not emitter then return end
    for _ = 1, count do
        local p = emitter:Add(mat, origin)
        if p then
            p:SetVelocity(dir_fn() * math.Rand(spd_min, spd_max))
            p:SetGravity(GRAVITY)
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(die_min, die_max))
            p:SetStartAlpha(240)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(4, 12))
            p:SetEndSize(0)
            p:SetColor(BR, BG, BB)
            p:SetRoll(math.Rand(0, 360))
            p:SetCollide(true)
            -- Correct signature: (particle, pos, normal)
            p:SetCollideCallback(function(ptcl, pos, normal)
                BloodDecal(pos, normal)
            end)
        end
    end
    emitter:Finish()
end

-- ============================================================
--  VARIANT 0 - HemoStream: sustained drip for 12 seconds
-- ============================================================
local function Blood_HemoStream(ent)
    local tname = "gkblood_" .. ent:EntIndex()
    timer.Remove(tname)
    local endT = CurTime() + 12
    timer.Create(tname, 0.05, 0, function()
        if not IsValid(ent) or CurTime() > endT then
            timer.Remove(tname)
            return
        end
        local origin = ent:GetPos() + Vector(0, 0, 72)
        local fwd    = ent:GetForward()
        local emitter = ParticleEmitter(origin, false)
        if not emitter then return end

        -- Main jet
        local p = emitter:Add(STREAM_MAT, origin)
        if p then
            local spread = Vector((math.random()-0.5)*0.5,(math.random()-0.5)*0.5,(math.random()-0.5)*0.3)
            p:SetVelocity((fwd + spread) * math.Rand(50, 120))
            p:SetGravity(Vector(0, 0, -280))
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.25, 0.65))
            p:SetStartAlpha(240)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(5, 14))
            p:SetEndSize(math.Rand(1, 4))
            p:SetStartLength(math.Rand(2, 8))
            p:SetEndLength(math.Rand(8, 22))
            p:SetColor(BR, BG, BB)
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-3, 3))
            p:SetCollide(true)
            p:SetCollideCallback(function(ptcl, pos, normal)
                BloodDecal(pos, normal)
            end)
        end

        -- Secondary drip
        if math.random() < 0.4 then
            local dp = emitter:Add(STREAM_MAT,
                origin + Vector((math.random()-0.5)*6,(math.random()-0.5)*6, 0))
            if dp then
                dp:SetVelocity(Vector((math.random()-0.5)*20,(math.random()-0.5)*20,-math.Rand(10,35)))
                dp:SetGravity(Vector(0, 0, -220))
                dp:SetLifeTime(0)
                dp:SetDieTime(math.Rand(0.4, 1.0))
                dp:SetStartAlpha(200)
                dp:SetEndAlpha(0)
                dp:SetStartSize(math.Rand(3, 9))
                dp:SetEndSize(0)
                dp:SetColor(BR, BG, BB)
                dp:SetRoll(math.Rand(0, 360))
                dp:SetCollide(true)
                dp:SetCollideCallback(function(ptcl, pos, normal)
                    BloodDecal(pos, normal)
                end)
            end
        end
        emitter:Finish()
    end)
end

-- ============================================================
--  VARIANT 1 - Geyser: upward burst
-- ============================================================
local function Blood_Geyser(origin)
    SpawnBlood(origin, RandBurst(), math.random(22, 38), 90, 320, 0.4, 1.3, function()
        return Vector(
            (math.random()-0.5) * 0.7,
            (math.random()-0.5) * 0.7,
            math.Rand(0.6, 1.0)
        ):GetNormalized()
    end)
end

-- ============================================================
--  VARIANT 2 - RadialRing: 360 horizontal ring
-- ============================================================
local function Blood_RadialRing(origin)
    local count = math.random(24, 40)
    local emitter = ParticleEmitter(origin, false)
    if not emitter then return end
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local p = emitter:Add(RandBurst(), origin)
        if p then
            local dir = Vector(math.cos(angle), math.sin(angle), math.Rand(-0.1, 0.35)):GetNormalized()
            p:SetVelocity(dir * math.Rand(180, 480))
            p:SetGravity(GRAVITY)
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.5, 1.1))
            p:SetStartAlpha(245)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(6, 14))
            p:SetEndSize(0)
            p:SetColor(BR, BG, BB)
            p:SetRoll(math.Rand(0, 360))
            p:SetCollide(true)
            p:SetCollideCallback(function(ptcl, pos, normal)
                BloodDecal(pos, normal)
            end)
        end
    end
    emitter:Finish()
end

-- ============================================================
--  VARIANT 3 - BurstCloud: omnidirectional
-- ============================================================
local function Blood_BurstCloud(origin)
    SpawnBlood(origin, RandBurst(), math.random(32, 52), 140, 420, 0.4, 1.0, function()
        return Vector(
            (math.random()-0.5) * 2,
            (math.random()-0.5) * 2,
            (math.random()-0.5) * 2
        ):GetNormalized()
    end)
end

-- ============================================================
--  VARIANT 4 - ArcShower: forward-biased arc
-- ============================================================
local function Blood_ArcShower(origin, forward)
    SpawnBlood(origin, RandBurst(), math.random(28, 48), 180, 580, 0.4, 1.0, function()
        return (forward + Vector(
            (math.random()-0.5) * 0.8,
            (math.random()-0.5) * 0.8,
            math.Rand(0.2, 0.7)
        )):GetNormalized()
    end)
end

-- ============================================================
--  VARIANT 5 - GroundPool: low horizontal spread
-- ============================================================
local function Blood_GroundPool(origin)
    SpawnBlood(
        origin + Vector(0, 0, 10),
        RandBurst(),
        math.random(22, 40), 80, 280, 0.35, 0.9,
        function()
            local a = math.Rand(0, math.pi * 2)
            return Vector(math.cos(a), math.sin(a), math.Rand(-0.05, 0.2)):GetNormalized()
        end
    )
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
