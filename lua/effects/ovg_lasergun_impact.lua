-- ============================================================
--  ovg_lasergun_impact.lua  (CLIENT)
--  Impact sparks, scorch decal and dynamic flash
-- ============================================================

function EFFECT:Init(data)
    local hitPos    = data:GetOrigin()
    local hitNormal = data:GetNormal()
    local hitWorld  = data:GetFlags() == 1

    if hitWorld then
        util.Decal("FadingScorch", hitPos + hitNormal, hitPos - hitNormal)
    end

    local dl = DynamicLight(0)
    if dl then
        dl.pos        = hitPos + hitNormal * 2
        dl.r          = 0
        dl.g          = 150
        dl.b          = 255
        dl.brightness = 3
        dl.size       = 180
        dl.decay      = 2000
        dl.dietime    = CurTime() + 0.5
        dl.style      = 6
    end

    local emitter = ParticleEmitter(hitPos)
    if emitter then
        for i = 1, 2 do
            local p = emitter:Add("sprites/light_glow02_add", hitPos)
            if p then
                p:SetDieTime(0.12) p:SetStartAlpha(2)   p:SetEndAlpha(0)
                p:SetStartSize(150) p:SetEndSize(0)      p:SetColor(0, 175, 255)
                p:SetRoll(math.random(-180,180))          p:SetVelocity(Vector(0,0,0))
                p:SetCollide(false)
            end
        end
        for i = 1, 12 do
            local p = emitter:Add("effects/spark", hitPos)
            if p then
                local dir = (VectorRand() + hitNormal):GetNormalized()
                p:SetDieTime(0.3)       p:SetStartAlpha(2)      p:SetEndAlpha(0)
                p:SetStartSize(1)       p:SetEndSize(0)
                p:SetStartLength(30)    p:SetEndLength(0)
                p:SetColor(0, 200, 255)
                p:SetVelocity(dir * math.Rand(150, 400))
                p:SetGravity(Vector(0,0,-600))
                p:SetCollide(true)      p:SetBounce(0.4)         p:SetAirResistance(60)
            end
        end
        emitter:Finish()
    end
end

function EFFECT:Think() return false end
function EFFECT:Render() end
