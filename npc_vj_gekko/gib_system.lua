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
--    * ElectricSpark + Sparks  (metal strike sparks)  <-- UNCHANGED
--    * small HelicopterMegaBomb flash (tuned way down)
--    * brief Ignite() burn
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

-- Spark constants  (UNCHANGED)
local SPARK_EFFECT         = "ElectricSpark"
local SPARK_EXTRA          = "Sparks"
local SPARK_COUNT          = 3

-- Fire / explosion constants  (TUNED DOWN)
-- Per-gib flash: SetScale reduced 0.4->0.12, SetRadius 24->8, SetMagnitude 1->0.4
-- GIB_EXPLODE_CHANCE reduced 0.65->0.25 so only ~1-in-4 gibs flash at all
-- fire_medium_base particle REMOVED (was a full fire column; too heavy)
-- GIB_BURN_TIME reduced 5.0->1.8s -- quick scorch, not a bonfire
-- BigBurst flash: scale 1.0->0.28, radius 192->56, magnitude 2->0.6
local GIB_EXPLOSION_EFFECT = "HelicopterMegaBomb"
local GIB_BURN_TIME        = 1.8   -- down from 5.0
local GIB_EXPLODE_CHANCE   = 0.25  -- down from 0.65

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
--  SpawnGibSparks  (electric strike sparks -- UNCHANGED)
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
--  SpawnGibFireFX  (TUNED DOWN)
--  - HelicopterMegaBomb flash is now tiny (scale 0.12, radius 8)
--  - fire_medium_base particle column removed
--  - Ignite duration reduced to GIB_BURN_TIME (1.8s)
-- ────────────────────────────────────────────────────────────
local function SpawnGibFireFX(gib, pos, normal)
    -- Small flash, only on GIB_EXPLODE_CHANCE rolls
    if math.random() < GIB_EXPLODE_CHANCE then
        local eexp = EffectData()
        eexp:SetOrigin(pos)
        eexp:SetNormal(normal or Vector(0, 0, 1))
        eexp:SetScale(0.12)     -- was 0.4
        eexp:SetMagnitude(0.4)  -- was 1
        eexp:SetRadius(8)       -- was 24
        util.Effect(GIB_EXPLOSION_EFFECT, eexp)
    end

    -- Brief ignition scorch (no full fire column particle)
    if IsValid(gib) then
        local burnDur = math.min(GIB_BURN_TIME, GIB_LIFETIME - 0.5)
        if burnDur > 0 then
            gib:Ignite(burnDur, 0)
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

    -- Electric sparks at spawn point (UNCHANGED)
    SpawnGibSparks(gib:GetPos(), hitNormal)

    -- Tuned-down fire + flash
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

-- ────────────────────────────────────────────────────────────
--  ENT:GekkoGib_BigBurst
--  Forced large gib event with beefier explosion, used by leg-disable
--  TUNED DOWN: flash scale 1.0->0.28, radius 192->56, magnitude 2->0.6
-- ────────────────────────────────────────────────────────────
function ENT:GekkoGib_BigBurst(hitPos, hitNormal)
    hitPos    = hitPos    or (self:GetPos() + Vector(0, 0, 100))
    hitNormal = hitNormal or Vector(0, 0, 1)

    local count = math.random(GIB_COUNT_MAX + 3, GIB_COUNT_MAX * 2)
    for _ = 1, count do
        SpawnSingleGib(hitPos, hitNormal)
    end

    local eexp = EffectData()
    eexp:SetOrigin(hitPos)
    eexp:SetNormal(hitNormal)
    eexp:SetScale(0.28)     -- was 1.0
    eexp:SetMagnitude(0.6)  -- was 2
    eexp:SetRadius(56)      -- was 192
    util.Effect(GIB_EXPLOSION_EFFECT, eexp)

    util.ScreenShake(hitPos, 14, 8, 0.9, 900)
end
