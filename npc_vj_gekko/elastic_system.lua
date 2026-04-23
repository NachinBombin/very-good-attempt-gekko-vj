-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
--  Standalone attack.  No dependency on the weapon roll table.
--
--  Rules:
--    • Max range        : 900 units
--    • Trigger chance   : 18 % per think cycle (guarded by cooldown)
--    • Cooldown         : 6 – 12 s  (random per trigger)
--    • Hit is CERTAIN once triggered
--    • Force direction  : Gekko → Target (normalised) * ELASTIC_FORCE
--    • Rope VFX        : net msg → cl_init draws a Garry's Mod
--                        phys_spring (elastic) entity on the client
-- ============================================================

-- ------------------------------------------------------------
--  TUNABLES
-- ------------------------------------------------------------
local ELASTIC_MAX_RANGE    = 900      -- units, sphere check
local ELASTIC_TRIGGER_PROB = 0.18     -- 18 % per eligible think
local ELASTIC_COOLDOWN_MIN = 6
local ELASTIC_COOLDOWN_MAX = 12
local ELASTIC_FORCE        = 55000    -- impulse magnitude (source units)
local ELASTIC_DAMAGE       = 35       -- blunt damage on hit
local ELASTIC_ROPE_WIDTH   = 3        -- visual rope pixel width
local ELASTIC_ROPE_R       = 180
local ELASTIC_ROPE_G       = 220
local ELASTIC_ROPE_B       = 80
local ELASTIC_SNAP_DELAY   = 0.35     -- seconds rope is visible before snap

-- net messages registered in init.lua util.AddNetworkString block;
-- we declare them here as well so the file is self-contained if
-- loaded standalone.
if SERVER then
    util.AddNetworkString("GekkoElasticRope")
    util.AddNetworkString("GekkoElasticSnap")
end

-- ============================================================
--  ENT:ElasticSystem_Init
--  Called once from ENT:Initialize (init.lua)
-- ============================================================
function ENT:ElasticSystem_Init()
    self._elasticNextTime = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
end

-- ============================================================
--  ENT:ElasticSystem_Think
--  Called every server think frame.
-- ============================================================
function ENT:ElasticSystem_Think()
    if CurTime() < self._elasticNextTime then return end

    -- need a live enemy
    local enemy = self:GetEnemy()
    if not IsValid(enemy) or not enemy:IsPlayer() and not enemy:IsNPC() then
        return
    end

    -- range gate
    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > ELASTIC_MAX_RANGE then return end

    -- probability gate
    if math.random() > ELASTIC_TRIGGER_PROB then return end

    -- ---- FIRE ----
    self:ElasticSystem_Fire(enemy)

    -- arm next window
    self._elasticNextTime = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
end

-- ============================================================
--  ENT:ElasticSystem_Fire
--  The actual hit + VFX sequence.
-- ============================================================
function ENT:ElasticSystem_Fire(enemy)
    local gekkoPos = self:GetPos() + Vector(0, 0, 80)  -- approximate torso
    local enemyPos = enemy:GetPos() + Vector(0, 0, 40)

    -- direction from Gekko to target
    local dir   = (enemyPos - gekkoPos):GetNormalized()
    local force = dir * ELASTIC_FORCE

    -- ---- damage ----
    local dmgInfo = DamageInfo()
    dmgInfo:SetDamage(ELASTIC_DAMAGE)
    dmgInfo:SetAttacker(self)
    dmgInfo:SetInflictor(self)
    dmgInfo:SetDamageType(DMG_CLUB)
    dmgInfo:SetDamageForce(force)
    dmgInfo:SetDamagePosition(enemyPos)
    enemy:TakeDamageInfo(dmgInfo)

    -- ---- physics impulse (works on players and prop-based NPCs) ----
    local phys = enemy:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(force)
    elseif enemy:IsPlayer() then
        enemy:SetVelocity(force / (enemy:GetMass and enemy:GetMass() or 80))
    end

    -- ---- broadcast VFX ----
    -- Pass: gekko entity, enemy entity, snap delay
    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteFloat(ELASTIC_SNAP_DELAY)
        net.WriteUInt(ELASTIC_ROPE_WIDTH, 8)
        net.WriteUInt(ELASTIC_ROPE_R,     8)
        net.WriteUInt(ELASTIC_ROPE_G,     8)
        net.WriteUInt(ELASTIC_ROPE_B,     8)
    net.Broadcast()
end
