-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Gekko VJ NPC — Death pose animation
--
--  SERVER: stub functions only (bone manipulation is clientside).
--  CLIENT: full two-step gravity-coherent fall sequence.
--
--  Step 1  (tipping, one leg swings out)
--    L Thigh  Angle(-15, 67, -12)
--    Pelvis Z  -12
--
--  Step 2  (death-frog, fully grounded)
--    R Thigh  Angle(0, -77, -22)   (X=0 preserved from rest)
--    Pelvis Z  -114
--
--  Timing is physics-coherent: the NPC is falling, not
--  crouching.  Step 1 lasts ~0.35 s, then gravitational
--  ease-in carries the pelvis down over ~0.55 s to Step 2.
-- ============================================================

-- ────────────────────────────────────────────────────────────
--  CONSTANTS
-- ────────────────────────────────────────────────────────────
local DP_STEP1_DUR   = 0.35   -- seconds to reach step-1 keyframe
local DP_STEP2_DUR   = 0.55   -- seconds to fall from step-1 → step-2

-- Step 1 targets
local DP_S1_LTHIGH   = Angle(-15, 67, -12)
local DP_S1_PELVIS_Z = -12

-- Step 2 targets
local DP_S2_RTHIGH   = Angle(0, -77, -22)
local DP_S2_PELVIS_Z = -114

-- Bone names
local DP_PELVIS_BONE = "b_pelvis"
local DP_LTHIGH_BONE = "b_l_thigh"
local DP_RTHIGH_BONE = "b_r_thigh"

-- ────────────────────────────────────────────────────────────
--  HELPERS
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
--  SERVER stubs  (init.lua calls these unconditionally)
-- ────────────────────────────────────────────────────────────
if SERVER then
    function ENT:GekkoDeath_Init()    end
    function ENT:GekkoDeath_Trigger() end
    function ENT:GekkoDeath_Think()   end
    return
end

-- ────────────────────────────────────────────────────────────
--  CLIENT implementation
-- ────────────────────────────────────────────────────────────

-- GekkoDeath_Init
-- Call once from ENT:Initialize (clientside), after bones are available.
function ENT:GekkoDeath_Init()
    self._dp_active    = false
    self._dp_startTime = 0
    self._dp_pelBone   = self:LookupBone(DP_PELVIS_BONE) or -1
    self._dp_lBone     = self:LookupBone(DP_LTHIGH_BONE) or -1
    self._dp_rBone     = self:LookupBone(DP_RTHIGH_BONE) or -1
end

-- GekkoDeath_Trigger
-- Called via net message when the NPC dies (clientside receiver).
function ENT:GekkoDeath_Trigger()
    if self._dp_active then return end
    self._dp_active    = true
    self._dp_startTime = CurTime()
end

-- GekkoDeath_Think
-- Call every frame from ENT:Think (clientside).
function ENT:GekkoDeath_Think()
    if not self._dp_active then return end

    local pelBone = self._dp_pelBone
    local lBone   = self._dp_lBone
    local rBone   = self._dp_rBone

    -- Re-resolve bones if they weren't ready at Init time
    if not pelBone or pelBone < 0 then
        self._dp_pelBone = self:LookupBone(DP_PELVIS_BONE) or -1
        pelBone = self._dp_pelBone
    end
    if not lBone or lBone < 0 then
        self._dp_lBone = self:LookupBone(DP_LTHIGH_BONE) or -1
        lBone = self._dp_lBone
    end
    if not rBone or rBone < 0 then
        self._dp_rBone = self:LookupBone(DP_RTHIGH_BONE) or -1
        rBone = self._dp_rBone
    end

    local elapsed  = CurTime() - self._dp_startTime
    local totalDur = DP_STEP1_DUR + DP_STEP2_DUR

    -- ── STEP 1: tip begins, L leg swings to the side ────────
    if elapsed < DP_STEP1_DUR then
        local t = Smoothstep(elapsed / DP_STEP1_DUR)

        if lBone and lBone >= 0 then
            self:ManipulateBoneAngles(lBone,
                LerpAngle(Angle(0, 0, 0), DP_S1_LTHIGH, t), false)
        end

        if pelBone and pelBone >= 0 then
            self:ManipulateBonePosition(pelBone,
                Vector(0, 0, Lerp(t, 0, DP_S1_PELVIS_Z)), false)
        end
        return
    end

    -- ── STEP 2: gravity takes over, death-frog final pose ───
    if elapsed < totalDur then
        local raw     = (elapsed - DP_STEP1_DUR) / DP_STEP2_DUR
        local tFall   = raw * raw            -- ease-in: gravity feel
        local tSmooth = Smoothstep(raw)

        -- L thigh holds step-1 angle
        if lBone and lBone >= 0 then
            self:ManipulateBoneAngles(lBone, DP_S1_LTHIGH, false)
        end

        -- R thigh opens out (death-frog)
        if rBone and rBone >= 0 then
            self:ManipulateBoneAngles(rBone,
                LerpAngle(Angle(0, 0, 0), DP_S2_RTHIGH, tSmooth), false)
        end

        -- Pelvis slams down with gravitational ease-in
        if pelBone and pelBone >= 0 then
            self:ManipulateBonePosition(pelBone,
                Vector(0, 0, Lerp(tFall, DP_S1_PELVIS_Z, DP_S2_PELVIS_Z)), false)
        end
        return
    end

    -- ── HOLD final pose forever ──────────────────────────────
    if lBone and lBone >= 0 then
        self:ManipulateBoneAngles(lBone, DP_S1_LTHIGH, false)
    end
    if rBone and rBone >= 0 then
        self:ManipulateBoneAngles(rBone, DP_S2_RTHIGH, false)
    end
    if pelBone and pelBone >= 0 then
        self:ManipulateBonePosition(pelBone, Vector(0, 0, DP_S2_PELVIS_Z), false)
    end
end
