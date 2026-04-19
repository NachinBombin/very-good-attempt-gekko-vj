-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Gekko VJ NPC — Death fall pose (two-step animated sequence)
--
--  Step 1 — one leg kicks out, fall begins
--    L Thigh  : Angle(-15, 67, -12)
--    Pelvis Z : -12  (just starting to drop)
--
--  Step 2 — death frog, body hits ground
--    R Thigh  : Angle(0, -77, -22)   (X = 0; tweak freely)
--    Pelvis Z : -114 (fully grounded)
--
--  Transition is gravity-coherent: pelvis lerps via quadratic
--  ease-in over ~0.62 s (sqrt(2*114/600)), mimicking free-fall.
-- ============================================================

-- ---- Pose targets ----
local STEP1_L_THIGH_ANG  = Angle(-15,  67, -12)
local STEP1_PELVIS_Z     = -12

local STEP2_R_THIGH_ANG  = Angle(0,   -77, -22)   -- X free to adjust
local STEP2_PELVIS_Z     = -114

-- ---- Timing ----
-- How long step 1 lasts before step 2 begins (leg-kick / tilt phase)
local STEP1_DURATION     = 0.35   -- seconds

-- Total travel time for pelvis 0 → -114
-- Distance = 114 u, gravity ≈ 600 u/s²  →  t = sqrt(2*114/600) ≈ 0.62 s
local FALL_DURATION      = 0.62   -- seconds

-- ============================================================
--  Init
-- ============================================================
function ENT:GekkoDeath_Init()
    self._gDeathActive = false
    self._gDeathStep   = 0        -- 0=idle, 1=step1, 2=step2
    self._gDeathStartT = 0
    self._gDeathStep2T = 0
    -- Cache bone indices (looked up once; same bones as leg_disable_system)
    self._gPelvisBone  = self:LookupBone("b_pelvis")   or -1
    self._gLThighBone  = self:LookupBone("b_l_thigh")  or -1
    self._gRThighBone  = self:LookupBone("b_r_thigh")  or -1
end

-- ============================================================
--  Trigger — called from OnDeath "Finish"
-- ============================================================
function ENT:GekkoDeath_Trigger(dmginfo)
    if self._gDeathActive then return end

    self._gDeathActive = true
    self._gDeathStep   = 1
    self._gDeathStartT = CurTime()
    self._gDeathStep2T = CurTime() + STEP1_DURATION

    -- Immediately snap L thigh for the "leg kicks out" moment
    if self._gLThighBone >= 0 then
        self:ManipulateBoneAngles(self._gLThighBone, STEP1_L_THIGH_ANG)
    end
    -- Pelvis starts its descent — place it at step-1 Z immediately
    if self._gPelvisBone >= 0 then
        self:ManipulateBonePosition(self._gPelvisBone, Vector(0, 0, STEP1_PELVIS_Z))
    end
end

-- ============================================================
--  Per-tick update — hooked into ENT:OnThink
-- ============================================================
function ENT:GekkoDeath_Think()
    if not self._gDeathActive then return end

    local now = CurTime()

    -- --------------------------------------------------------
    --  Advance to step 2: snap R thigh into death-frog angle
    -- --------------------------------------------------------
    if self._gDeathStep == 1 and now >= self._gDeathStep2T then
        self._gDeathStep = 2
        if self._gRThighBone >= 0 then
            self:ManipulateBoneAngles(self._gRThighBone, STEP2_R_THIGH_ANG)
        end
    end

    -- --------------------------------------------------------
    --  Pelvis gravity animation: quadratic ease-in (t²)
    --  Starts from STEP1_PELVIS_Z, falls to STEP2_PELVIS_Z.
    -- --------------------------------------------------------
    if self._gDeathStep >= 1 then
        local elapsed  = math.min(now - self._gDeathStartT, FALL_DURATION)
        local frac     = elapsed / FALL_DURATION      -- 0 → 1
        local easeFrac = frac * frac                  -- slow-start, accelerate

        local pelvisZ  = Lerp(easeFrac, STEP1_PELVIS_Z, STEP2_PELVIS_Z)

        if self._gPelvisBone >= 0 then
            self:ManipulateBonePosition(self._gPelvisBone, Vector(0, 0, pelvisZ))
        end

        if elapsed >= FALL_DURATION then
            self:GekkoDeath_Freeze()
        end
    end
end

-- ============================================================
--  Freeze — lock the final pose and stop ticking
-- ============================================================
function ENT:GekkoDeath_Freeze()
    -- Snap to exact final values
    if self._gPelvisBone >= 0 then
        self:ManipulateBonePosition(self._gPelvisBone, Vector(0, 0, STEP2_PELVIS_Z))
    end
    if self._gRThighBone >= 0 then
        self:ManipulateBoneAngles(self._gRThighBone, STEP2_R_THIGH_ANG)
    end
    if self._gLThighBone >= 0 then
        self:ManipulateBoneAngles(self._gLThighBone, STEP1_L_THIGH_ANG)
    end

    self._gDeathActive = false   -- stop further updates
end
