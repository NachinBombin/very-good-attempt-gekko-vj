-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
--
--  BUG FIXES in this revision:
--
--  1. RE-APPEAR AFTER SNAP
--     GekkoElastic_Fire sets _elasticNextShotT, but the retract
--     animation on the client takes  dist/EXTEND_SPEED  seconds.
--     A new beam can fire immediately after cleanup and appear
--     while the retract is still playing.
--     FIX: Track _elasticRetractUntil on every cleanup path.
--     The passive fire gate blocks until that time clears.
--
--  2. ATTACHES AFTER TARGET DIES
--     IsValid(ply) returns true on a dead, not-yet-removed player.
--     FIX: All enemy validity checks now also call :Alive() for
--     players.
--
--  3. ZOMBIE CABLE ON DEATH / RESPAWN
--     Player entity is reused across respawns.  _elasticActive
--     was never cleared on death so the cable persisted forever.
--     FIX: hook PlayerDeath + PlayerSpawn force-break any active
--     beam targeting that player and broadcast GekkoElasticBreak.
-- ============================================================

AddCSLuaFile("elastic_cl.lua")

-- ------------------------------------------------------------
--  TUNABLES
-- ------------------------------------------------------------
local ELASTIC_MAX_RANGE     = 600
local ELASTIC_COOLDOWN_MIN  = 30
local ELASTIC_COOLDOWN_MAX  = 65
local ELASTIC_DAMAGE        = 5
local ELASTIC_DURATION      = 2.8
local ELASTIC_PULL_SPEED    = 420
local ELASTIC_PULL_INTERVAL = 0.08
local ELASTIC_ROPE_WIDTH    = 1.4
local ELASTIC_ROPE_R        = 0
local ELASTIC_ROPE_G        = 0
local ELASTIC_ROPE_B        = 0
local ELASTIC_SNAP_DELAY    = 2.8
local ANCHOR_MODEL          = "models/hunter/blocks/cube025x025x025.mdl"

local GEKKO_ORIGIN_Z        = 380
local ELASTIC_PREFIRE_DELAY = 0.9
local EXTEND_SPEED          = 600

local BREAK_THRESHOLD = 7
local BREAK_WINDOW    = 1.0

-- How long after any cleanup we block new shots.
-- Must be >= max retract travel time (MAX_RANGE / EXTEND_SPEED).
local RETRACT_BLOCK_PAD = (ELASTIC_MAX_RANGE / EXTEND_SPEED) + 0.3

util.AddNetworkString("GekkoElasticRope")
util.AddNetworkString("GekkoElasticShootSound")
util.AddNetworkString("GekkoElasticBreak")
util.AddNetworkString("GekkoElasticRetract")
util.PrecacheModel(ANCHOR_MODEL)

