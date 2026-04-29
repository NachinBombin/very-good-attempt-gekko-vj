-- ============================================================
--  lua/effects/gekko_bloodstream.lua
--  Standalone blood stream effect for npc_vj_gekko.
--  Called by cl_init BloodVariant_HemoStream with the NPC entity.
--  Emits a sustained blood stream from the NPC torso for ~12s.
-- ============================================================

local EFFECT = {}

-- Torso bone candidates in priority order
local TORSO_BONES = { "b_spine4", "b_spine3", "b_spine2", "b_spine1", "ValveBiped.Bip01_Spine4" }

local STREAM_LIFETIME  = 12
local STREAM_RATE      = 0.05
local PARTICLE_SCALE   = 0.4
local SPEED_MIN        = 35
local SPEED_MAX        = 95
local GRAVITY          = Vector(0, 0, -220)
local DRIP_CHANCE      = 0.3
local R, G, B          = 175, 8, 8

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    -- Find best torso bone, fallback to a body-height offset
    local boneIdx = -1
    for _, bname in ipairs(TORSO_BONES) do
        local idx = ent:LookupBone(bname)
        if idx and idx >= 0 then boneIdx = idx break end
    end

    local timername = "gkbs_" .. tostring(ent:EntIndex()) .. "_" .. tostring(math.floor(CurTime() * 1000))
    self._timer = timername
    self._ent   = ent
    self._end   = CurTime() + STREAM_LIFETIME
    self._bone  = boneIdx

    timer.Create(timername, STREAM_RATE, math.ceil(STREAM_LIFETIME / STREAM_RATE), function()
        if not IsValid(ent) or CurTime() > self._end then
            timer.Remove(timername)
            return
        end

        -- Stream origin: bone position if available, else torso height
        local origin
        if boneIdx >= 0 then
            local bp = ent:GetBonePosition(boneIdx)
            origin = bp or (ent:GetPos() + Vector(0, 0, 90))
        else
            origin = ent:GetPos() + Vector(
                (math.random() - 0.5) * 20,
                (math.random() - 0.5) * 20,
                70 + (math.random() - 0.5) * 40
            )
        end

        local forward = ent:GetForward()

        -- Main blood jet
        local emitter = ParticleEmitter(origin, false)
        if emitter then
            local p = emitter:Add("effects/blood", origin)
            if p then
                local spread = Vector(
                    (math.random() - 0.5) * 0.5,
                    (math.random() - 0.5) * 0.5,
                    (math.random() - 0.5) * 0.3
                )
                p:SetVelocity((forward + spread) * math.Rand(SPEED_MIN, SPEED_MAX))
                p:SetGravity(GRAVITY)
                p:SetLifeTime(0)
                p:SetDieTime(math.Rand(0.25, 0.6))
                p:SetStartAlpha(230)
                p:SetEndAlpha(0)
                p:SetStartSize(PARTICLE_SCALE * math.Rand(7, 16))
                p:SetEndSize(PARTICLE_SCALE * math.Rand(2, 6))
                p:SetColor(R, G, B)
                p:SetRoll(math.Rand(0, 360))
                p:SetRollDelta(math.Rand(-3, 3))
                p:SetCollide(true)
                p:SetCollideCallback(function(norm, cp)
                    util.Decal("Blood", cp:GetPos() + norm * 2, cp:GetPos() - norm * 4)
                end)
            end

            -- Secondary mist particle
            local p2 = emitter:Add("effects/blood2", origin + Vector((math.random()-0.5)*4,(math.random()-0.5)*4,0))
            if p2 then
                p2:SetVelocity(Vector(
                    (math.random()-0.5)*SPEED_MIN,
                    (math.random()-0.5)*SPEED_MIN,
                    math.Rand(10, 30)
                ))
                p2:SetGravity(GRAVITY * 0.6)
                p2:SetLifeTime(0)
                p2:SetDieTime(math.Rand(0.15, 0.4))
                p2:SetStartAlpha(160)
                p2:SetEndAlpha(0)
                p2:SetStartSize(PARTICLE_SCALE * math.Rand(3, 8))
                p2:SetEndSize(0)
                p2:SetColor(R, G, B)
                p2:SetRoll(math.Rand(0, 360))
            end

            emitter:Finish()
        end

        -- Occasional drip
        if math.random() < DRIP_CHANCE then
            local de = ParticleEmitter(origin, false)
            if de then
                local dp = de:Add("effects/blood", origin)
                if dp then
                    dp:SetVelocity(Vector(
                        (math.random()-0.5)*18,
                        (math.random()-0.5)*18,
                        -math.Rand(10, 30)
                    ))
                    dp:SetGravity(GRAVITY)
                    dp:SetLifeTime(0)
                    dp:SetDieTime(math.Rand(0.4, 1.0))
                    dp:SetStartAlpha(200)
                    dp:SetEndAlpha(0)
                    dp:SetStartSize(PARTICLE_SCALE * math.Rand(4, 9))
                    dp:SetEndSize(0)
                    dp:SetColor(R, G, B)
                    dp:SetRoll(math.Rand(0, 360))
                    dp:SetCollide(true)
                    dp:SetCollideCallback(function(norm, cp)
                        util.Decal("Blood", cp:GetPos() + norm * 2, cp:GetPos() - norm * 4)
                    end)
                end
                de:Finish()
            end
        end
    end)
end

function EFFECT:Think()
    if not IsValid(self._ent) or CurTime() > (self._end or 0) then
        if self._timer then timer.Remove(self._timer) end
        return false
    end
    return true
end

function EFFECT:Render() end

effects.Register(EFFECT, "gekko_bloodstream")
