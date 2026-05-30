-- ============================================================
--  ELASTIC SLING SYSTEM  (server-side)
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

local GEKKO_ORIGIN_Z        = 380   -- used only as fallback below

-- Returns the tentacle-origin position for a Gekko entity.
-- Prefers the spine bone's actual world position so the tentacle root
-- stays glued to the model even when the NPC is crouching or downed
-- by the leg-disable system.  Falls back to the flat Z offset.
local function GekkoElastic_GetOrigin(gekko)
    local boneIdx = gekko.GekkoSpineBone or gekko.GekkoPelvisBone or -1
    if boneIdx >= 0 then
        local m = gekko:GetBoneMatrix(boneIdx)
        if m then return m:GetTranslation() end
    end
    -- Fallback: model-relative up direction so the offset is not world-Z fixed
    local up = gekko:GetAngles():Up()
    return gekko:GetPos() + up * GEKKO_ORIGIN_Z
end

local ELASTIC_PREFIRE_DELAY = 0.9
local EXTEND_SPEED          = 600

local BREAK_THRESHOLD = 7
local BREAK_WINDOW    = 1.0

-- How long after any cleanup we block new shots.
local RETRACT_BLOCK_PAD = (ELASTIC_MAX_RANGE / EXTEND_SPEED) + 0.3

util.AddNetworkString("GekkoElasticRope")
util.AddNetworkString("GekkoElasticShootSound")
util.AddNetworkString("GekkoElasticBreak")
util.AddNetworkString("GekkoElasticRetract")
util.PrecacheModel(ANCHOR_MODEL)

