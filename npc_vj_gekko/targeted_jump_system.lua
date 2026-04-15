-- ============================================================
--  npc_vj_gekko / targeted_jump_system.lua
--
--  Ballistic targeted jump system for the Gekko NPC.
--  Uses the same animation sequences (jump / fall / land) and
--  the same JUMP_RISING / JUMP_FALLING / JUMP_LAND state values
--  as jump_system.lua, but instead of a random vertical force it
--  solves the correct launch velocity to land on the current enemy.
--
--  KEY DESIGN RULE: this system owns _tjStateLOCAL, a completely
--  separate variable from jump_system.lua's _jumpStateLOCAL.
--  Both systems write to SetGekkoJumpState() (the shared NW int
--  read by the client), but they guard each other by checking
--  GetGekkoJumpState() == JUMP_NONE before firing.
--
--  Integration in init.lua (already present):
--    include("targeted_jump_system.lua")   -- top of file
--    self:GekkoTargetJump_Init()           -- inside Init()
--    self:GekkoTargetJump_Think()          -- inside OnThink()
-- ============================================================

-- Shared state constants (must match jump_system.lua)
local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

-- ── Ballistic tuning ─────────────────────────────────────────
-- Must match sv_gravity (default 600 u/s^2).
local TJ_GRAVITY            = 600

-- Vertical launch speed for targets ABOVE the Gekko.
local TJ_VZ_ASCENDING       = 1200
-- Vertical launch speed for targets at equal height or BELOW.
local TJ_VZ_DESCENDING      = 700
-- If the target's z-position is more than this above the Gekko, use ascending vz.
local TJ_HEIGHT_ASCEND_THRESH = 80

-- Horizontal speed limits.
local TJ_VXY_MAX            = 1800
local TJ_VXY_MIN            = 80

-- When the discriminant is still negative after the initial guess,
-- boost vz by this step and retry once.
local TJ_VZ_BOOST_STEP      = 200
local TJ_VZ_BOOST_MAX       = 1600

-- ── Cooldown / distance guards ───────────────────────────────
local TJ_COOLDOWN_MIN       = 7.0
local TJ_COOLDOWN_MAX       = 20.0
local TJ_MIN_ENEMY_DIST     = 500
local TJ_MAX_ENEMY_DIST     = 6000
local TJ_POST_LAND_COOLDOWN = 3.0
local TJ_LAND_LOCKOUT       = 1.4
local TJ_LAND_SUPPRESS_PAD  = 1.1
local TJ_RISING_TIMEOUT     = 1.8
local TJ_GROUND_DIST        = 24

-- Small XY jitter so the Gekko does not land pixel-perfectly every time.
local TJ_JITTER_XY          = 80

-- ============================================================
--  Internal helpers (prefixed TJ_ to avoid colliding with
--  the identically-named helpers in jump_system.lua)
-- ============================================================

local function TJ_GetLocalState(ent)
    return ent._tjStateLOCAL or JUMP_NONE
end

local function TJ_SetLocalState(ent, state)
    ent._tjStateLOCAL = state
    -- Drive the shared NW int so cl_init.lua sees the correct state
    -- regardless of which system fired.
    ent:SetGekkoJumpState(state)
end

