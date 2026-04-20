-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Gekko VJ NPC — 2-step death fall pose (bone-driven)
--
--  Step 1 (~0.35s after death): L thigh swings out, pelvis dips
--  Step 2 (~1.1s after death):  R thigh swings out, pelvis fully
--                                drops to ground — gravity-paced
--
--  Designed to mirror the leg_disable_system pattern:
--  ManipulateBoneAngles / ManipulateBonePosition held every Think.
-- ============================================================

-- ----------------------------------------------------------------
--  Keyframe definitions (your exact values)
-- ----------------------------------------------------------------
local KF = {
    -- Step 1: L leg swings to side, body starts to tip
    [1] = {
        pelvisZ  = -12,
        lThigh   = Angle(-15, 67, -12),
        rThigh   = nil,               -- not yet moved
        duration = 0.38,              -- seconds to lerp into this kf
    },
    -- Step 2: both legs splayed (death-frog), pelvis hits deck
    [2] = {
        pelvisZ  = -114,
        lThigh   = Angle(-15, 67, -12),  -- held from step 1
        rThigh   = Angle(0, -77, -22),
        duration = 0.82,              -- slower — he is FALLING, not crouching
    },
}

-- ----------------------------------------------------------------
--  Init  (called from ENT:Init)
-- ----------------------------------------------------------------
function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
    self._deathPoseStep   = 0        -- 0 = not started, 1, 2
    self._deathPoseLerpT  = 0        -- lerp start time for current step
    self._deathPoseAlpha  = 0        -- 0→1 within current step

    -- Previous keyframe (lerp FROM)
    self._deathPosePrev = {
        pelvisZ = 0,
        lThigh  = Angle(0,0,0),
        rThigh  = Angle(0,0,0),
    }
    -- Current target keyframe (lerp TO)
    self._deathPoseCur = {
        pelvisZ = 0,
        lThigh  = Angle(0,0,0),
        rThigh  = Angle(0,0,0),
    }
end

-- ----------------------------------------------------------------
--  Trigger  (called from ENT:OnDeath at status=="Finish")
-- ----------------------------------------------------------------
function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true
    self._deathPoseStep   = 0

    -- Cache bone indices (may already exist from GekkoLegs_Init,
    -- but be safe in case death fires before that path ran)
    if not self.GekkoPelvisBone or self.GekkoPelvisBone < 0 then
        self.GekkoPelvisBone = self:LookupBone("b_pelvis") or -1
    end
    if not self.GekkoLThighBone or self.GekkoLThighBone < 0 then
        self.GekkoLThighBone = self:LookupBone("b_l_thigh") or -1
    end
    if not self.GekkoRThighBone or self.GekkoRThighBone < 0 then
        self.GekkoRThighBone = self:LookupBone("b_r_thigh") or -1
    end

    -- Kick off step 1 after a tiny settling delay
    timer.Simple(0.30, function()
        if not IsValid(self) then return end
        self:GekkoDeath_BeginStep(1)
    end)
end

-- ----------------------------------------------------------------
--  Begin a keyframe step
-- ----------------------------------------------------------------
function ENT:GekkoDeath_BeginStep(stepIdx)
    local kf = KF[stepIdx]
    if not kf then return end  -- no more steps, hold final pose

    -- Store what we were at as the FROM pose
    self._deathPosePrev = {
        pelvisZ = self._deathPoseCur.pelvisZ,
        lThigh  = Angle(
            self._deathPoseCur.lThigh.p,
            self._deathPoseCur.lThigh.y,
            self._deathPoseCur.lThigh.r
        ),
        rThigh  = Angle(
            self._deathPoseCur.rThigh.p,
            self._deathPoseCur.rThigh.y,
            self._deathPoseCur.rThigh.r
        ),
    }

    -- Set the TO pose from the keyframe
    self._deathPoseCur = {
        pelvisZ = kf.pelvisZ,
        lThigh  = kf.lThigh  and Angle(kf.lThigh.p,  kf.lThigh.y,  kf.lThigh.r)  or Angle(self._deathPosePrev.lThigh.p, self._deathPosePrev.lThigh.y, self._deathPosePrev.lThigh.r),
        rThigh  = kf.rThigh  and Angle(kf.rThigh.p,  kf.rThigh.y,  kf.rThigh.r)  or Angle(self._deathPosePrev.rThigh.p, self._deathPosePrev.rThigh.y, self._deathPosePrev.rThigh.r),
    }

    self._deathPoseStep  = stepIdx
    self._deathPoseLerpT = CurTime()
    self._deathPoseAlpha = 0

    -- Schedule next step at end of this one's duration
    if KF[stepIdx + 1] then
        timer.Simple(kf.duration, function()
            if not IsValid(self) then return end
            self:GekkoDeath_BeginStep(stepIdx + 1)
        end)
    end
end

-- ----------------------------------------------------------------
--  Helper: lerp between two Angle values component-wise
-- ----------------------------------------------------------------
local function LerpAngle(t, a, b)
    return Angle(
        Lerp(t, a.p, b.p),
        Lerp(t, a.y, b.y),
        Lerp(t, a.r, b.r)
    )
end

-- ----------------------------------------------------------------
--  Per-tick update  (called from ENT:OnThink)
-- ----------------------------------------------------------------
function ENT:GekkoDeath_Think()
    if not self._deathPoseActive then return end
    if self._deathPoseStep == 0  then return end  -- waiting for first timer

    local kf = KF[self._deathPoseStep]
    local now = CurTime()

    -- Advance alpha within this step
    if kf then
        local elapsed = now - self._deathPoseLerpT
        -- Use a smooth-step curve so the motion feels like gravity, not linear slide
        local t = math.Clamp(elapsed / kf.duration, 0, 1)
        -- Smoothstep: t = t*t*(3-2*t)
        self._deathPoseAlpha = t * t * (3 - 2 * t)
    else
        self._deathPoseAlpha = 1  -- final step complete, hold
    end

    local alpha   = self._deathPoseAlpha
    local prev    = self._deathPosePrev
    local cur     = self._deathPoseCur

    -- Pelvis Z drop
    local pelvisZ = Lerp(alpha, prev.pelvisZ, cur.pelvisZ)
    if self.GekkoPelvisBone and self.GekkoPelvisBone >= 0 then
        self:ManipulateBonePosition(self.GekkoPelvisBone, Vector(0, 0, pelvisZ))
    end

    -- L thigh
    if self.GekkoLThighBone and self.GekkoLThighBone >= 0 then
        self:ManipulateBoneAngles(self.GekkoLThighBone, LerpAngle(alpha, prev.lThigh, cur.lThigh))
    end

    -- R thigh
    if self.GekkoRThighBone and self.GekkoRThighBone >= 0 then
        self:ManipulateBoneAngles(self.GekkoRThighBone, LerpAngle(alpha, prev.rThigh, cur.rThigh))
    end
end