-- ============================================================
--  HELPERS
-- ============================================================
local function IsAliveAndValid(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return ent:Alive() end
    if ent.Health and ent:Health() <= 0 then return false end
    return true
end

-- FIX (nikita grab prevention): returns true for any entity that must
-- never be grabbed by the tentacle. Catches npc_vj_gekko_nikita and any
-- other projectile / missile entity the gekko owns.
local function IsNikitaOrProjectile(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass()
    if cls == "npc_vj_gekko_nikita" then return true end
    if cls == "sent_npc_topmissile"   then return true end
    if cls == "sent_npc_trackmissile" then return true end
    if cls == "sent_orbital_rpg"      then return true end
    if cls == "obj_gekko_rocket"      then return true end
    local owner = ent:GetOwner()
    if IsValid(owner) and owner:GetClass() == "npc_vj_gekko" then return true end
    return false
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
    a._gekkoOwnedGib = true
    local phys = a:GetPhysicsObject()
    if not IsValid(phys) then a:Remove() return nil end
    phys:SetMass(1)
    phys:EnableCollisions(false)
    phys:EnableMotion(false)
    phys:Wake()
    return a
end

local function GekkoElastic_HasLOS(gekko, enemy)
    local fromPos = GekkoElastic_GetOrigin(gekko)
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
-- ============================================================
local function ForceBreakOnTarget(target)
    for _, ent in ipairs(ents.FindByClass("npc_vj_gekko")) do
        if not IsValid(ent) then continue end

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
    timer.Simple(0.1, function()
        if not IsValid(ply) then return end
        ForceBreakOnTarget(ply)
    end)
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

    _breakTimes[ply] = {}

    for _, ent in ipairs(ents.FindByClass("npc_vj_gekko")) do
        if not IsValid(ent) then continue end
        if not ent._elasticActive then continue end
        if ent._elasticEnemy ~= ply then continue end

        local breakPos = ply:GetPos() + Vector(0, 0, 40)
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
    self._elasticRetractUntil = 0
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

    if self._elasticPending then
        if now >= self._elasticPendingT then
            self._elasticPending = false
            local pendEnemy = self._elasticPendingEnemy
            self._elasticPendingEnemy = nil
            if IsNikitaOrProjectile(pendEnemy) then
                self._elasticNextShotT = now + 2.0
                return
            end
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

        if IsValid(self._elasticAnchorE) then
            local epos = enemy:GetPos() + Vector(0, 0, 40)
            local phys = self._elasticAnchorE:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetPos(epos)
                phys:Wake()
            end
            self._elasticAnchorE:SetPos(epos)
        end

        if now >= self._elasticPullStartT and now >= self._elasticNextKickT then
            self._elasticNextKickT = now + ELASTIC_PULL_INTERVAL
            local gekkoPos = GekkoElastic_GetOrigin(self)
            local enemyPos = enemy:GetPos() + Vector(0, 0, 40)
            local dir      = (gekkoPos - enemyPos):GetNormalized()
            local vel      = dir * ELASTIC_PULL_SPEED

            if enemy:IsPlayer() then
                enemy:SetVelocity(vel)
            elseif enemy:IsNPC() then
                local phys = enemy:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(vel)
                    phys:Wake()
                end

                local dmg = DamageInfo()
                dmg:SetDamage(ELASTIC_DAMAGE)
                dmg:SetAttacker(self)
                dmg:SetInflictor(self)
                dmg:SetDamageType(DMG_CRUSH)
                dmg:SetDamageForce((enemyPos - gekkoPos):GetNormalized() * 55000)
                dmg:SetDamagePosition(enemyPos)
                enemy:TakeDamageInfo(dmg)
            end
        end
        return
    end

    if now < (self._elasticNextShotT or 0)   then return end
    if now < (self._elasticRetractUntil or 0) then return end
    if self._gekkoDead                         then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return end
    if not IsAliveAndValid(enemy) then return end
    if IsNikitaOrProjectile(enemy) then return end
    if self:GetPos():Distance(enemy:GetPos()) > ELASTIC_MAX_RANGE then return end
    if not GekkoElastic_HasLOS(self, enemy) then return end

    -- Schedule the shot after prefire delay
    self._elasticPending      = true
    self._elasticPendingT     = now + ELASTIC_PREFIRE_DELAY
    self._elasticPendingEnemy = enemy

    net.Start("GekkoElasticShootSound")
        net.WriteEntity(self)
    net.Broadcast()
end

-- ============================================================
--  _GekkoElastic_Detonate  (fires the actual tentacle)
-- ============================================================
function ENT:_GekkoElastic_Detonate(enemy)
    if not IsAliveAndValid(enemy) then return end
    if IsNikitaOrProjectile(enemy) then return end

    local gekkoPos = GekkoElastic_GetOrigin(self)
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
    self._elasticNextKickT  = 0
    self._elasticAnchorG    = anchorG
    self._elasticAnchorE    = anchorE
    self._elasticEnemy      = enemy

    net.Start("GekkoElasticRope")
        net.WriteEntity(self)
        net.WriteEntity(enemy)
        net.WriteVector(gekkoPos)
        net.WriteVector(enemyPos)
        net.WriteFloat(travelTime)
        net.WriteFloat(ELASTIC_DURATION)
        net.WriteFloat(ELASTIC_ROPE_WIDTH)
        net.WriteUInt(ELASTIC_ROPE_R, 8)
        net.WriteUInt(ELASTIC_ROPE_G, 8)
        net.WriteUInt(ELASTIC_ROPE_B, 8)
    net.Broadcast()

    self._elasticNextShotT = CurTime() + ELASTIC_DURATION +
        RETRACT_BLOCK_PAD +
        math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
end

-- ============================================================
--  _GekkoElastic_Cleanup
-- ============================================================
function ENT:_GekkoElastic_Cleanup()
    if IsValid(self._elasticAnchorG) then self._elasticAnchorG:Remove() end
    if IsValid(self._elasticAnchorE) then self._elasticAnchorE:Remove() end
    self._elasticAnchorG  = nil
    self._elasticAnchorE  = nil
    self._elasticActive   = false
    self._elasticEnemy    = nil
    self._elasticRetractUntil = CurTime() + RETRACT_BLOCK_PAD

    if self._elasticNextShotT < CurTime() then
        self._elasticNextShotT = CurTime() +
            math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    end
end

-- ============================================================
--  GekkoElastic_OnOwnerDeath  (called from init.lua death hook)
-- ============================================================
function ENT:GekkoElastic_OnOwnerDeath()
    if not self._elasticActive then return end
    local activeEnemy = self._elasticEnemy
    local breakPos = IsValid(activeEnemy) and
        (activeEnemy:GetPos() + Vector(0, 0, 40)) or Vector(0,0,0)
    self:_GekkoElastic_Cleanup()
    net.Start("GekkoElasticBreak")
        net.WriteEntity(activeEnemy or game.GetWorld())
        net.WriteVector(breakPos)
    net.Broadcast()
end
