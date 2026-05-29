-- ============================================================
--  npc_vj_gekko / init.lua  (SERVER)
-- ============================================================
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("elastic_cl.lua")
AddCSLuaFile("muzzleflash_system.lua")
AddCSLuaFile("bullet_impact_system.lua")
AddCSLuaFile("hit_react_cl.lua")
AddCSLuaFile("cl_aps.lua")
AddCSLuaFile("mg_shell_system.lua")

include("shared.lua")
include("crouch_system.lua")
include("pedestal_dodge_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("elastic_system.lua")
include("crush_system.lua")
include("gib_system.lua")
include("aps_system.lua")
include("death_pose_system.lua")
include("leg_disable_system.lua")

-- ============================================================
--  Net message pool
-- ============================================================
util.AddNetworkString("GekkoCrushHit")
util.AddNetworkString("GekkoSonarLock")

-- ============================================================
--  Animation speed constants
-- ============================================================
local ANIM_RUN_SPEED  = 284
local ANIM_WALK_SPEED = 100

-- Jump state IDs (mirror shared.lua / jump_system.lua)
local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel(self.Model[1])
    self:SetHullType(self.HullType)
    self:SetHullSizeNormal()
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetBloodColor(BLOOD_COLOR_RED)
    self:CapabilitiesAdd(
        bit.bor(
            CAP_MOVE_GROUND,
            CAP_OPEN_DOORS,
            CAP_TURN_HEAD,
            CAP_ANIMATEDFACE
        )
    )

    self.BaseClass.Initialize(self)

    -- ── System inits ──────────────────────────────────────────
    self:GeckoCrouch_Init()
    self:PedestalDodge_Init()
    self:GekkoJump_Init()
    self:TargetedJump_Init()
    self:ElasticSystem_Init()
    self:CrushSystem_Init()
    self:GibSystem_Init()
    self:APS_Init()
    self:DeathPose_Init()
    self:LegDisable_Init()

    -- ── Animation state ───────────────────────────────────────
    self._gekkoRunning          = false
    self._gekkoLastSpeed        = 0
    self._gekkoDead             = false
    self._gekkoSuppressActivity = 0
    self.Flinching              = false

    -- Cache crouch sequences now the model is bound
    self:GeckoCrouch_CacheSeqs()

    -- Spine bone index (head tracking; also used by server)
    self._spineBoneIdx = self:LookupBone("b_spine3") or -1

    -- Default standing collision bounds
    self:SetCollisionBounds(
        Vector(-64, -64,   0),
        Vector( 64,  64, 200)
    )

    -- NetworkVar defaults
    self:SetNWBool("GekkoIsCrouching",      false)
    self:SetNWBool("GekkoMGFiring",         false)
    self:SetNWFloat("GekkoSpeed",           0)
    self:SetNWInt("GekkoJumpDust",          0)
    self:SetNWInt("GekkoLandDust",          0)
    self:SetNWInt("GekkoFK360LandDust",     0)
    self:SetNWInt("GekkoBloodSplat",        0)
    self:SetNWInt("GekkoKickPulse",         0)
    self:SetNWInt("GekkoLKickPulse",        0)
    self:SetNWInt("GekkoHeadbuttPulse",     0)
    self:SetNWInt("GekkoFrontKick360Pulse",  0)
    self:SetNWInt("GekkoFrontKick360BPulse", 0)
    self:SetNWInt("GekkoSpinKickPulse",     0)
    self:SetNWEntity("GekkoEnemy",          NULL)

    self:SetGekkoJumpState(JUMP_NONE)
end

-- ============================================================
--  Precache
-- ============================================================
function ENT:Precache()
    self.BaseClass.Precache(self)
    util.PrecacheModel("models/metal_gear_solid_4/enemies/gekko.mdl")
end

-- ============================================================
--  TraceAttack  — suppress all decals/damage during invuln window
-- ============================================================
function ENT:TraceAttack(dmginfo, dir, trace)
    if self._gekkoDead then return end

    if CurTime() < (self._gekkoInvulnUntil or 0) then
        -- Zero damage and suppress blood/bullet-hole decals entirely
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        return
    end

    -- Kill VJ flinch any tick we are crouching (prevents crouch-bounce)
    if self._gekkoCrouching then
        self.Flinching = false
    end

    self.BaseClass.TraceAttack(self, dmginfo, dir, trace)
end

-- ============================================================
--  OnTakeDamage  — reactive dodge + invuln suppression
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    if self._gekkoDead then return end

    -- Full invuln window: zero damage, suppress flinch, return
    if CurTime() < (self._gekkoInvulnUntil or 0) then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        self.Flinching = false
        return
    end

    -- APS intercept (active protection system)
    if self.APS_OnTakeDamage and self:APS_OnTakeDamage(dmginfo) then
        return
    end

    -- Reactive dodge on bullet/blast hit (sets invuln window internally)
    if self:PedestalDodge_OnHit(dmginfo) then
        self.Flinching = false
        return
    end

    -- Normal VJ damage path
    self.BaseClass.OnTakeDamage(self, dmginfo)

    -- Kill flinch while crouching so the hold lock is never broken
    if self._gekkoCrouching then
        self.Flinching = false
    end
end

-- ============================================================
--  GekkoUpdateAnimation  — called every Think tick
--
--  FIX: Flinch kill runs at the very top, BEFORE any early
--  return.  Previously the kill lived inside GeckoCrouch_Update
--  which could be bypassed by early returns higher up, leaving
--  a race window where VJ Base reasserted the stand animation
--  mid-dodge and caused violent up-down snapping.
-- ============================================================
function ENT:GekkoUpdateAnimation()
    -- ── Unconditional flinch kill ─────────────────────────────
    -- Must be first; must not be gated by any condition.
    -- Covers: normal crouch, dodge slide, pedestal slide.
    local dodgeActive = self._gekkoDodgeCrouch
                        and CurTime() < (self._gekkoDodgeCrouchUntil or 0)
    local slideActive = self._pedestalSliding
    if self._gekkoCrouching or dodgeActive or slideActive then
        self.Flinching = false
    end
    -- ─────────────────────────────────────────────────────────

    if self._gekkoDead then return end

    -- ── Crouch system owns the sequence when active ───────────
    if self:GeckoCrouch_Update() then
        return
    end

    -- ── Jump animation ────────────────────────────────────────
    if self:GekkoJump_UpdateAnim() then
        return
    end

    -- ── Locomotion (walk / run / idle) ────────────────────────
    local vel   = self:GetVelocity()
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    self:SetNWFloat("GekkoSpeed", speed)

    if speed > 5 then
        local isRunning = speed > ANIM_WALK_SPEED
        local baseSpeed = isRunning and ANIM_RUN_SPEED or ANIM_WALK_SPEED
        local rate      = math.Clamp(speed / baseSpeed, 0.4, 2.0)
        local seqName   = isRunning and "run" or "walk"
        local seq       = self:LookupSequence(seqName)
        if seq and seq ~= -1 then
            self:ResetSequence(seq)
            self:SetPlaybackRate(rate)
        end
        self._gekkoRunning = isRunning
    else
        if self._gekkoRunning or speed <= 1 then
            local idleSeq = self:LookupSequence("idle")
            if idleSeq and idleSeq ~= -1 then
                self:ResetSequence(idleSeq)
                self:SetPlaybackRate(1.0)
            end
            self._gekkoRunning = false
        end
    end
end

-- ============================================================
--  Think
-- ============================================================
function ENT:Think()
    if not self._gekkoDead then
        -- Speed NW var (footstep / shake sync on client)
        local vel   = self:GetVelocity()
        local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
        self:SetNWFloat("GekkoSpeed", speed)

        -- Enemy tracking for client head-driver
        local enemy = self:GetEnemy()
        self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)

        -- Random strafe (no crouch)
        self:PedestalDodge_ThinkStrafe()

        -- Jump systems
        self:GekkoJump_Think()
        self:TargetedJump_Think()

        -- Elastic tentacle system
        self:ElasticSystem_Think()

        -- Animation
        self:GekkoUpdateAnimation()
    end

    self:NextThink(CurTime())
    return true
