-- ============================================================
--  bloodspray.lua  (addon override)
--  Replaces GMod's default BloodSpray effect.
--  Uses decals/trail — confirmed rendering correctly on this
--  system. Same pattern as gekko_bloodstream.
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

    local count = math.max(1, math.floor(scale * 0.5))

    for _ = 1, count do
        local particle = emitter:Add(BLOOD_MAT, pos)
        if particle then
            local spread = Vector(
                (math.random() - 0.5) * 0.7,
                (math.random() - 0.5) * 0.7,
                (math.random() - 0.5) * 0.3
            )
            local dir   = (normal + spread):GetNormalized()
            local speed = mag * math.Rand(25, 65)

            particle:SetVelocity(dir * speed)
            particle:SetDieTime(math.Rand(1.5, 3.5))
            particle:SetStartSize(math.Rand(1.5, 3.5) * 0.4)
            particle:SetEndSize(0)
            particle:SetStartLength(4  * 0.4)
            particle:SetEndLength(100 * 0.4)
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
