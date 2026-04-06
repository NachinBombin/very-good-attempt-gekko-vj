-- ============================================================
--  npc_vj_gekko / gib_system.lua
--
--  Spawns painted-black metal gib props when the Gekko takes
--  significant damage. Each gib is:
--    * a random model from GEKKO_GIB_MODELS
--    * rendered black via SetColor (opaque, pure black)
--    * launched outward + upward with random spin
--    * removed after GIB_LIFETIME seconds
--
--  On spawn each gib gets:
--    * ElectricSpark + Sparks  (metal strike sparks)
--    * HelicopterMegaBomb explosion flash
--    * Ignite() so it burns visually for GIB_BURN_TIME seconds
--    * ParticleEffect(fire_medium_base) local fire column
-- ============================================================

-- ────────────────────────────────────────────────────────────
--  Tuning
-- ────────────────────────────────────────────────────────────
local GIB_DAMAGE_THRESHOLD = 80   -- minimum single-hit damage to trigger
local GIB_CHANCE           = 0.55  -- probability per qualifying hit (0-1)
local GIB_COUNT_MIN        = 1
local GIB_COUNT_MAX        = 9
local GIB_LIFETIME         = 8.0   -- seconds before auto-remove
local GIB_SPEED_MIN        = 260
local GIB_SPEED_MAX        = 900
local GIB_UP_MIN           = 80
local GIB_UP_MAX           = 340
local GIB_SPIN_SCALE       = 200   -- random angular velocity magnitude
local GIB_MASS             = 18    -- kg
local GIB_COOLDOWN         = 4.0   -- seconds between gib events (spam guard)

-- Spark constants
local SPARK_EFFECT         = "ElectricSpark"
local SPARK_EXTRA          = "Sparks"
local SPARK_COUNT          = 3

-- Fire / explosion constants
-- GIB_EXPLOSION_EFFECT fires a small bright flash at the gib spawn point.
-- GIB_FIRE_PARTICLE    plays a short fire column on the gib itself.
-- GIB_BURN_TIME        how long the gib stays on fire (capped by GIB_LIFETIME).
-- GIB_EXPLODE_CHANCE   not every gib needs the full explosion -- keep it punchy.
local GIB_EXPLOSION_EFFECT = "HelicopterMegaBomb"  -- orange/white blast flash
local GIB_FIRE_PARTICLE    = "fire_medium_base"    -- HL2 fire column particle
local GIB_BURN_TIME        = 5.0                   -- seconds of visible flame
local GIB_EXPLODE_CHANCE   = 0.65                  -- probability per gib

-- ────────────────────────────────────────────────────────────
--  Gib model pool
-- ────────────────────────────────────────────────────────────
local GEKKO_GIB_MODELS = {
    "models/props_c17/playground_swingset_seat01a.mdl",
    "models/Gibs/helicopter_brokenpiece_02.mdl",
    "models/Gibs/helicopter_brokenpiece_03.mdl",
    "models/Gibs/helicopter_brokenpiece_04.mdl",
    "models/Items/item_item_crate_chunk05.mdl",
    "models/mechanics/solid_steel/steel_beam45_3.mdl",
}

if SERVER then
    for _, mdl in ipairs(GEKKO_GIB_MODELS) do
        util.PrecacheModel(mdl)
    end
end

-- ────────────────────────────────────────────────────────────
--  SpawnGibSparks  (electric strike sparks)
-- ────────────────────────────────────────────────────────────
local function SpawnGibSparks(pos, normal)
    for _ = 1, SPARK_COUNT do
        local e = EffectData()
        e:SetOrigin(pos)
        e:SetNormal(normal or Vector(0, 0, 1))
        e:SetMagnitude(math.Rand(0.5, 1))
        e:SetScale(math.Rand(0.3, 1))
        e:SetRadius(math.random(1, 5))
        util.Effect(SPARK_EFFECT, e)
    end

    local e2 = EffectData()
    e2:SetOrigin(pos)
    e2:SetNormal(normal or Vector(0, 0, 1))
    e2:SetMagnitude(math.Rand(0.3, 1))
    e2:SetScale(math.Rand(0.4, 1))
    e2:SetRadius(math.random(5, 12))
    util.Effect(SPARK_EXTRA, e2)
end

