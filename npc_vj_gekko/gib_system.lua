-- ============================================================
--  npc_vj_gekko / gib_system.lua
--
--  Spawns painted-black metal gib props when the Gekko takes
--  significant damage. Each gib is:
--    • a random model from GEKKO_GIB_MODELS
--    • rendered black via SetColor (opaque, pure black)
--    • launched outward + upward with random spin
--    • removed after GIB_LIFETIME seconds
--
--  Custom spark effect fires at the gib origin on spawn:
--    WheelSparks (bright metal streak, not ManhackSparks).
--
--  Called from ENT:OnTakeDamage in init.lua.
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
local GIB_UP_MAX            = 340
local GIB_SPIN_SCALE       = 200   -- random angular velocity magnitude
local GIB_MASS             = 18    -- kg — heavy enough to feel metallic
local GIB_COOLDOWN         = 4.0  -- seconds between gib events (spam guard)

-- Spark constants
local SPARK_EFFECT         = "ElectricSpark"  -- bright electric/welding sparks
local SPARK_EXTRA          = "Sparks"          -- secondary burst for density
local SPARK_COUNT          = 3                 -- effect calls per gib

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

-- Precache on load (server)
if SERVER then
    for _, mdl in ipairs(GEKKO_GIB_MODELS) do
        util.PrecacheModel(mdl)
    end
end

-- ────────────────────────────────────────────────────────────
--  SpawnGibSparks  (server — broadcasts via util.Effect)
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

    -- Secondary dense burst
    local e2 = EffectData()
    e2:SetOrigin(pos)
    e2:SetNormal(normal or Vector(0, 0, 1))
    e2:SetMagnitude(math.Rand(0.3, 1))
    e2:SetScale(math.Rand(0.4, 1))
    e2:SetRadius(math.random(5, 12))
    util.Effect(SPARK_EXTRA, e2)
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

    -- Paint solid black — looks like charred/oily metal
    gib:SetColor(Color(0, 0, 0, 255))
    gib:SetMaterial("models/debug/debugwhite")  -- flat shading amplifies the black

    local phys = gib:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(GIB_MASS)
        phys:EnableGravity(true)
        phys:Wake()

        -- Launch outward from the hit normal + random upward component
        local outDir = (hitNormal + Vector(
            (math.random() - 0.5) * 1.2,
            (math.random() - 0.5) * 1.2,
            0
        )):GetNormalized()

        local speed = math.Rand(GIB_SPEED_MIN, GIB_SPEED_MAX)
        local upVel = math.Rand(GIB_UP_MIN, GIB_UP_MAX)
        local vel   = outDir * speed + Vector(0, 0, upVel)
        phys:SetVelocity(vel)

        -- Random tumble
        phys:SetAngleVelocity(Vector(
            (math.random() - 0.5) * 2 * GIB_SPIN_SCALE,
            (math.random() - 0.5) * 2 * GIB_SPIN_SCALE,
            (math.random() - 0.5) * 2 * GIB_SPIN_SCALE
        ))
    end

    -- Sparks at spawn point
    SpawnGibSparks(gib:GetPos(), hitNormal)

    -- Auto-remove
    timer.Simple(GIB_LIFETIME, function()
        if IsValid(gib) then gib:Remove() end
    end)

    return gib
end

-- ────────────────────────────────────────────────────────────
--  ENT:GekkoGib_OnDamage
--  Call this from OnTakeDamage AFTER base damage is applied.
--  dmg = the actual damage value (number)
--  dmginfo = the DamageInfo object
-- ────────────────────────────────────────────────────────────
function ENT:GekkoGib_OnDamage(dmg, dmginfo)
    if dmg < GIB_DAMAGE_THRESHOLD then return end
    if math.random() > GIB_CHANCE   then return end

    local now = CurTime()
    if now < (self._gibCooldownT or 0) then return end
    self._gibCooldownT = now + GIB_COOLDOWN

    -- Eject from the hit position, or mid-body if unavailable
    local hitPos = dmginfo:GetDamagePosition()
    if not hitPos or hitPos == vector_origin then
        hitPos = self:GetPos() + Vector(0, 0, 100)
    end

    -- Normal points away from attacker
    local attacker  = dmginfo:GetAttacker()
    local hitNormal = Vector(0, 0, 1)
    if IsValid(attacker) then
        hitNormal = (self:GetPos() - attacker:GetPos()):GetNormalized()
        hitNormal.z = math.Clamp(hitNormal.z, -0.3, 0.3)  -- keep it lateral
        hitNormal:Normalize()
    end

    local count = math.random(GIB_COUNT_MIN, GIB_COUNT_MAX)
    for _ = 1, count do
        SpawnSingleGib(hitPos, hitNormal)
    end

    print(string.format("[GekkoGib] Spawned %d gibs (dmg=%.1f)", count, dmg))
end