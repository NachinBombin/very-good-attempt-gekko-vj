-- ============================================================
--  npc_vj_gekko / targeted_jump_system.lua
--
--  Ballistic targeted jump system.
--  Instead of randomized vertical / horizontal forces, this
--  system samples the enemy position every TJ_SOLVE_INTERVAL
--  seconds and solves the exact launch velocity needed to land
--  on them, accounting for any height delta (ascending or
--  descending).
--
--  Rules:
--   • Uses the identical animation sequences as jump_system.lua
--     (jump / fall / land) and re-uses GekkoJump_Think() entirely.
--   • Replaces ONLY the velocity calculation in Execute.
--   • Kicks off at most once per TJ_SOLVE_INTERVAL (4 s).
--   • Ignores trivial height differences (< TJ_MIN_DZ_ABS) so
--     the gekko does not jump over single stair steps.
--   • No upper height limit – will always attempt a jump as long
--     as it is physically solvable; if the first vz guess fails
--     the discriminant check it escalates vz until it succeeds
--     or hits TJ_VZ_MAX.
-- ============================================================

-- ── Gravity ──────────────────────────────────────────────────
-- Must match the server's sv_gravity (default 600).
-- If your map/server overrides it, change this constant.
local TJ_GRAVITY = 600

-- ── Height mode thresholds ───────────────────────────────────
-- How far above the Gekko the target must be before we switch
-- to a steeper launch angle (ascending mode).
local TJ_ASCEND_THRESH = 80        -- units

-- Minimum absolute Z-difference to consider a jump worthwhile.
-- Below this (e.g. single stair step) the system will NOT jump.
local TJ_MIN_DZ_ABS    = 60        -- units  ← "no stair jump" gate

-- ── Vertical launch speeds ───────────────────────────────────
-- Starting guess for ASCENDING targets (target is above us).
-- Will be escalated automatically if the discriminant fails.
local TJ_VZ_ASCEND_BASE  = 900

-- Starting guess for LEVEL / DESCENDING targets.
local TJ_VZ_DESCEND_BASE = 550

-- Hard cap: we will not escalate vz beyond this value.
-- Prevents moon-launches on extremely tall targets.
-- Set to a large number if you truly want no ceiling.
local TJ_VZ_MAX          = 3000

-- Step size when escalating vz after a failed discriminant.
local TJ_VZ_STEP         = 150

-- ── Horizontal speed limits ───────────────────────────────────
local TJ_VXY_MAX = 2000   -- cap to avoid supersonic slides
local TJ_VXY_MIN = 80     -- always push at least this much

-- ── Timing ───────────────────────────────────────────────────
-- How often (seconds) the solver samples the enemy position and
-- may decide to jump.  The actual jump fires immediately when the
-- solver says go; this is NOT a per-tick check.
local TJ_SOLVE_INTERVAL = 4.0

-- ── Distance limits ──────────────────────────────────────────
-- Same lower bound as the random system; no upper bound.
local TJ_MIN_ENEMY_DIST = 600

-- ============================================================
--  Internal solver
--  Returns a table { vz, vxy, valid=true } or nil on failure.
-- ============================================================
local function SolveBallisticJump( selfPos, targetPos )
    -- 2-D horizontal distance (ignore z here; z is the dZ term)
    local dx   = targetPos.x - selfPos.x
    local dy   = targetPos.y - selfPos.y
    local dXY  = math.sqrt(dx*dx + dy*dy)
    local dZ   = targetPos.z - selfPos.z

    -- Choose starting vz based on height relationship
    local vz = (dZ > TJ_ASCEND_THRESH) and TJ_VZ_ASCEND_BASE or TJ_VZ_DESCEND_BASE

    -- Escalate vz until we get a real discriminant or hit the cap.
    -- Physics: dZ = vz*t - 0.5*g*t^2
    --   rearranged: 0.5*g*t^2 - vz*t + dZ = 0
    --   discriminant: D = vz^2 - 2*g*dZ
    --   (taking the positive-t solution of the quadratic)
    local t = nil
    while vz <= TJ_VZ_MAX do
        local disc = vz * vz - 2 * TJ_GRAVITY * dZ
        if disc >= 0 then
            -- Two roots; pick the SMALLER positive one (faster, direct arc)
            local sqrtD = math.sqrt(disc)
            local t1 = (vz - sqrtD) / TJ_GRAVITY   -- smaller root
            local t2 = (vz + sqrtD) / TJ_GRAVITY   -- larger  root
            -- t1 may be negative for descending targets; fall back to t2
            if t1 > 0.05 then
                t = t1
            elseif t2 > 0.05 then
                t = t2
            end
            if t then break end
        end
        vz = vz + TJ_VZ_STEP
    end

    if not t then
        -- Could not find a valid arc even at TJ_VZ_MAX
        print("[GekkoTJ] Solver FAILED: no valid arc found (dXY=" ..
              math.floor(dXY) .. " dZ=" .. math.floor(dZ) .. ")")
        return nil
    end

    local vxy = (dXY > 1) and math.Clamp(dXY / t, TJ_VXY_MIN, TJ_VXY_MAX) or 0

    print(string.format(
        "[GekkoTJ] Solved | dXY=%.0f dZ=%.0f  vz=%.0f vxy=%.0f t=%.2fs",
        dXY, dZ, vz, vxy, t
    ))

    return { vz = vz, vxy = vxy, valid = true }
end

