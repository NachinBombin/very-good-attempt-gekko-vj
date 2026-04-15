-- ============================================================
--  npc_vj_gekko / targeted_jump_system.lua
-- ============================================================
--  Handles the Gekko's targeted jump (leaps directly toward the
--  enemy).  Shares the same JUMP_RISING / JUMP_FALLING / JUMP_LAND
--  the same JUMP_RISING / JUMP_FALLING / JUMP_LAND state values
--  as jump_system.lua but uses its own state variable so the two
--  systems don't interfere.
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

-- How long the Gekko stays in JUMP_LAND before returning to JUMP_NONE.
local TJ_LAND_LOCKOUT      = 0.35
-- Extra suppress pad after the land lockout.
local TJ_LAND_SUPPRESS_PAD = 0.15

-- Watchdog timeout for the whole jump.
local TJ_WATCHDOG_TIME = 8.0

-- Minimum time between consecutive targeted jumps.
local TJ_COOLDOWN = 6.0

-- Vertical component of the launch velocity.
local TJ_LAUNCH_Z = 500

-- Horizontal launch speed toward the target.
local TJ_LAUNCH_XY = 500

-- Only perform a targeted jump if the enemy is at least this far
-- away (2D distance).
local TJ_MIN_DIST_2D = 500

-- Maximum 2D distance for a targeted jump to be worthwhile.
local TJ_MAX_DIST_2D = 3000

