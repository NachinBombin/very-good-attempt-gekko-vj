-- ============================================================
--  npc_vj_gekko / init.lua  (server)
-- ============================================================

include("shared.lua")
include("gib_system.lua")
include("leg_disable_system.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("elastic_system.lua")
include("crouch_system.lua")
include("death_pose_system.lua")

-- ============================================================
--  BLOOD TUNING
-- ============================================================
-- Probability (0-1) that a single bullet/hit also triggers one
-- of the custom blood variants (Geyser, Ring, Cloud, Arc, Pool,
-- or HemoStream) on top of the vanilla GMod bleed decals.
local CUSTOM_BLEED_CHANCE = 0.35

-- Minimum damage per hit to be eligible for a custom bleed event.
local CUSTOM_BLEED_MIN_DMG = 8

-- How many custom blood variants exist (variants 1-6 in cl_init).
local CUSTOM_BLEED_VARIANTS = 6

-- ============================================================
--  ENT:Initialize
-- ============================================================
function ENT:Initialize()
    self.BaseClass.Initialize(self)
    self:GekkoLegs_Init()
    self:GekkoGib_Init()  -- if defined; safe no-op otherwise
end

-- ============================================================
--  ENT:TraceAttack
--  Called server-side on every bullet/projectile hit.
--
--  1. Passes through to the VJ base class so the vanilla GMod
--     blood decals + drips are produced (ENT.Bleeds = true handles
--     the colour; the base TraceAttack calls MakeBlood internally).
--  2. Rolls CUSTOM_BLEED_CHANCE to also fire a custom blood
--     variant via the GekkoBloodSplat NWInt, which cl_init reads
--     and dispatches to the appropriate particle/effect variant.
-- ============================================================
function ENT:TraceAttack(dmginfo, dir, trace)
    -- 1. Vanilla GMod bleed (decals, drips) via the base class.
    self.BaseClass.TraceAttack(self, dmginfo, dir, trace)

    -- 2. Custom bleed chance.
    local dmg = dmginfo:GetDamage()
    if dmg < CUSTOM_BLEED_MIN_DMG then return end
    if math.random() > CUSTOM_BLEED_CHANCE then return end

    -- Pack pulse counter + variant into one NWInt so cl_init
    -- can detect each new event without missing repeated variants.
    --   packed = pulse * 16 + (variant - 1)
    -- pulse increments each call so clients always see a change.
    self._bloodSplatPulse = ((self._bloodSplatPulse or 0) + 1) % 2048
    local variant = math.random(1, CUSTOM_BLEED_VARIANTS)
    self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse * 16 + (variant - 1))
end

-- ============================================================
--  ENT:OnTakeDamage
--  Called for ALL damage types (including explosions, fire, etc.)
--  that TraceAttack would miss.
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    self.BaseClass.OnTakeDamage(self, dmginfo)

    -- Leg-disable threshold check.
    self:GekkoLegs_OnDamage(dmginfo)

    -- Gib system check.
    self:GekkoGib_OnDamage(dmginfo:GetDamage(), dmginfo)

    -- For non-bullet damage (explosion, fire) also roll a custom bleed.
    local dt = dmginfo:GetDamageType()
    local isBullet = bit.band(dt, DMG_BULLET) ~= 0
        or bit.band(dt, DMG_BUCKSHOT) ~= 0
    if isBullet then return end  -- already handled in TraceAttack

    local dmg = dmginfo:GetDamage()
    if dmg < CUSTOM_BLEED_MIN_DMG then return end
    if math.random() > CUSTOM_BLEED_CHANCE then return end

    self._bloodSplatPulse = ((self._bloodSplatPulse or 0) + 1) % 2048
    local variant = math.random(1, CUSTOM_BLEED_VARIANTS)
    self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse * 16 + (variant - 1))
end

-- ============================================================
--  ENT:Think  (server)
-- ============================================================
function ENT:Think()
    self.BaseClass.Think(self)
    self:GekkoLegs_Think()
end
