-- ============================================================
--  VJ_GekkoMuzzle_Rocket  —  Gekko rocket-pod muzzle flash
--
--  Uses only textures already present in the mod:
--    "particles/flamelet1-5"       (orange flame core)
--    "particle/particle_smokegrenade"  (smoke ring)
--    "effects/spark"               (hot sparks)
-- ============================================================

function EFFECT:Init( data )
    local origin = data:GetOrigin()
    local normal = data:GetNormal()
    local scale  = data:GetScale()

    -- ── Dynamic light pop (orange, fast decay) ────────────────
    local dlight = DynamicLight(0)
    if dlight then
        dlight.pos        = origin
        dlight.r          = 255
        dlight.g          = 120
        dlight.b          = 20
        dlight.brightness = 3 * scale
        dlight.Size       = 200 * scale
        dlight.Decay      = 1800
        dlight.DieTime    = CurTime() + 0.12
    end

    local emitter = ParticleEmitter(origin, false)
    if not IsValid(emitter) then return end

    -- ── Orange flame core (flamelet1-5, matches Nikita exhaust) ──
    for i = 1, 5 do
        local p = emitter:Add(
            "particles/flamelet" .. math.random(1, 5),
            origin + VectorRand() * (5 * scale)
        )
        if p then
            p:SetVelocity(normal * math.Rand(80, 180) + VectorRand() * (20 * scale))
            p:SetDieTime(math.Rand(0.06, 0.14))
            p:SetStartAlpha(230)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(20, 36) * scale)
            p:SetEndSize(math.Rand(5, 14) * scale)
            p:SetColor(255, math.random(100, 180), 0)
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-3, 3))
            p:SetGravity(Vector(0, 0, 10))
            p:SetCollide(false)
            p:SetLighting(false)
        end
    end

    -- ── Smoke ring — 3 radial puffs (particle_smokegrenade) ──────
    local right = normal:Cross(Vector(0, 0, 1)):GetNormalized()
    if right:LengthSqr() < 0.01 then right = normal:Cross(Vector(0, 1, 0)):GetNormalized() end
    local up = right:Cross(normal):GetNormalized()

    for i = 0, 2 do
        local angle  = (i / 3) * math.pi * 2
        local offset = (right * math.cos(angle) + up * math.sin(angle)) * (14 * scale)
        local p = emitter:Add(
            "particle/particle_smokegrenade",
            origin + offset
        )
        if p then
            p:SetVelocity(normal * math.Rand(30, 65) + offset:GetNormalized() * 30)
            p:SetDieTime(math.Rand(0.22, 0.50))
            p:SetStartAlpha(150)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(12, 22) * scale)
            p:SetEndSize(math.Rand(45, 80) * scale)
            p:SetColor(200, 190, 160)
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-1.5, 1.5))
            p:SetGravity(Vector(0, 0, 18))
            p:SetCollide(false)
        end
    end

    -- ── Sparks (effects/spark, matches Nikita exhaust sparks) ────
    for i = 1, 4 do
        local p = emitter:Add(
            "effects/spark",
            origin + VectorRand() * (3 * scale)
        )
        if p then
            p:SetVelocity(normal * math.Rand(300, 700) + VectorRand() * (60 * scale))
            p:SetDieTime(math.Rand(0.10, 0.28))
            p:SetStartAlpha(255)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(1, 3))
            p:SetEndSize(0)
            p:SetColor(255, 230, 180)
            p:SetGravity(Vector(0, 0, -280))
            p:SetCollide(true)
            p:SetBounce(0.2)
        end
    end

    emitter:Finish()
end

function EFFECT:Think()  return false  end
function EFFECT:Render() end
