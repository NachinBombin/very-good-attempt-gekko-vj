-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
--
--  constraint.Elastic internally calls CreateKeyframeRope which
--  crashes on bare prop_physics anchors (nil bone comparison).
--  We bypass it entirely and create a  phys_spring  entity
--  directly — the same thing constraint.Elastic does internally,
--  minus the rope visual that breaks.
--
--  Pull logic:
--    - anchor_gekko : frozen at Gekko torso every Think tick
--    - anchor_enemy : frozen at enemy centre-mass every Think tick
--    - phys_spring  : connects them; engine resolves the tension
--    - After ELASTIC_DURATION both anchors + spring are removed
--    - Player fallback: direct SetVelocity kick toward Gekko
--
--  Called from init.lua:
--    self:GekkoElastic_Init()
--    self:GekkoElastic_Think()
--    self:GekkoElastic_Fire(enemy)
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
local ELASTIC_DURATION     = 0.6    -- seconds the spring lives
local ELASTIC_SPRING_CONST = 180    -- phys_spring "constant" key
local ELASTIC_DAMPING      = 8      -- phys_spring "damping" key
local ELASTIC_NATURAL_LEN  = 0      -- rest length; 0 = full pull
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
local function MakeAnchor(pos)
    local a = ents.Create("prop_physics")
    if not IsValid(a) then return nil end
    a:SetModel(ANCHOR_MODEL)
    a:SetPos(pos)
    a:SetNoDraw(true)
    a:DrawShadow(false)
    a:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    a:Spawn()
    a:Activate()
    local phys = a:GetPhysicsObject()
    if not IsValid(phys) then a:Remove() return nil end
    phys:SetMass(1)
    phys:EnableCollisions(false)
    phys:EnableMotion(false)
    phys:Wake()
    return a
end

local function MakeSpring(anchorG, anchorE, naturalLen)
    -- Create a raw phys_spring entity.
    -- This is what constraint.Elastic does internally, but without
    -- the CreateKeyframeRope call that crashes on our anchors.
    local spring = ents.Create("phys_spring")
    if not IsValid(spring) then return nil end

    spring:SetKeyValue("spawnflags",  "0")
    spring:SetKeyValue("constant",    tostring(ELASTIC_SPRING_CONST))
    spring:SetKeyValue("damping",     tostring(ELASTIC_DAMPING))
    spring:SetKeyValue("relativedamping", "0")
    spring:SetKeyValue("length",      tostring(math.max(naturalLen, 0)))
    spring:SetKeyValue("breaksound",  "")

    spring:SetPos(anchorG:GetPos())
    spring:Spawn()
    spring:Activate()

    -- Wire endpoints via input firing
    spring:Fire("SetEndPoint1", tostring(anchorG:EntIndex()), 0)
    spring:Fire("SetEndPoint2", tostring(anchorE:EntIndex()), 0)

    return spring
end

-- ============================================================
--  GekkoElastic_Init
-- ============================================================
function ENT:GekkoElastic_Init()
    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self._elasticActive   = false
    self._elasticCleanupT = 0
    self._elasticAnchorG  = nil
    self._elasticAnchorE  = nil
    self._elasticSpring   = nil
    self._elasticEnemy    = nil
end

-- ============================================================
--  GekkoElastic_Think
-- ============================================================
function ENT:GekkoElastic_Think()
    -- cleanup expired spring
    if self._elasticActive and CurTime() >= self._elasticCleanupT then
        self:_GekkoElastic_Cleanup()
    end

    -- pin anchor_enemy to enemy position every tick
    if self._elasticActive
    and IsValid(self._elasticAnchorE)
    and IsValid(self._elasticEnemy) then
        local pos  = self._elasticEnemy:GetPos() + Vector(0, 0, 40)
        local phys = self._elasticAnchorE:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:SetPos(pos)
            phys:Wake()
        end
        self._elasticAnchorE:SetPos(pos)
    end

    -- passive fire gate
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

    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self:_GekkoElastic_Cleanup()

    local gekkoPos = self:GetPos() + Vector(0, 0, 80)
    local enemyPos = enemy:GetPos() + Vector(0, 0, 40)

    local anchorG = MakeAnchor(gekkoPos)
    local anchorE = MakeAnchor(enemyPos)
    if not IsValid(anchorG) or not IsValid(anchorE) then
        if IsValid(anchorG) then anchorG:Remove() end
        if IsValid(anchorE) then anchorE:Remove() end
        return false
    end

    local spring = MakeSpring(anchorG, anchorE, ELASTIC_NATURAL_LEN)
    -- spring may be nil if phys_spring is unavailable; pull still
    -- happens via the velocity kick below.

    -- damage
    local dmg = DamageInfo()
    dmg:SetDamage(ELASTIC_DAMAGE)
    dmg:SetAttacker(self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(DMG_CLUB)
    dmg:SetDamageForce((enemyPos - gekkoPos):GetNormalized() * 55000)
    dmg:SetDamagePosition(enemyPos)
    enemy:TakeDamageInfo(dmg)

    -- direct velocity pull toward Gekko for both players and NPCs.
    -- NPCs: SetVelocity is respected between AI ticks.
    -- Players: engine will partially override but gives a visible jerk.
    local pullDir = (gekkoPos - enemyPos):GetNormalized()
    local pullVel = pullDir * 550
    if enemy:IsPlayer() then
        enemy:SetVelocity(pullVel)
    elseif enemy:IsNPC() then
        if enemy.SetVelocity then enemy:SetVelocity(pullVel) end
        local ephys = enemy:GetPhysicsObject()
        if IsValid(ephys) then
            ephys:SetVelocity(pullVel)
            ephys:Wake()
        end
    end

    self._elasticActive   = true
    self._elasticCleanupT = CurTime() + ELASTIC_DURATION
    self._elasticAnchorG  = anchorG
    self._elasticAnchorE  = anchorE
    self._elasticSpring   = spring
    self._elasticEnemy    = enemy

    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteFloat(ELASTIC_SNAP_DELAY)
        net.WriteUInt(ELASTIC_ROPE_WIDTH, 8)
        net.WriteUInt(ELASTIC_ROPE_R,     8)
        net.WriteUInt(ELASTIC_ROPE_G,     8)
        net.WriteUInt(ELASTIC_ROPE_B,     8)
    net.Broadcast()

    print(string.format("[GekkoElastic] FIRE  dist=%.0f  spring=%s",
        self:GetPos():Distance(enemy:GetPos()),
        IsValid(spring) and "OK" or "nil(vel-only)"))

    return true
end

-- ============================================================
--  _GekkoElastic_Cleanup
-- ============================================================
function ENT:_GekkoElastic_Cleanup()
    if IsValid(self._elasticSpring)  then self._elasticSpring:Remove()  end
    if IsValid(self._elasticAnchorG) then self._elasticAnchorG:Remove() end
    if IsValid(self._elasticAnchorE) then self._elasticAnchorE:Remove() end
    self._elasticActive  = false
    self._elasticSpring  = nil
    self._elasticAnchorG = nil
    self._elasticAnchorE = nil
    self._elasticEnemy   = nil
end

-- ============================================================
--  GekkoElastic_OnRemove
-- ============================================================
function ENT:GekkoElastic_OnRemove()
    self:_GekkoElastic_Cleanup()
    self._elasticNextShotT = math.huge
end