local function TJ_IsGrounded(ent)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local tr = util.TraceHull({
        start  = ent:GetPos(),
        endpos = ent:GetPos() + Vector(0, 0, -TJ_GROUND_DIST),
        mins   = Vector(mins.x * 0.5, mins.y * 0.5, 0),
        maxs   = Vector(maxs.x * 0.5, maxs.y * 0.5, 4),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit
end

local function TJ_ForceSeq(ent, seq, rate, suppressDur, label)
    ent:ResetSequence(seq)
    ent:SetCycle(0)
    ent:SetPlaybackRate(rate)
    ent.Gekko_LastSeqIdx       = seq
    ent.Gekko_LastSeqName      = label or "jump_phase"
    ent._gekkoSuppressActivity = CurTime() + suppressDur
    ent.VJ_IsMoving            = false
    ent.VJ_CanMoveThink        = false
end

-- ============================================================
--  Ballistic solver
--
--  Projectile physics (Source Engine):
--    z(t) = vz*t - 0.5*g*t^2
--    d(t) = vxy*t          (horizontal)
--
--  Given a fixed vz, time-of-flight T satisfies:
--    dZ = vz*T - 0.5*g*T^2
--    => 0.5*g*T^2 - vz*T + dZ = 0
--    => T = (vz +/- sqrt(vz^2 - 2*g*dZ)) / g
--  Then: vxy = dXY / T
--
--  Returns { vz, vxy, tof, valid=true } or nil.
-- ============================================================
local function TJ_Solve(selfPos, targetPos)
    local dXY = Vector(targetPos.x - selfPos.x, targetPos.y - selfPos.y, 0):Length()
    local dZ  = targetPos.z - selfPos.z

    local vz = (dZ > TJ_HEIGHT_ASCEND_THRESH) and TJ_VZ_ASCENDING or TJ_VZ_DESCENDING

    for attempt = 1, 2 do
        -- disc = vz^2 - 2*g*dZ   (simplified form of the full quadratic discriminant)
        local disc = vz * vz - 2 * TJ_GRAVITY * dZ

        if disc >= 0 then
            local sqrtD = math.sqrt(disc)
            -- t1 = smaller root (direct, faster arc)
            -- t2 = larger root  (high lob arc)
            local t1 = (vz - sqrtD) / TJ_GRAVITY
            local t2 = (vz + sqrtD) / TJ_GRAVITY

            -- Prefer t1 (direct arc); fall back to t2 if t1 <= 0 (descending target)
            local t
            if t1 > 0.05 then
                t = t1
            elseif t2 > 0.05 then
                t = t2
            end

            if t then
                local vxy = (dXY > 1) and (dXY / t) or 0
                vxy = math.Clamp(vxy, TJ_VXY_MIN, TJ_VXY_MAX)
                print(string.format(
                    "[GekkoTargetJump] Solved | dXY=%.0f dZ=%.0f vz=%.0f vxy=%.0f tof=%.2fs",
                    dXY, dZ, vz, vxy, t
                ))
                return { vz = vz, vxy = vxy, tof = t, valid = true }
            end
        end

        -- Boost vz and retry once
        if attempt == 1 then
            vz = math.min(vz + TJ_VZ_BOOST_STEP, TJ_VZ_BOOST_MAX)
        end
    end

    print(string.format(
        "[GekkoTargetJump] Solver FAILED | dXY=%.0f dZ=%.0f",
        dXY, dZ
    ))
    return nil
end

-- ============================================================
--  Init
-- ============================================================
function ENT:GekkoTargetJump_Init()
    self._tjStateLOCAL      = JUMP_NONE
    self._tjCooldown        = CurTime() + TJ_POST_LAND_COOLDOWN
    self._tjLandCooldown    = CurTime() + TJ_POST_LAND_COOLDOWN
    self._tjJustJumped      = 0
    self._tjRisingStartTime = 0
    self._tjDidLiftoff      = false
    self._tjLastState       = JUMP_NONE
    self._tjThinkPrint      = 0
    -- _seqJump / _seqFall / _seqLand are set by GekkoJump_Activate() in
    -- jump_system.lua; no separate lookup needed here.
    print("[GekkoTargetJump] Init() called")
end

-- ============================================================
--  ShouldJump
-- ============================================================
function ENT:GekkoTargetJump_ShouldJump()
    if self._tjCooldown          > CurTime() then return false end
    if self._tjLandCooldown      > CurTime() then return false end
    if TJ_GetLocalState(self)   ~= JUMP_NONE  then return false end
    -- Block if the random jump system is currently mid-air.
    if self:GetGekkoJumpState() ~= JUMP_NONE  then return false end
    if not self:IsOnGround()                   then return false end
    if self._mgBurstActive                     then return false end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return false end

    local dist = self:GetPos():Distance2D(enemy:GetPos())
    if dist < TJ_MIN_ENEMY_DIST or dist > TJ_MAX_ENEMY_DIST then return false end

    return true
end

-- ============================================================
--  Execute
-- ============================================================
function ENT:GekkoTargetJump_Execute()
    if TJ_GetLocalState(self) ~= JUMP_NONE then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return end

    -- Add a small jitter so the landing spot is not always identical.
    local aimPos = enemy:GetPos() + Vector(
        math.Rand(-TJ_JITTER_XY, TJ_JITTER_XY),
        math.Rand(-TJ_JITTER_XY, TJ_JITTER_XY),
        40
    )

    local sol = TJ_Solve(self:GetPos(), aimPos)
    if not sol then
        -- No valid arc: back off with a long cooldown.
        self._tjCooldown = CurTime() + TJ_COOLDOWN_MAX
        return
    end

    -- Orient toward the target before launching.
    local fwd = (aimPos - self:GetPos())
    fwd.z = 0
    fwd:Normalize()
    self:SetAngles(Angle(0, fwd:Angle().y, 0))

    self:SetMoveType(MOVETYPE_FLYGRAVITY)

    local vel = self:GetVelocity()
    vel.z     = sol.vz
    vel       = vel + fwd * sol.vxy
    self:SetVelocity(vel)

    self:SetSchedule(SCHED_NONE)

    TJ_SetLocalState(self, JUMP_RISING)
    self._tjLastState       = JUMP_RISING
    self._tjCooldown        = CurTime() + math.Rand(TJ_COOLDOWN_MIN, TJ_COOLDOWN_MAX)
    self._tjJustJumped      = CurTime() + 0.3
    self._tjRisingStartTime = CurTime()
    self._tjDidLiftoff      = false
    self._tjLandCooldown    = 0

    -- Animations -- reuse sequences from jump_system.lua's Activate().
    if self._seqJump and self._seqJump ~= -1 then
        TJ_ForceSeq(self, self._seqJump, 1.0, 0.5, "jump")
    end

    -- FX -- reuse all existing hooks.
    self:GeckoCrush_LaunchBlast()
    self:SetNWInt("GekkoJumpDust", (self:GetNWInt("GekkoJumpDust", 0) + 1) % 255)
    self:GekkoJump_StartJetFX()

    print(string.format(
        "[GekkoTargetJump] LAUNCH | vz=%.0f vxy=%.0f tof=%.2fs dZ=%.0f",
        sol.vz, sol.vxy, sol.tof, aimPos.z - self:GetPos().z
    ))
end

-- ============================================================
--  Think  (runs every frame from OnThink)
-- ============================================================
function ENT:GekkoTargetJump_Think()
    -- Gate check every frame; Execute() only fires when everything is clear.
    if self:GekkoTargetJump_ShouldJump() then
        self:GekkoTargetJump_Execute()
    end

    local state = TJ_GetLocalState(self)
    if state == JUMP_NONE then
        self._tjLastState = JUMP_NONE
        return
    end

    local vel      = self:GetVelocity()
    local grounded = TJ_IsGrounded(self)
    local now      = CurTime()

    -- One-shot per-state flags (entry only, not every tick).
    if state ~= self._tjLastState then
        if state == JUMP_RISING or state == JUMP_FALLING then
            self.VJ_IsMoving     = false
            self.VJ_CanMoveThink = false
        end
        self._tjLastState = state
    end

    if state == JUMP_LAND then
        local cv = self:GetVelocity()
        if math.abs(cv.x) > 0.5 or math.abs(cv.y) > 0.5 then
            self:SetVelocity(Vector(0, 0, cv.z))
        end
        self.VJ_IsMoving               = false
        self.VJ_CanMoveThink           = false
        self._gekkoSuppressActivity    = now + 0.2
    end

    -- Prevent physics from tumbling the Gekko mid-air.
    if state == JUMP_RISING or state == JUMP_FALLING then
        local a = self:GetAngles()
        if math.abs(a.p) > 0.5 or math.abs(a.r) > 0.5 then
            self:SetAngles(Angle(0, a.y, 0))
        end
    end

    -- Throttled debug print.
    if now > self._tjThinkPrint then
        print(string.format(
            "[GekkoTargetJump] Think | state=%d velZ=%.1f grounded=%s",
            state, vel.z, tostring(grounded)
        ))
        self._tjThinkPrint = now + 0.25
    end

    -- ── RISING ──────────────────────────────────────────────────
    if state == JUMP_RISING then
        if vel.z > 50 then self._tjDidLiftoff = true end

        -- Abort if never left the ground within the timeout.
        if not self._tjDidLiftoff and
           (now - self._tjRisingStartTime) > TJ_RISING_TIMEOUT then
            TJ_SetLocalState(self, JUMP_NONE)
            self._tjLastState           = JUMP_NONE
            self:SetGekkoJumpTimer(0)
            self:SetMoveType(MOVETYPE_STEP)
            self:SetVelocity(Vector(0, 0, 0))
            self.Gekko_LastSeqIdx       = -1
            self.Gekko_LastSeqName      = ""
            self._gekkoSuppressActivity = now + 0.15
            self.VJ_CanMoveThink        = true
            self._tjCooldown            = now + TJ_COOLDOWN_MAX * 2
            self._tjLandCooldown        = now + TJ_POST_LAND_COOLDOWN
            self:GekkoJump_StopJetFX()
            if self._gekkoCrouching then self._gekkoCrouchJustEntered = true end
            return
        end

        -- Loop the middle of the jump sequence while ascending.
        if self._seqJump and self._seqJump ~= -1 then
            if self:GetSequence() ~= self._seqJump then
                self:ResetSequence(self._seqJump)
                self:SetPlaybackRate(0.8)
            end
            if self:GetCycle() > 0.90 then self:SetCycle(0.5) end
        end

        -- Switch to FALLING when vertical velocity goes negative.
        if vel.z < 0 then
            TJ_SetLocalState(self, JUMP_FALLING)
            self._tjLastState = JUMP_FALLING
            self:GekkoJump_StopJetFX()
            if self._seqFall and self._seqFall ~= -1 then
                TJ_ForceSeq(self, self._seqFall, 1.0, 0.5, "fall")
            end
            return
        end
    end

    -- ── FALLING ─────────────────────────────────────────────────
    if state == JUMP_FALLING then
        if self._seqFall and self._seqFall ~= -1 then
            if self:GetSequence() ~= self._seqFall then
                self:ResetSequence(self._seqFall)
                self:SetPlaybackRate(0.8)
            end
            if self:GetCycle() > 0.90 then self:SetCycle(0.5) end
        end
    end

    -- ── FALLING -> LAND ─────────────────────────────────────────
    if state == JUMP_FALLING and grounded then
        TJ_SetLocalState(self, JUMP_LAND)
        self._tjLastState = JUMP_LAND
        self:SetGekkoJumpTimer(now + TJ_LAND_LOCKOUT)
        self:SetMoveType(MOVETYPE_STEP)

        self:SetVelocity(Vector(0, 0, 0))
        local selfRef = self
        timer.Simple(0, function()
            if IsValid(selfRef) and TJ_GetLocalState(selfRef) == JUMP_LAND then
                selfRef:SetVelocity(Vector(0, 0, 0))
            end
        end)

        local a = self:GetAngles()
        self:SetAngles(Angle(0, a.y, 0))
        if self._seqLand and self._seqLand ~= -1 then
            TJ_ForceSeq(self, self._seqLand, 1.0,
                TJ_LAND_LOCKOUT + TJ_LAND_SUPPRESS_PAD, "land")
        end

        self._tjLandCooldown = now + TJ_LAND_LOCKOUT + TJ_POST_LAND_COOLDOWN
        self:GekkoJump_LandImpact()
        return
    end

    -- ── LAND -> NONE ────────────────────────────────────────────
    if state == JUMP_LAND and now > self:GetGekkoJumpTimer() then
        TJ_SetLocalState(self, JUMP_NONE)
        self._tjLastState           = JUMP_NONE
        self:SetGekkoJumpTimer(0)
        self.Gekko_LastSeqIdx       = -1
        self.Gekko_LastSeqName      = ""
        self._gekkoSuppressActivity = now + 0.08
        self._gekkoSkipAnimTick     = true
        if self.GekkoSeq_Idle and self.GekkoSeq_Idle ~= -1 then
            self:ResetSequence(self.GekkoSeq_Idle)
            self:SetPlaybackRate(1.0)
            self.Gekko_LastSeqIdx  = self.GekkoSeq_Idle
            self.Gekko_LastSeqName = "idle"
        end
        self.VJ_CanMoveThink = true
        if self._gekkoCrouching then self._gekkoCrouchJustEntered = true end
    end
end

-- ============================================================
--  Utility
-- ============================================================
function ENT:GekkoTargetJump_IsAirborne()
    local s = TJ_GetLocalState(self)
    return s == JUMP_RISING or s == JUMP_FALLING
end