-- ────────────────────────────────────────────────────────────
--  SpawnGibFireFX
--  Fires at the gib's position on spawn:
--    1. HelicopterMegaBomb flash (if GIB_EXPLODE_CHANCE passes)
--    2. fire_medium_base particle column on the prop itself
--    3. Ignite() for GIB_BURN_TIME seconds
-- ────────────────────────────────────────────────────────────
local function SpawnGibFireFX(gib, pos, normal)
    -- Explosion flash (probabilistic -- not every chunk, keeps it interesting)
    if math.random() < GIB_EXPLODE_CHANCE then
        local eexp = EffectData()
        eexp:SetOrigin(pos)
        eexp:SetNormal(normal or Vector(0, 0, 1))
        eexp:SetScale(0.4)      -- small -- this is a chunk, not the whole mech
        eexp:SetMagnitude(1)
        eexp:SetRadius(24)
        util.Effect(GIB_EXPLOSION_EFFECT, eexp)
    end

    -- Fire column particle (client-side via ParticleEffect broadcast)
    -- ParticleEffect on server routes to all clients automatically in VJ Base.
    if IsValid(gib) then
        ParticleEffect(GIB_FIRE_PARTICLE, pos, angle_zero, gib)

        -- Ignite the prop so the default flame overlay also shows.
        -- Duration is capped to GIB_LIFETIME so we don't orphan fire.
        local burnDur = math.min(GIB_BURN_TIME, GIB_LIFETIME - 0.5)
        if burnDur > 0 then
            gib:Ignite(burnDur, 0)   -- second arg = 0 = don't use flame damage
        end
    end
end

-- ────────────────────────────────────────────────────────────
--  SpawnSingleGib
-- ────────────────────────────────────────────────────────────
local function SpawnSingleGib(origin, hitNormal)
    local mdl = GEKKO_GIB_MODELS[math.random(#GEKKO_GIB_MODELS)]

    local gib = ents.Create("prop_physics_override")
    if not IsValid(gib) then return end

    gib:SetModel(mdl)
    gib:SetPos(origin + Vector(
        (math.random() - 0.5) * 40,
        (math.random() - 0.5) * 40,
        math.random(20, 80)
    ))
    gib:SetAngles(Angle(
        math.Rand(0, 360),
        math.Rand(0, 360),
        math.Rand(0, 360)
    ))
    gib:Spawn()
    gib:Activate()

    gib:SetColor(Color(0, 0, 0, 255))
    gib:SetMaterial("models/debug/debugwhite")

    local phys = gib:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(GIB_MASS)
        phys:EnableGravity(true)
        phys:Wake()

        local outDir = (hitNormal + Vector(
            (math.random() - 0.5) * 1.2,
            (math.random() - 0.5) * 1.2,
            0
        )):GetNormalized()

        local speed = math.Rand(GIB_SPEED_MIN, GIB_SPEED_MAX)
        local upVel = math.Rand(GIB_UP_MIN, GIB_UP_MAX)
        local vel   = outDir * speed + Vector(0, 0, upVel)
        phys:SetVelocity(vel)

        phys:SetAngleVelocity(Vector(
            (math.random() - 0.5) * 2 * GIB_SPIN_SCALE,
            (math.random() - 0.5) * 2 * GIB_SPIN_SCALE,
            (math.random() - 0.5) * 2 * GIB_SPIN_SCALE
        ))
    end

    -- Electric sparks at spawn point
    SpawnGibSparks(gib:GetPos(), hitNormal)

    -- Fire + explosion flash
    SpawnGibFireFX(gib, gib:GetPos(), hitNormal)

    -- Auto-remove
    timer.Simple(GIB_LIFETIME, function()
        if IsValid(gib) then gib:Remove() end
    end)

    return gib
end

-- ────────────────────────────────────────────────────────────
--  ENT:GekkoGib_OnDamage
-- ────────────────────────────────────────────────────────────
function ENT:GekkoGib_OnDamage(dmg, dmginfo)
    if dmg < GIB_DAMAGE_THRESHOLD then return end
    if math.random() > GIB_CHANCE   then return end

    local now = CurTime()
    if now < (self._gibCooldownT or 0) then return end
    self._gibCooldownT = now + GIB_COOLDOWN

    local hitPos = dmginfo:GetDamagePosition()
    if not hitPos or hitPos == vector_origin then
        hitPos = self:GetPos() + Vector(0, 0, 100)
    end

    local attacker  = dmginfo:GetAttacker()
    local hitNormal = Vector(0, 0, 1)
    if IsValid(attacker) then
        hitNormal = (self:GetPos() - attacker:GetPos()):GetNormalized()
        hitNormal.z = math.Clamp(hitNormal.z, -0.3, 0.3)
        hitNormal:Normalize()
    end

    local count = math.random(GIB_COUNT_MIN, GIB_COUNT_MAX)
    for _ = 1, count do
        SpawnSingleGib(hitPos, hitNormal)
    end

    print(string.format("[GekkoGib] Spawned %d gibs (dmg=%.1f)", count, dmg))
end