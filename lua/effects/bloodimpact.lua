-- ============================================================
--  bloodimpact.lua  (addon override)
--  Replaces GMod's default BloodImpact effect.
--  Uses decals/trail — confirmed rendering correctly on this
--  system. Burst of particles at impact point.
-- ============================================================
if SERVER then return end

local BLOOD_MAT = Material("decals/trail")
local DECAL_MATS = {
    Material("decals/Blood1"),
    Material("decals/Blood2"),
    Material("decals/Blood3"),
    Material("decals/Blood4"),
    Material("decals/Blood5"),
    Material("decals/Blood6"),
}

function EFFECT:Init(data)
    local pos    = data:GetOrigin()
    local normal = data:GetNormal()
    local scale  = math.max(data:GetScale(), 1)
    local mag    = math.max(data:GetMagnitude(), 1)

    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end

    local count = math.max(1, math.floor(scale * 0.8))

    for _ = 1, count do
        local particle = emitter:Add(BLOOD_MAT, pos)
        if particle then
            local dir = Vector(
                (math.random() - 0.5) * 2,
                (math.random() - 0.5) * 2,
                math.Rand(0.2, 1.0)
            ):GetNormalized()

            local speed = mag * math.Rand(20, 50)

            particle:SetVelocity(dir * speed)
            particle:SetDieTime(math.Rand(0.8, 2.5))
            particle:SetStartSize(math.Rand(2.0, 4.5) * 0.4)
            particle:SetEndSize(0)
            particle:SetStartLength(4  * 0.4)
            particle:SetEndLength(80 * 0.4)
            particle:SetGravity(Vector(0, 0, -1050))
            particle:SetCollide(true)
            particle:SetCollideCallback(function(_, cpos, cnormal)
                util.DecalEx(
                    DECAL_MATS[math.random(#DECAL_MATS)],
                    Entity(0), cpos, cnormal,
                    Color(255, 255, 255), 0.15, 0.15
                )
            end)
        end
    end

    emitter:Finish()
end

function EFFECT:Think()  return false end
function EFFECT:Render() end
