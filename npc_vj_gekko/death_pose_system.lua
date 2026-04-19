-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Gekko VJ NPC — Death pose animation (CLIENT)
--
--  Two-step gravity-coherent fall sequence, triggered when the
--  NPC dies.  Mirrors the leg_disable_system approach.
--
--  Step 1  (tipping, one leg swings out)
--    L Thigh  Angle(-15, 67, -12)
--    Pelvis Z  -12
--
--  Step 2  (death-frog, fully grounded)
--    R Thigh  Angle(X, -77, -22)   (X preserved from rest)
--    Pelvis Z  -114
--
--  Timing is physics-coherent: the NPC is falling, not
--  crouching.  Step 1 lasts ~0.35 s, then gravity
--  accelerates the pelvis down over ~0.55 s to Step 2.
-- ============================================================

-- ────────────────────────────────────────────────────────────
--  CONSTANTS
-- ────────────────────────────────────────────────────────────
local DP_STEP1_DUR   = 0.35   -- seconds to reach step-1 keyframe
local DP_STEP2_DUR   = 0.55   -- seconds to fall from step-1 → step-2

-- Step 1 targets
local DP_S1_LTHIGH   = Angle(-15, 67, -12)
local DP_S1_PELVIS_Z = -12

-- Step 2 targets  (R thigh pitch: copy rest=0, just drive Y and R)
local DP_S2_RTHIGH   = Angle(0, -77, -22)
local DP_S2_PELVIS_Z = -114

-- Bone names
local DP_PELVIS_BONE = "b_pelvis"
local DP_LTHIGH_BONE = "b_l_thigh"
local DP_RTHIGH_BONE = "b_r_thigh"

-- ────────────────────────────────────────────────────────────
--  SMOOTHSTEP  (local copy, identical to cl_init.lua)
-- ────────────────────────────────────────────────────────────
local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function LerpAngle(a, b, t)
    return Angle(
        Lerp(t, a.p, b.p),
        Lerp(t, a.y, b.y),
        Lerp(t, a.r, b.r)
    )
end

-- ────────────────────────────────────────────────────────────
--  GekkoDeathPose_Init
--  Call once from ENT:Initialize (clientside), after bones
--  are available.
-- ────────────────────────────────────────────────────────────
function ENT:GekkoDeathPose_Init()
    self._dp_active    = false
    self._dp_startTime = 0
    self._dp_pelBone   = self:LookupBone(DP_PELVIS_BONE) or -1
    self._dp_lBone     = self:LookupBone(DP_LTHIGH_BONE) or -1
    self._dp_rBone     = self:LookupBone(DP_RTHIGH_BONE) or -1
end

-- ────────────────────────────────────────────────────────────
--  GekkoDeathPose_Trigger
--  Call from ENT:OnDeath or the death net-message handler.
-- ────────────────────────────────────────────────────────────
function ENT:GekkoDeathPose_Trigger()
    if self._dp_active then return end
    self._dp_active    = true
    self._dp_startTime = CurTime()
end

-- ────────────────────────────────────────────────────────────
--  GekkoDeathPose_Think
--  Call every frame from ENT:Think (clientside).
--  Returns true while the animation is still running.
-- ────────────────────────────────────────────────────────────
function ENT:GekkoDeathPose_Think()
    if not self._dp_active then return false end

    local pelBone = self._dp_pelBone
    local lBone   = self._dp_lBone
    local rBone   = self._dp_rBone

    -- Re-resolve bones in case they were not ready at Init time
    if (not pelBone or pelBone < 0) then
        self._dp_pelBone = self:LookupBone(DP_PELVIS_BONE) or -1
        pelBone = self._dp_pelBone
    end
    if (not lBone or lBone < 0) then
        self._dp_lBone = self:LookupBone(DP_LTHIGH_BONE) or -1
        lBone = self._dp_lBone
    end
    if (not rBone or rBone < 0) then
        self._dp_rBone = self:LookupBone(DP_RTHIGH_BONE) or -1
        rBone = self._dp_rBone
    end

    local elapsed = CurTime() - self._dp_startTime
    local totalDur = DP_STEP1_DUR + DP_STEP2_DUR

    -- ── STEP 1: tip begins, one leg swings out ──────────────
    if elapsed < DP_STEP1_DUR then
        local t = Smoothstep(elapsed / DP_STEP1_DUR)

        -- L thigh swings to side
        if lBone and lBone >= 0 then
            self:ManipulateBoneAngles(lBone,
                LerpAngle(Angle(0, 0, 0), DP_S1_LTHIGH, t), false)
        end

        -- Pelvis begins dropping slightly
        if pelBone and pelBone >= 0 then
            self:ManipulateBonePosition(pelBone,
                Vector(0, 0, Lerp(t, 0, DP_S1_PELVIS_Z)), false)
        end

        return true
    end

    -- ── STEP 2: gravity takes over, death-frog final pose ───
    if elapsed < totalDur then
        -- Use squared ease-in to simulate gravity acceleration
        local raw = (elapsed - DP_STEP1_DUR) / DP_STEP2_DUR
        local tFall = raw * raw   -- ease-in (gravity feel)
        local tSmooth = Smoothstep(raw)

        -- L thigh holds step-1 angle throughout
        if lBone and lBone >= 0 then
            self:ManipulateBoneAngles(lBone, DP_S1_LTHIGH, false)
        end

        -- R thigh swings out (death-frog) with smoothstep
        if rBone and rBone >= 0 then
            self:ManipulateBoneAngles(rBone,
                LerpAngle(Angle(0, 0, 0), DP_S2_RTHIGH, tSmooth), false)
        end

        -- Pelvis slams down with gravitational ease-in
        if pelBone and pelBone >= 0 then
            self:ManipulateBonePosition(pelBone,
                Vector(0, 0, Lerp(tFall, DP_S1_PELVIS_Z, DP_S2_PELVIS_Z)), false)
        end

        return true
    end

    -- ── HOLD final pose forever after animation completes ───
    if lBone and lBone >= 0 then
        self:ManipulateBoneAngles(lBone, DP_S1_LTHIGH, false)
    end
    if rBone and rBone >= 0 then
        self:ManipulateBoneAngles(rBone, DP_S2_RTHIGH, false)
    end
    if pelBone and pelBone >= 0 then
        self:ManipulateBonePosition(pelBone, Vector(0, 0, DP_S2_PELVIS_Z), false)
    end

    return true   -- keep returning true so caller never resets bones
end
