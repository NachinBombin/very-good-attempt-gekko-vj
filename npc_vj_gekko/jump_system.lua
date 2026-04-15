-- ============================================================
--  npc_vj_gekko / jump_system.lua
-- ============================================================
-- Handles the Gekko's free-roam jump (not targeted at a specific
-- enemy position).  State machine:
--   JUMP_NONE -> JUMP_RISING -> JUMP_FALLING -> JUMP_LAND -> JUMP_NONE
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

-- How long the Gekko stays in JUMP_LAND before returning to JUMP_NONE.
local JUMP_LAND_LOCKOUT      = 0.35
-- Extra suppress pad after the land lockout so the landing anim
-- fully completes before movement / attacks resume.
local JUMP_LAND_SUPPRESS_PAD = 0.15

-- Watchdog: if the jump state machine gets stuck, force it back to
-- JUMP_NONE after this many seconds.
local JUMP_WATCHDOG_TIME = 6.0

-- Minimum time between consecutive jumps.
local JUMP_COOLDOWN = 4.0

-- Vertical launch velocity.
local JUMP_LAUNCH_Z = 450

-- How far ahead of the Gekko to aim the jump landing.
local JUMP_FORWARD_BIAS = 200

-- Only jump if the enemy is at least this far away (2D).
local JUMP_MIN_DIST_2D = 300

-- Jump probability per think tick (throttled by JUMP_COOLDOWN).
local JUMP_CHANCE = 0.004

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function GekkoIsGrounded( ent )
    local tr = util.TraceLine({
        start  = ent:GetPos() + Vector(0,0,4),
        endpos = ent:GetPos() - Vector(0,0,12),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit
end

local function ForceSeq( ent, seqName )
    local idx = ent:LookupSequence(seqName)
    if idx and idx ~= -1 then
        ent:ResetSequence(idx)
        ent:SetPlaybackRate(1)
        ent.VJ_IsMoving     = false
        ent.VJ_CanMoveThink = false
    end
end

local function GetGekkoJumpTimer( ent )
    return ent._gekkoJumpTimer or 0
end

-- ── Public state accessors ────────────────────────────────────────────────────

function ENT:GetGekkoJumpState()
    return self._gekkoJumpState or JUMP_NONE
end

function ENT:SetGekkoJumpState( s )
    self._gekkoJumpState = s
end

function ENT:GetGekkoJumpTimer()
    return self._gekkoJumpTimer or 0
end

-- ── Init ──────────────────────────────────────────────────────────────────────

function ENT:GekkoJump_Init()
    self._gekkoJumpState    = JUMP_NONE
    self._gekkoJumpTimer    = 0
    self._gekkoJumpCooldown = 0
    self._jumpLastState     = JUMP_NONE
end

function ENT:GekkoJump_Activate()
    -- nothing needed post-spawn for the free-roam jump
end

-- ── Think ─────────────────────────────────────────────────────────────────────

function ENT:GekkoJump_Think()
    local state    = self:GetGekkoJumpState()
    local vel      = self:GetVelocity()
    local grounded = GekkoIsGrounded(self)
    local now      = CurTime()

    -- ── One-shot flags on state ENTRY only (not every tick) ──────────
    -- _gekkoSuppressActivity, VJ_IsMoving, VJ_CanMoveThink are set by
    -- ForceSeq() at state transitions.  Re-stamping them every tick was
    -- permanently blocking VJBase range attack scheduling.
    if state ~= self._jumpLastState then
        if state == JUMP_RISING or state == JUMP_FALLING then
            self.VJ_IsMoving     = false
            self.VJ_CanMoveThink = false
        end
        -- FIX: JUMP_LAND one-shot entry flags (was re-stamped every tick).
        if state == JUMP_LAND then
            self.VJ_IsMoving               = false
            self.VJ_CanMoveThink           = false
            self._gekkoSuppressActivity    = CurTime() + JUMP_LAND_LOCKOUT + JUMP_LAND_SUPPRESS_PAD
        end
        self._jumpLastState = state
    end

    -- Velocity damping while landed (safe to run every tick; no timer re-stamp).
    if state == JUMP_LAND then
        local cv = self:GetVelocity()
        if math.abs(cv.x) > 0.5 or math.abs(cv.y) > 0.5 then
            self:SetVelocity(Vector(0, 0, cv.z))
        end
    end

    -- Angle correction while airborne
    if state == JUMP_RISING or state == JUMP_FALLING then
        local a = self:GetAngles()
        if math.abs(a.p) > 0.5 or math.abs(a.r) > 0.5 then
            self:SetAngles(Angle(0, a.y, 0))
        end
    end

    -- ── State transitions ────────────────────────────────────────────
    if state == JUMP_NONE then
        -- Chance to initiate a jump
        if now < self._gekkoJumpCooldown then return end
        if self._gekkoAerialMode          then return end
        if self._gekkoLegsDisabled        then return end
        if not grounded                   then return end
        local enemy = self.VJ_TheEnemy
        if not IsValid(enemy) then enemy = self:GetEnemy() end
        if not IsValid(enemy) then return end
        local dist2d = (self:GetPos() - enemy:GetPos())
        dist2d.z = 0
        if dist2d:Length() < JUMP_MIN_DIST_2D then return end
        if math.random() > JUMP_CHANCE then return end

        -- Launch
        ForceSeq(self, "jump_start")
        self:SetGekkoJumpState(JUMP_RISING)
        self._gekkoJumpTimer    = now + JUMP_WATCHDOG_TIME
        self._gekkoJumpCooldown = now + JUMP_COOLDOWN
        self._gekkoJustJumped   = now + 0.3

        local fwd = self:GetForward()
        local launchVel = fwd * 300 + Vector(0, 0, JUMP_LAUNCH_Z)
        self:SetVelocity(launchVel)

        self:SetNWInt("GekkoJumpDust", (self:GetNWInt("GekkoJumpDust",0) + 1) % 256)
        return
    end

    if state == JUMP_RISING then
        if vel.z <= 0 then
            ForceSeq(self, "jump_fall")
            self:SetGekkoJumpState(JUMP_FALLING)
        end
        if now > GetGekkoJumpTimer(self) then
            self:SetGekkoJumpState(JUMP_NONE)
            self.VJ_IsMoving     = true
            self.VJ_CanMoveThink = true
        end
        return
    end

    if state == JUMP_FALLING then
        if grounded then
            ForceSeq(self, "jump_land")
            self:SetGekkoJumpState(JUMP_LAND)
            self:SetNWInt("GekkoLandDust", (self:GetNWInt("GekkoLandDust",0) + 1) % 256)
        end
        if now > GetGekkoJumpTimer(self) then
            self:SetGekkoJumpState(JUMP_NONE)
            self.VJ_IsMoving     = true
            self.VJ_CanMoveThink = true
        end
        return
    end

    if state == JUMP_LAND then
        if now > GetGekkoJumpTimer(self) then
            self:SetGekkoJumpState(JUMP_NONE)
            self.VJ_IsMoving     = true
            self.VJ_CanMoveThink = true
            self:GekkoResetAttackReadiness()
        end
        return
    end
end
