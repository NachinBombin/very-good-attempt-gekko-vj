-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
--
--  Called from init.lua:
--    ENT:Init()          → self:GekkoElastic_Init()
--    ENT:OnThink()       → self:GekkoElastic_Think()
--    ENT:OnRangeAttack   → self:GekkoElastic_Fire(enemy)   (via FireElastic)
--    ENT:OnDeath         → self:GekkoElastic_OnRemove()
--
--  Rules:
--    • Max range   : 900 units  (hard gate in FireElastic + here)
--    • Hit         : CERTAIN once triggered
--    • Force       : Gekko → Target * ELASTIC_FORCE
--    • VFX         : net "GekkoElasticRope" → elastic_cl.lua
-- ============================================================

AddCSLuaFile("elastic_cl.lua")

-- ------------------------------------------------------------
--  TUNABLES
-- ------------------------------------------------------------
local ELASTIC_MAX_RANGE    = 900
local ELASTIC_COOLDOWN_MIN = 6
local ELASTIC_COOLDOWN_MAX = 12
local ELASTIC_FORCE        = 55000
local ELASTIC_DAMAGE       = 35
local ELASTIC_ROPE_WIDTH   = 3
local ELASTIC_ROPE_R       = 180
local ELASTIC_ROPE_G       = 220
local ELASTIC_ROPE_B       = 80
local ELASTIC_SNAP_DELAY   = 0.35

util.AddNetworkString("GekkoElasticRope")

-- ============================================================
--  GekkoElastic_Init  — seed cooldown on spawn
-- ============================================================
function ENT:GekkoElastic_Init()
    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
end

-- ============================================================
--  GekkoElastic_Think  — passive window; fires on its own
--  probability independently of the weapon roll.
--  (The weapon roll also calls GekkoElastic_Fire directly via
--  FireElastic in init.lua — both paths are safe.)
-- ============================================================
function ENT:GekkoElastic_Think()
    if CurTime() < (self._elasticNextShotT or 0) then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return end

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > ELASTIC_MAX_RANGE then return end

    -- 18 % chance per think tick that passes all gates
    if math.random() > 0.18 then return end

    self:GekkoElastic_Fire(enemy)
end

-- ============================================================
--  GekkoElastic_Fire  — guaranteed hit + VFX
--  Called by both GekkoElastic_Think AND FireElastic (weapon roll)
-- ============================================================
function ENT:GekkoElastic_Fire(enemy)
    if not IsValid(enemy) then return false end

    -- arm next cooldown immediately so double-fires are impossible
    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)

    local gekkoPos = self:GetPos() + Vector(0, 0, 80)
    local enemyPos = enemy:GetPos() + Vector(0, 0, 40)
    local dir      = (enemyPos - gekkoPos):GetNormalized()
    local force    = dir * ELASTIC_FORCE

    -- damage
    local dmg = DamageInfo()
    dmg:SetDamage(ELASTIC_DAMAGE)
    dmg:SetAttacker(self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(DMG_CLUB)
    dmg:SetDamageForce(force)
    dmg:SetDamagePosition(enemyPos)
    enemy:TakeDamageInfo(dmg)

    -- physics push
    local phys = enemy:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(force)
    elseif enemy:IsPlayer() then
        local mass = (enemy.GetMass and enemy:GetMass()) or 80
        enemy:SetVelocity(force / mass)
    end

    -- VFX net message → elastic_cl.lua
    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteFloat(ELASTIC_SNAP_DELAY)
        net.WriteUInt(ELASTIC_ROPE_WIDTH, 8)
        net.WriteUInt(ELASTIC_ROPE_R,     8)
        net.WriteUInt(ELASTIC_ROPE_G,     8)
        net.WriteUInt(ELASTIC_ROPE_B,     8)
    net.Broadcast()

    print(string.format("[GekkoElastic] FIRE  dist=%.0f  dmg=%d",
        self:GetPos():Distance(enemy:GetPos()), ELASTIC_DAMAGE))

    return true
end

-- ============================================================
--  GekkoElastic_OnRemove  — clean up on death
-- ============================================================
function ENT:GekkoElastic_OnRemove()
    -- cooldown state is ephemeral; nothing persistent to clean.
    -- Kept as a hook point for future ragdoll / constraint removal.
    self._elasticNextShotT = math.huge
end
