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
local ELASTIC_MAX_RANGE     = 600
local ELASTIC_COOLDOWN_MIN  = 30
local ELASTIC_COOLDOWN_MAX  = 65
local ELASTIC_DAMAGE        = 5
local ELASTIC_DURATION      = 2.8    -- seconds the pull lasts
local ELASTIC_PULL_SPEED    = 420    -- velocity magnitude toward Gekko
local ELASTIC_PULL_INTERVAL = 0.08   -- how often the velocity kick repeats
local ELASTIC_ROPE_WIDTH    = 1.4
local ELASTIC_ROPE_R        = 0
local ELASTIC_ROPE_G        = 0
local ELASTIC_ROPE_B        = 0
local ELASTIC_SNAP_DELAY    = 2.8    -- matches ELASTIC_DURATION
local ANCHOR_MODEL          = "models/hunter/blocks/cube025x025x025.mdl"

-- The origin Z offset for the rope / pull.
local GEKKO_ORIGIN_Z        = 380

-- Pre-fire delay: shoot sound plays NOW, actual logic starts after.
local ELASTIC_PREFIRE_DELAY = 0.9

util.AddNetworkString("GekkoElasticRope")
util.AddNetworkString("GekkoElasticShootSound")
util.PrecacheModel(ANCHOR_MODEL)

-- ============================================================
--  LINE-OF-SIGHT HELPER
--
--  Traces from the Gekko's fire origin (GetPos + GEKKO_ORIGIN_Z)
--  to the enemy's eye / center position.
--
--  Uses MASK_SOLID_BRUSHONLY so only world brushes (walls,
--  rooftops, solid geometry) block the shot.  Other NPCs and
--  props are intentionally ignored -- the Gekko can reach
--  through them but NOT through solid architecture.
--
--  Returns true if the path is clear.
-- ============================================================
local function GekkoElastic_HasLOS(gekko, enemy)
    local fromPos = gekko:GetPos() + Vector(0, 0, GEKKO_ORIGIN_Z)
    local toPos   = enemy:GetPos() + Vector(0, 0, 40)

    local tr = util.TraceLine({
        start  = fromPos,
        endpos = toPos,
        filter = { gekko, enemy },
        mask   = MASK_SOLID_BRUSHONLY,
    })

    return not tr.Hit
end

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
    self._elasticNextShotT    = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self._elasticActive       = false
    self._elasticPending      = false
    self._elasticPendingT     = 0
    self._elasticPendingEnemy = nil
    self._elasticCleanupT     = 0
    self._elasticNextKickT    = 0
    self._elasticAnchorG      = nil
    self._elasticAnchorE      = nil
    self._elasticEnemy        = nil
end

-- ============================================================
--  GekkoElastic_Think
-- ============================================================
function ENT:GekkoElastic_Think()
    local now = CurTime()

    -- ---- pending pre-fire delay ----
    if self._elasticPending then
        if now >= self._elasticPendingT then
            self._elasticPending = false
            local pendEnemy = self._elasticPendingEnemy
            self._elasticPendingEnemy = nil

            if IsValid(pendEnemy) then
                -- Re-check LOS at detonation time.
                -- If enemy ducked behind cover during the 0.9s wind-up,
                -- abort silently.  Reset cooldown to a short value so
                -- the Gekko tries again quickly once LOS is restored.
                if not GekkoElastic_HasLOS(self, pendEnemy) then
                    print("[GekkoElastic] DETONATE BLOCKED (no LOS) -- re-queuing")
                    self._elasticNextShotT = now + 2.0
                    return
                end
                self:_GekkoElastic_Detonate(pendEnemy)
            end
        end
        return
    end

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
            local gekkoPos = self:GetPos() + Vector(0, 0, GEKKO_ORIGIN_Z)
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

    -- ---- passive fire gate ----
    if now < (self._elasticNextShotT or 0) then return end
    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return end
    if self:GetPos():Distance(enemy:GetPos()) > ELASTIC_MAX_RANGE then return end

    -- LOS gate: don't even commit to pre-fire if sight is blocked
    if not GekkoElastic_HasLOS(self, enemy) then return end

    if math.random() > 0.18 then return end
    self:GekkoElastic_Fire(enemy)
end

-- ============================================================
--  GekkoElastic_Fire
--  Sends the shoot sound net message immediately, then waits
--  ELASTIC_PREFIRE_DELAY before actually doing anything.
-- ============================================================
function ENT:GekkoElastic_Fire(enemy)
    if not IsValid(enemy) then return false end

    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self:_GekkoElastic_Cleanup()

    -- broadcast the pre-fire shoot sound immediately
    net.Start("GekkoElasticShootSound")
        net.WriteEntity(self)
    net.Broadcast()

    -- queue the real logic for ELASTIC_PREFIRE_DELAY seconds later
    self._elasticPending      = true
    self._elasticPendingT     = CurTime() + ELASTIC_PREFIRE_DELAY
    self._elasticPendingEnemy = enemy

    print(string.format("[GekkoElastic] PRE-FIRE  delay=%.1fs", ELASTIC_PREFIRE_DELAY))
    return true
end

-- ============================================================
--  _GekkoElastic_Detonate  (runs after pre-fire delay)
-- ============================================================
function ENT:_GekkoElastic_Detonate(enemy)
    if not IsValid(enemy) then return end

    local gekkoPos = self:GetPos() + Vector(0, 0, GEKKO_ORIGIN_Z)
    local enemyPos = enemy:GetPos() + Vector(0, 0, 40)

    local anchorG = MakeAnchor(gekkoPos)
    local anchorE = MakeAnchor(enemyPos)
    if not IsValid(anchorG) or not IsValid(anchorE) then
        if IsValid(anchorG) then anchorG:Remove() end
        if IsValid(anchorE) then anchorE:Remove() end
        return
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

    -- VFX net message (beam + tentacle loop sound)
    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteFloat(ELASTIC_SNAP_DELAY)
        net.WriteUInt(math.floor(ELASTIC_ROPE_WIDTH), 8)
        net.WriteUInt(ELASTIC_ROPE_R, 8)
        net.WriteUInt(ELASTIC_ROPE_G, 8)
        net.WriteUInt(ELASTIC_ROPE_B, 8)
    net.Broadcast()

    print(string.format("[GekkoElastic] FIRE  dist=%.0f  dur=%.1fs",
        self:GetPos():Distance(enemy:GetPos()), ELASTIC_DURATION))
end

-- ============================================================
--  _GekkoElastic_Cleanup
-- ============================================================
function ENT:_GekkoElastic_Cleanup()
    if IsValid(self._elasticAnchorG) then self._elasticAnchorG:Remove() end
    if IsValid(self._elasticAnchorE) then self._elasticAnchorE:Remove() end
    self._elasticActive       = false
    self._elasticPending      = false
    self._elasticPendingEnemy = nil
    self._elasticAnchorG      = nil
    self._elasticAnchorE      = nil
    self._elasticEnemy        = nil
end

-- ============================================================
--  GekkoElastic_OnRemove
-- ============================================================
function ENT:GekkoElastic_OnRemove()
    self:_GekkoElastic_Cleanup()
    self._elasticNextShotT = math.huge
end