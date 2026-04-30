if SERVER then return end

local TRAIL_MAT = Material("decals/trail")

function EFFECT:Init(data)
    local pos    = data:GetOrigin()
    local normal = data:GetNormal()
    local scale  = math.max(data:GetScale(), 1)
    local mag    = math.max(data:GetMagnitude(), 1)

    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end

    local count = math.max(1, math.floor(scale * 0.8))

    for _ = 1, count do
        local particle = emitter:Add(TRAIL_MAT, pos)
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
            particle:SetStartLength(4 * 0.4)
            particle:SetEndLength(80 * 0.4)
            particle:SetGravity(Vector(0, 0, -1050))
            particle:SetCollide(true)
            particle:SetCollideCallback(function(_, cpos, cnormal)
                util.Decal("Blood", cpos + cnormal, cpos - cnormal)
            end)
        end
    end

    emitter:Finish()
end

function EFFECT:Think()  return false end
function EFFECT:Render() end