end

-- ============================================================
--  OnRemove
-- ============================================================
function ENT:OnRemove()
    if self.BaseClass.OnRemove then
        self.BaseClass.OnRemove(self)
    end
end

-- ============================================================
--  VJ Base hooks
-- ============================================================

-- VJ Base calls this every tick instead of managing sequences itself
-- when VJ_NPC_UsesCustomMoveAnimation = true.
function ENT:VJ_OnUpdateAnimation()
    self:GekkoUpdateAnimation()
end

-- Returning true blocks VJ Base from overwriting our sequence.
function ENT:VJ_OnBeforeSetMoveSequence()
    if self._gekkoCrouching or self._pedestalSliding then
        return true
    end
    return false
end

-- VJ Base death hook
function ENT:VJ_OnDeath(dmginfo)
    self._gekkoDead = true
    self:SetNWBool("GekkoMGFiring", false)
    self:DeathPose_Apply(dmginfo)
    if self.GibSystem_OnDeath then
        self:GibSystem_OnDeath(dmginfo)
    end
end

-- ============================================================
--  Range attack  — MG burst / missiles via CrushSystem
-- ============================================================
function ENT:CustomRangeAttack1(pos, ent)
    if not IsValid(ent) then return end
    self:CrushSystem_SelectAndFire(ent)
end