-- Probability per think tick that a targeted jump is initiated
-- (subject to cooldown and distance checks).
local TJ_CHANCE = 0.003

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function TJ_IsGrounded( ent )
    local tr = util.TraceLine({
        start  = ent:GetPos() + Vector(0,0,4),
        endpos = ent:GetPos() - Vector(0,0,12),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit
end

local function TJ_ForceSeq( ent, seqName )
    local idx = ent:LookupSequence(seqName)
    if idx and idx ~= -1 then
        ent:ResetSequence(idx)
        ent:SetPlaybackRate(1)
        ent.VJ_IsMoving     = false
        ent.VJ_CanMoveThink = false
    end
end

local function TJ_GetLocalState( ent )
    return ent._gekkoTJState or JUMP_NONE
end

local function TJ_SetLocalState( ent, s )
    ent._gekkoTJState = s
end

-- ── Init ──────────────────────────────────────────────────────────────────────

function ENT:GekkoTargetJump_Init()
    self._gekkoTJState    = JUMP_NONE
    self._gekkoTJTimer    = 0
    self._gekkoTJCooldown = 0
    self._tjLastState     = JUMP_NONE
end

-- ── Think ─────────────────────────────────────────────────────────────────────

function ENT:GekkoTargetJump_Think()
    local state    = TJ_GetLocalState(self)
    local grounded = TJ_IsGrounded(self)
    local now      = CurTime()

    -- One-shot per-state flags (entry only, not every tick).
    if state ~= self._tjLastState then
        if state == JUMP_RISING or state == JUMP_FALLING then
            self.VJ_IsMoving     = false
            self.VJ_CanMoveThink = false
        end
        -- FIX: JUMP_LAND one-shot entry flags (was re-stamped every tick).
        if state == JUMP_LAND then
            self.VJ_IsMoving               = false
            self.VJ_CanMoveThink           = false
            self._gekkoSuppressActivity    = CurTime() + TJ_LAND_LOCKOUT + TJ_LAND_SUPPRESS_PAD
        end
        self._tjLastState = state
    end

    -- Velocity damping while landed (safe to run every tick; no timer re-stamp).
    if state == JUMP_LAND then
        local cv = self:GetVelocity()
        if math.abs(cv.x) > 0.5 or math.abs(cv.y) > 0.5 then
            self:SetVelocity(Vector(0, 0, cv.z))
        end
    end

    -- Prevent physics from tumbling the Gekko mid-air.
    if state == JUMP_RISING or state == JUMP_FALLING then
        local a = self:GetAngles()
        if math.abs(a.p) > 0.5 or math.abs(a.r) > 0.5 then
            self:SetAngles(Angle(0, a.y, 0))
        end
    end

    -- ── State transitions ────────────────────────────────────────────
    if state == JUMP_NONE then
        if now < self._gekkoTJCooldown  then return end
        if self._gekkoAerialMode        then return end
        if self._gekkoLegsDisabled      then return end
        if not grounded                 then return end

        local enemy = self.VJ_TheEnemy
        if not IsValid(enemy) then enemy = self:GetEnemy() end
        if not IsValid(enemy) then return end

        local toEnemy = enemy:GetPos() - self:GetPos()
        local dist2d  = Vector(toEnemy.x, toEnemy.y, 0):Length()
        if dist2d < TJ_MIN_DIST_2D or dist2d > TJ_MAX_DIST_2D then return end
        if math.random() > TJ_CHANCE then return end

        -- Orient toward enemy before launching.
        local faceAng = toEnemy:Angle()
        faceAng.p = 0 ; faceAng.r = 0
        self:SetAngles(faceAng)

        TJ_ForceSeq(self, "jump_start")
        TJ_SetLocalState(self, JUMP_RISING)
        self._tjLastState       = JUMP_RISING
        self._gekkoTJTimer      = now + TJ_WATCHDOG_TIME
        self._gekkoTJCooldown   = now + TJ_COOLDOWN
        self._gekkoJustJumped   = now + 0.3

        local dir2d = Vector(toEnemy.x, toEnemy.y, 0):GetNormalized()
        self:SetVelocity(dir2d * TJ_LAUNCH_XY + Vector(0, 0, TJ_LAUNCH_Z))
        self:SetNWInt("GekkoJumpDust", (self:GetNWInt("GekkoJumpDust",0) + 1) % 256)
        return
    end

    if state == JUMP_RISING then
        local vel = self:GetVelocity()
        if vel.z <= 0 then
            TJ_ForceSeq(self, "jump_fall")
            TJ_SetLocalState(self, JUMP_FALLING)
            self._tjLastState = JUMP_FALLING
        end
        if now > self._gekkoTJTimer then
            TJ_SetLocalState(self, JUMP_NONE)
            self._tjLastState           = JUMP_NONE
            self.VJ_IsMoving            = true
            self.VJ_CanMoveThink        = true
        end
        return
    end

    if state == JUMP_FALLING then
        if grounded then
            TJ_ForceSeq(self, "jump_land")
            TJ_SetLocalState(self, JUMP_LAND)
            self._tjLastState = JUMP_LAND
            self:SetNWInt("GekkoLandDust", (self:GetNWInt("GekkoLandDust",0) + 1) % 256)

            -- Face the enemy on landing.
            local selfRef = self
            timer.Simple(TJ_LAND_LOCKOUT, function()
                if not IsValid(selfRef) then return end
                if TJ_GetLocalState(selfRef) == JUMP_LAND then
                    local e = selfRef.VJ_TheEnemy
                    if not IsValid(e) then e = selfRef:GetEnemy() end
                    if IsValid(e) then
                        local a = (e:GetPos() - selfRef:GetPos()):Angle()
                        a.p = 0 ; a.r = 0
                        selfRef:SetAngles(a)
                    end
                end
            end)
        end
        if now > self._gekkoTJTimer then
            TJ_SetLocalState(self, JUMP_NONE)
            self._tjLastState           = JUMP_NONE
            self.VJ_IsMoving            = true
            self.VJ_CanMoveThink        = true
        end
        return
    end

    if state == JUMP_LAND and now > self:GetGekkoJumpTimer() then
        TJ_SetLocalState(self, JUMP_NONE)
        self._tjLastState           = JUMP_NONE
        self.VJ_IsMoving            = true
        self.VJ_CanMoveThink        = true
        self:GekkoResetAttackReadiness()
        return
    end
end