-- ============================================================
--  GekkoTargetJump_Init
--  Call once from ENT:Init() after GekkoJump_Init().
-- ============================================================
function ENT:GekkoTargetJump_Init()
    self._tjNextSolveTime = 0   -- when we're allowed to solve again
    self._tjPendingLaunch = nil -- cached solution waiting for ShouldJump gate
    print("[GekkoTJ] TargetJump system initialised")
end

-- ============================================================
--  GekkoTargetJump_ShouldJump
--  Identical guard conditions to GekkoJump_ShouldJump() from
--  jump_system.lua, except distance has no upper cap.
-- ============================================================
function ENT:GekkoTargetJump_ShouldJump()
    if self._jumpCooldown     > CurTime() then return false end
    if self._jumpLandCooldown > CurTime() then return false end
    -- Re-use the shared state accessor exposed by jump_system.lua
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return false end
    if not self:IsOnGround()                       then return false end
    if self._mgBurstActive                         then return false end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then return false end

    local dist = self:GetPos():Distance2D(enemy:GetPos())
    if dist < TJ_MIN_ENEMY_DIST then return false end

    return true
end

-- ============================================================
--  GekkoTargetJump_Think
--  Call this from ENT:OnThink() every frame.
--  It manages the 4-second solve interval and fires Execute
--  when a valid solution is cached and the jump guards pass.
-- ============================================================
function ENT:GekkoTargetJump_Think()
    local now = CurTime()

    -- Only re-solve every TJ_SOLVE_INTERVAL seconds
    if now >= self._tjNextSolveTime then
        self._tjNextSolveTime = now + TJ_SOLVE_INTERVAL
        self._tjPendingLaunch = nil  -- clear stale solution

        -- Guard: only solve when conditions are met
        if self:GekkoTargetJump_ShouldJump() then
            local enemy = self:GetEnemy()
            if IsValid(enemy) then
                local myPos     = self:GetPos()
                local enemyPos  = enemy:GetPos()
                local dZ        = enemyPos.z - myPos.z

                -- Ignore trivial drops / single stair steps
                if math.abs(dZ) < TJ_MIN_DZ_ABS then
                    print(string.format(
                        "[GekkoTJ] Skipping jump: dZ=%.1f below threshold (%d)",
                        dZ, TJ_MIN_DZ_ABS
                    ))
                else
                    local sol = SolveBallisticJump(myPos, enemyPos)
                    if sol then
                        self._tjPendingLaunch = {
                            sol      = sol,
                            enemyPos = enemyPos,   -- snapshot for direction calc
                        }
                    end
                end
            end
        end
    end

    -- If we have a pending solution and are still clear to jump, fire.
    if self._tjPendingLaunch and self:GekkoTargetJump_ShouldJump() then
        self:GekkoTargetJump_Execute(self._tjPendingLaunch)
        self._tjPendingLaunch = nil
    end
end

-- ============================================================
--  GekkoTargetJump_Execute
--  Mirrors GekkoJump_Execute() from jump_system.lua exactly,
--  replacing only the velocity lines with the solver result.
-- ============================================================
local function ForceSeqTJ(ent, seq, rate, suppressDur, seqLabel)
    ent:ResetSequence(seq)
    ent:SetCycle(0)
    ent:SetPlaybackRate(rate)
    ent.Gekko_LastSeqIdx   = seq
    ent.Gekko_LastSeqName  = seqLabel or "jump_phase"
    ent._gekkoSuppressActivity = CurTime() + suppressDur
    ent.VJ_IsMoving        = false
    ent.VJ_CanMoveThink    = false
end

function ENT:GekkoTargetJump_Execute(pending)
    -- Refuse if state has changed since the solve tick
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end

    local sol       = pending.sol
    local enemySnap = pending.enemyPos  -- direction vector from solve time

    -- Aim horizontal component toward the snapshotted enemy position
    local fwd = (enemySnap - self:GetPos())
    fwd.z = 0
    if fwd:Length() < 1 then fwd = self:GetForward() ; fwd.z = 0 end
    fwd:Normalize()

    local launchYaw = fwd:Angle().y
    self:SetAngles(Angle(0, launchYaw, 0))
    self:SetMoveType(MOVETYPE_FLYGRAVITY)

    local vel = self:GetVelocity()
    vel.z     = sol.vz
    vel       = vel + fwd * sol.vxy
    self:SetVelocity(vel)

    self:SetSchedule(SCHED_NONE)

    -- Transition into RISING – uses the shared state setters from jump_system.lua
    self:SetGekkoJumpState(self.JUMP_RISING)
    self._jumpStateLOCAL      = self.JUMP_RISING
    self._jumpLastState       = self.JUMP_RISING
    self._jumpCooldown        = CurTime() + math.Rand(8.0, 25.0)
    self._gekkoJustJumped     = CurTime() + 0.3
    self._jumpRisingStartTime = CurTime()
    self._jumpDidLiftoff      = false
    self._jumpLandCooldown    = 0

    if self._seqJump ~= -1 then
        ForceSeqTJ(self, self._seqJump, 1.0, 0.5, "jump")
    end

    -- Reuse all existing FX / crush hooks from jump_system.lua
    self:GeckoCrush_LaunchBlast()
    self:SetNWInt("GekkoJumpDust", (self:GetNWInt("GekkoJumpDust", 0) + 1) % 255)
    self:GekkoJump_StartJetFX()

    print(string.format(
        "[GekkoTJ] LAUNCH | vz=%.0f vxy=%.0f yaw=%.1f",
        sol.vz, sol.vxy, launchYaw
    ))
end
