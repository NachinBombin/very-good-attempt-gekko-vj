-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
--
--  Two frozen prop_physics anchors connected by a phys_spring.
--  The spring is wired synchronously via SetPhysicsAttacker.
--  A repeated velocity kick each Think tick drives the pull on
--  players and NPCs (physics simulation on living ents is weak).
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
local ELASTIC_DAMAGE       = 12
local ELASTIC_DURATION     = 3.5    -- seconds the pull lasts
local ELASTIC_PULL_SPEED   = 420    -- velocity magnitude toward Gekko
local ELASTIC_PULL_INTERVAL= 0.08   -- how often the velocity kick repeats
local ELASTIC_ROPE_WIDTH   = 1.5
local ELASTIC_ROPE_R       = 180
local ELASTIC_ROPE_G       = 220
local ELASTIC_ROPE_B       = 80
local ELASTIC_SNAP_DELAY   = 3.5    -- matches ELASTIC_DURATION
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

-- ============================================================
--  GekkoElastic_Init
-- ============================================================
function ENT:GekkoElastic_Init()
    self._elasticNextShotT  = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self._elasticActive     = false
    self._elasticCleanupT   = 0
    self._elasticNextKickT  = 0
    self._elasticAnchorG    = nil
    self._elasticAnchorE    = nil
    self._elasticEnemy      = nil
end

-- ============================================================
--  GekkoElastic_Think
-- ============================================================
function ENT:GekkoElastic_Think()
    local now = CurTime()

    if self._elasticActive then
        -- cleanup when duration expires
        if now >= self._elasticCleanupT then
            self:_GekkoElastic_Cleanup()
            return
        end

        local enemy = self._elasticEnemy
        if not IsValid(enemy) then
            self:_GekkoElastic_Cleanup()
            return
        end

        -- pin anchorE to enemy every tick
        if IsValid(self._elasticAnchorE) then
            local epos = enemy:GetPos() + Vector(0, 0, 40)
            local phys = self._elasticAnchorE:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetPos(epos)
                phys:Wake()
            end
            self._elasticAnchorE:SetPos(epos)
        end

        -- repeated velocity kick toward Gekko
        if now >= self._elasticNextKickT then
            self._elasticNextKickT = now + ELASTIC_PULL_INTERVAL
            local gekkoPos = self:GetPos() + Vector(0, 0, 80)
            local enemyPos = enemy:GetPos() + Vector(0, 0, 40)
            local dir      = (gekkoPos - enemyPos):GetNormalized()
            local vel      = dir * ELASTIC_PULL_SPEED

            if enemy:IsPlayer() then
                enemy:SetVelocity(vel)
            else
                local phys = enemy:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(vel)
                    phys:Wake()
                elseif enemy.SetVelocity then
                    enemy:SetVelocity(vel)
                end
            end
        end
        return
    end

    -- passive fire gate
    if now < (self._elasticNextShotT or 0) then return end
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

    -- initial damage
    local dmg = DamageInfo()
    dmg:SetDamage(ELASTIC_DAMAGE)
    dmg:SetAttacker(self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(DMG_CLUB)
    dmg:SetDamageForce((enemyPos - gekkoPos):GetNormalized() * 55000)
    dmg:SetDamagePosition(enemyPos)
    enemy:TakeDamageInfo(dmg)

    -- first velocity kick immediately
    local dir = (gekkoPos - enemyPos):GetNormalized()
    local vel = dir * ELASTIC_PULL_SPEED
    if enemy:IsPlayer() then
        enemy:SetVelocity(vel)
    else
        local phys = enemy:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(vel)
            phys:Wake()
        elseif enemy.SetVelocity then
            enemy:SetVelocity(vel)
        end
    end

    self._elasticActive    = true
    self._elasticCleanupT  = CurTime() + ELASTIC_DURATION
    self._elasticNextKickT = CurTime() + ELASTIC_PULL_INTERVAL
    self._elasticAnchorG   = anchorG
    self._elasticAnchorE   = anchorE
    self._elasticEnemy     = enemy

    -- VFX net message
    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteFloat(ELASTIC_SNAP_DELAY)
        net.WriteUInt(ELASTIC_ROPE_WIDTH, 8)
        net.WriteUInt(ELASTIC_ROPE_R,     8)
        net.WriteUInt(ELASTIC_ROPE_G,     8)
        net.WriteUInt(ELASTIC_ROPE_B,     8)
    net.Broadcast()

    print(string.format("[GekkoElastic] FIRE  dist=%.0f  dur=%.1fs",
        self:GetPos():Distance(enemy:GetPos()), ELASTIC_DURATION))

    return true
end

-- ============================================================
--  _GekkoElastic_Cleanup
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
--  GekkoElastic_OnRemove
-- ============================================================
function ENT:GekkoElastic_OnRemove()
    self:_GekkoElastic_Cleanup()
    self._elasticNextShotT = math.huge
end