-- ============================================================
--  HELPERS
-- ============================================================
-- Returns true only if the entity is alive and valid.
-- Handles players (need :Alive()) and NPCs (health check).
local function IsAliveAndValid(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return ent:Alive() end
    -- NPC / prop: treat as alive if it has positive health or no health concept
    if ent.Health and ent:Health() <= 0 then return false end
    return true
end

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
--  GLOBAL DEATH / RESPAWN HOOKS
--  These run once per server, not per-Gekko instance.
--  They scan all Gekkos so we don't miss a cable targeting
--  the dying player.
-- ============================================================
local function ForceBreakOnTarget(target)
    for _, ent in ipairs(ents.FindByClass("npc_vj_gekko")) do
        if not IsValid(ent) then continue end

        -- Clear any pending shot aimed at this target
        if ent._elasticPendingEnemy == target then
            ent._elasticPending      = false
            ent._elasticPendingEnemy = nil
        end

        if not ent._elasticActive then continue end
        if ent._elasticEnemy ~= target then continue end

        local breakPos = IsValid(target) and
            (target:GetPos() + Vector(0, 0, 40)) or Vector(0,0,0)

        ent:_GekkoElastic_Cleanup()

        net.Start("GekkoElasticBreak")
            net.WriteEntity(target)
            net.WriteVector(breakPos)
        net.Broadcast()
    end
end

hook.Add("PlayerDeath", "GekkoElasticPlayerDeath", function(ply)
    ForceBreakOnTarget(ply)
end)

hook.Add("PlayerSpawn", "GekkoElasticPlayerSpawn", function(ply)
    -- Respawn reuses the same entity: force-break any cable
    -- that survived death (edge-case if PlayerDeath was missed)
    ForceBreakOnTarget(ply)
end)

-- ============================================================
--  PER-PLAYER BUTTON TIMESTAMP TABLE  (key-smash break)
-- ============================================================
local _breakTimes = {}

hook.Add("PlayerButtonDown", "GekkoElasticCableBreak", function(ply)
    if not IsValid(ply) or not ply:Alive() then return end

    if not _breakTimes[ply] then _breakTimes[ply] = {} end

    local now   = CurTime()
    local times = _breakTimes[ply]
    times[#times + 1] = now

    local cutoff = now - BREAK_WINDOW
    local i = 1
    while i <= #times do
        if times[i] < cutoff then table.remove(times, i)
        else i = i + 1 end
    end

    if #times < BREAK_THRESHOLD then return end

    for _, ent in ipairs(ents.FindByClass("npc_vj_gekko")) do
        if not IsValid(ent) then continue end
        if not ent._elasticActive then continue end
        if ent._elasticEnemy ~= ply then continue end

        local breakPos = ply:GetPos() + Vector(0, 0, 40)
        _breakTimes[ply] = {}
        ent:_GekkoElastic_Cleanup()

        net.Start("GekkoElasticBreak")
            net.WriteEntity(ply)
            net.WriteVector(breakPos)
        net.Broadcast()
        break
    end
end)

hook.Add("PlayerDisconnected", "GekkoElasticCableBreakCleanup", function(ply)
    _breakTimes[ply] = nil
    ForceBreakOnTarget(ply)
end)

-- ============================================================
--  GekkoElastic_Init
-- ============================================================
function ENT:GekkoElastic_Init()
    self._elasticNextShotT    = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self._elasticRetractUntil = 0     -- blocks new shots during retract
    self._elasticActive       = false
    self._elasticPending      = false
    self._elasticPendingT     = 0
    self._elasticPendingEnemy = nil
    self._elasticCleanupT     = 0
    self._elasticNextKickT    = 0
    self._elasticPullStartT   = 0
    self._elasticAnchorG      = nil
    self._elasticAnchorE      = nil
    self._elasticEnemy        = nil
end

-- ============================================================
--  GekkoElastic_Think
-- ============================================================
function ENT:GekkoElastic_Think()
    local now = CurTime()

    -- pending pre-fire delay
    if self._elasticPending then
        if now >= self._elasticPendingT then
            self._elasticPending = false
            local pendEnemy = self._elasticPendingEnemy
            self._elasticPendingEnemy = nil
            -- Discard if target died while waiting
            if IsAliveAndValid(pendEnemy) then
                if not GekkoElastic_HasLOS(self, pendEnemy) then
                    self._elasticNextShotT = now + 2.0
                    return
                end
                self:_GekkoElastic_Detonate(pendEnemy)
            end
        end
        return
    end

    if self._elasticActive then
        -- Target died mid-pull
        local enemy = self._elasticEnemy
        if not IsAliveAndValid(enemy) then
            local breakPos = IsValid(enemy) and
                (enemy:GetPos() + Vector(0, 0, 40)) or Vector(0,0,0)
            self:_GekkoElastic_Cleanup()
            if IsValid(enemy) then
                net.Start("GekkoElasticBreak")
                    net.WriteEntity(enemy)
                    net.WriteVector(breakPos)
                net.Broadcast()
            end
            return
        end

        -- Natural expiry
        if now >= self._elasticCleanupT then
            local retractEnt = self._elasticEnemy
            self:_GekkoElastic_Cleanup()
            if IsValid(retractEnt) then
                net.Start("GekkoElasticRetract")
                    net.WriteEntity(retractEnt)
                net.Broadcast()
            end
            return
        end

        -- Track anchor to enemy
        if IsValid(self._elasticAnchorE) then
            local epos = enemy:GetPos() + Vector(0, 0, 40)
            local phys = self._elasticAnchorE:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetPos(epos)
                phys:Wake()
            end
            self._elasticAnchorE:SetPos(epos)
        end

        -- Velocity kicks (delayed until tip arrives)
        if now >= self._elasticPullStartT and now >= self._elasticNextKickT then
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

    -- Passive fire gate:
    -- Block during cooldown AND during the retract window of the last cable.
    if now < (self._elasticNextShotT or 0) then return end
    if now < (self._elasticRetractUntil or 0) then return end

    local enemy = self:GetEnemy()
    if not IsAliveAndValid(enemy) then return end
    if self:GetPos():Distance(enemy:GetPos()) > ELASTIC_MAX_RANGE then return end
    if not GekkoElastic_HasLOS(self, enemy) then return end
    if math.random() > 0.18 then return end
    self:GekkoElastic_Fire(enemy)
end

-- ============================================================
--  GekkoElastic_Fire
-- ============================================================
function ENT:GekkoElastic_Fire(enemy)
    if not IsAliveAndValid(enemy) then return false end

    self._elasticNextShotT = CurTime() + math.Rand(
        ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    self:_GekkoElastic_Cleanup()

    net.Start("GekkoElasticShootSound")
        net.WriteEntity(self)
    net.Broadcast()

    self._elasticPending      = true
    self._elasticPendingT     = CurTime() + ELASTIC_PREFIRE_DELAY
    self._elasticPendingEnemy = enemy
    return true
end

-- ============================================================
--  _GekkoElastic_Detonate
-- ============================================================
function ENT:_GekkoElastic_Detonate(enemy)
    if not IsAliveAndValid(enemy) then return end

    local gekkoPos = self:GetPos() + Vector(0, 0, GEKKO_ORIGIN_Z)
    local enemyPos = enemy:GetPos() + Vector(0, 0, 40)

    local anchorG = MakeAnchor(gekkoPos)
    local anchorE = MakeAnchor(enemyPos)
    if not IsValid(anchorG) or not IsValid(anchorE) then
        if IsValid(anchorG) then anchorG:Remove() end
        if IsValid(anchorE) then anchorE:Remove() end
        return
    end

    local dist       = gekkoPos:Distance(enemyPos)
    local travelTime = dist / EXTEND_SPEED

    self._elasticActive     = true
    self._elasticCleanupT   = CurTime() + ELASTIC_DURATION
    self._elasticPullStartT = CurTime() + travelTime
    self._elasticNextKickT  = CurTime() + travelTime
    self._elasticAnchorG    = anchorG
    self._elasticAnchorE    = anchorE
    self._elasticEnemy      = enemy

    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteFloat(ELASTIC_SNAP_DELAY)
        net.WriteUInt(math.floor(ELASTIC_ROPE_WIDTH), 8)
        net.WriteUInt(ELASTIC_ROPE_R, 8)
        net.WriteUInt(ELASTIC_ROPE_G, 8)
        net.WriteUInt(ELASTIC_ROPE_B, 8)
    net.Broadcast()

    timer.Simple(travelTime, function()
        if not IsAliveAndValid(enemy) then return end
        local dmg = DamageInfo()
        dmg:SetDamage(ELASTIC_DAMAGE)
        dmg:SetAttacker(self)
        dmg:SetInflictor(self)
        dmg:SetDamageType(DMG_CLUB)
        dmg:SetDamageForce((enemyPos - gekkoPos):GetNormalized() * 55000)
        dmg:SetDamagePosition(enemyPos)
        enemy:TakeDamageInfo(dmg)
    end)
end

-- ============================================================
--  _GekkoElastic_Cleanup
--
--  Sets _elasticRetractUntil so the passive fire gate knows
--  to wait out the retract animation before shooting again.
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
    self._elasticPullStartT   = 0
    -- Block new shots for the full retract travel time
    self._elasticRetractUntil = CurTime() + RETRACT_BLOCK_PAD
end

-- ============================================================
--  GekkoElastic_OnRemove
-- ============================================================
function ENT:GekkoElastic_OnRemove()
    self:_GekkoElastic_Cleanup()
    self._elasticNextShotT    = math.huge
    self._elasticRetractUntil = math.huge
end
