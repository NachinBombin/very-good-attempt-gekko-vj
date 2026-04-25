-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
--
--  Approach: spawn two invisible prop_physics anchors
--    - anchor_enemy : glued to enemy via Think (tracks their pos)
--    - anchor_gekko : glued to Gekko torso
--  Then connect them with constraint.Elastic so the SOURCE
--  ENGINE resolves the pull.  Clean up after ELASTIC_DURATION.
--
--  Called from init.lua:
--    self:GekkoElastic_Init()
--    self:GekkoElastic_Think()
--    self:GekkoElastic_Fire(enemy)   -- also called by FireElastic
--    self:GekkoElastic_OnRemove()
-- ============================================================

AddCSLuaFile("elastic_cl.lua")

-- ------------------------------------------------------------
--  TUNABLES
-- ------------------------------------------------------------
local ELASTIC_MAX_RANGE    = 900
local ELASTIC_COOLDOWN_MIN = 6
local ELASTIC_COOLDOWN_MAX = 12
local ELASTIC_DAMAGE       = 35
local ELASTIC_DURATION     = 0.6   -- seconds the spring stays active
local ELASTIC_SPRING_CONST = 180   -- stiffness  (source: constraint.Elastic)
local ELASTIC_DAMPING      = 8     -- damping
local ELASTIC_NATURAL_LEN  = 0     -- target rest length (0 = pull all the way in)
local ELASTIC_ROPE_WIDTH   = 3
local ELASTIC_ROPE_R       = 180
local ELASTIC_ROPE_G       = 220
local ELASTIC_ROPE_B       = 80
local ELASTIC_SNAP_DELAY   = 0.35
local ANCHOR_MODEL         = "models/hunter/blocks/cube025x025x025.mdl"

util.AddNetworkString("GekkoElasticRope")
util.PrecacheModel(ANCHOR_MODEL)

-- ============================================================
--  HELPERS
-- ============================================================
local function MakeAnchor(pos, ang)
    local a = ents.Create("prop_physics")
    if not IsValid(a) then return nil end
    a:SetModel(ANCHOR_MODEL)
    a:SetPos(pos)
    a:SetAngles(ang or angle_zero)
    a:SetNoDraw(true)
    a:DrawShadow(false)
    a:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    a:Spawn()
    a:Activate()
    local phys = a:GetPhysicsObject()
    if not IsValid(phys) then a:Remove() return nil end
    phys:SetMass(1)
    phys:EnableCollisions(false)
    return a
end

-- ============================================================
--  GekkoElastic_Init
-- ============================================================
function ENT:GekkoElastic_Init()
    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self._elasticActive    = false
    self._elasticCleanupT  = 0
    self._elasticAnchorG   = nil   -- anchor on Gekko
    self._elasticAnchorE   = nil   -- anchor on enemy
    self._elasticEnemy     = nil   -- enemy being pulled
end

-- ============================================================
--  GekkoElastic_Think  (passive window; also ticks cleanup)
-- ============================================================
function ENT:GekkoElastic_Think()
    -- clean up expired springs
    if self._elasticActive and CurTime() >= self._elasticCleanupT then
        self:_GekkoElastic_Cleanup()
    end

    -- track anchor_enemy to follow the enemy each tick
    if self._elasticActive
    and IsValid(self._elasticAnchorE)
    and IsValid(self._elasticEnemy) then
        local pos = self._elasticEnemy:GetPos() + Vector(0, 0, 40)
        local phys = self._elasticAnchorE:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:SetPos(pos)
            phys:Wake()
        end
        self._elasticAnchorE:SetPos(pos)
    end

    if CurTime() < (self._elasticNextShotT or 0) then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return end
    if self:GetPos():Distance(enemy:GetPos()) > ELASTIC_MAX_RANGE then return end
    if math.random() > 0.18 then return end

    self:GekkoElastic_Fire(enemy)
end

-- ============================================================
--  GekkoElastic_Fire
-- ============================================================
function ENT:GekkoElastic_Fire(enemy)
    if not IsValid(enemy) then return false end

    -- arm cooldown immediately
    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)

    -- clean previous spring if any
    self:_GekkoElastic_Cleanup()

    local gekkoPos = self:GetPos() + Vector(0, 0, 80)
    local enemyPos = enemy:GetPos() + Vector(0, 0, 40)

    -- spawn anchors
    local anchorG = MakeAnchor(gekkoPos)
    local anchorE = MakeAnchor(enemyPos)
    if not IsValid(anchorG) or not IsValid(anchorE) then
        if IsValid(anchorG) then anchorG:Remove() end
        if IsValid(anchorE) then anchorE:Remove() end
        return false
    end

    -- pin gekko anchor (no motion — it just sits at torso)
    local physG = anchorG:GetPhysicsObject()
    if IsValid(physG) then physG:EnableMotion(false) end

    -- enemy anchor also pinned each think tick (above)
    local physE = anchorE:GetPhysicsObject()
    if IsValid(physE) then physE:EnableMotion(false) end

    -- create the elastic spring between the two anchors
    local constr = constraint.Elastic(
        anchorG, anchorE,
        0, 0,               -- bone indices
        Vector(0,0,0),      -- local offset on anchorG
        Vector(0,0,0),      -- local offset on anchorE
        ELASTIC_SPRING_CONST,
        ELASTIC_DAMPING,
        ELASTIC_NATURAL_LEN
    )

    -- damage
    local dmg = DamageInfo()
    dmg:SetDamage(ELASTIC_DAMAGE)
    dmg:SetAttacker(self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(DMG_CLUB)
    dmg:SetDamageForce(
        (enemyPos - gekkoPos):GetNormalized() * 55000
    )
    dmg:SetDamagePosition(enemyPos)
    enemy:TakeDamageInfo(dmg)

    -- direct velocity push for players (engine overrides phys velocity on players)
    if enemy:IsPlayer() then
        local dir = (gekkoPos - enemyPos):GetNormalized()
        enemy:SetVelocity(dir * 600)
    end

    -- store state
    self._elasticActive   = true
    self._elasticCleanupT = CurTime() + ELASTIC_DURATION
    self._elasticAnchorG  = anchorG
    self._elasticAnchorE  = anchorE
    self._elasticEnemy    = enemy

    -- broadcast VFX
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
--  _GekkoElastic_Cleanup  (internal)
-- ============================================================
function ENT:_GekkoElastic_Cleanup()
    if IsValid(self._elasticAnchorG) then self._elasticAnchorG:Remove() end
    if IsValid(self._elasticAnchorE) then self._elasticAnchorE:Remove() end
    self._elasticActive  = false
    self._elasticAnchorG = nil
    self._elasticAnchorE = nil
    self._elasticEnemy   = nil
end

-- ============================================================
--  GekkoElastic_OnRemove  (called on death)
-- ============================================================
function ENT:GekkoElastic_OnRemove()
    self:_GekkoElastic_Cleanup()
    self._elasticNextShotT = math.huge
end
