-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Applies a 2-step collapse pose to the ragdoll CORPSE entity.
--
--  Root cause fix: VJ Base removes the living NPC immediately
--  after OnDeath("Finish") and replaces it with a prop_ragdoll
--  stored in self.Corpse. ENT:OnThink stops running at that point,
--  so all bone manipulation must target self.Corpse instead,
--  driven by a repeating timer.
-- ============================================================

local TIMER_INTERVAL = 0.016   -- ~60 Hz bone updates on the corpse
local FIND_RETRIES   = 20
local FIND_INTERVAL  = 0.05

-- Keyframes: pelvis Z offset + thigh angles
local KF = {
    [1] = {
        pelvisZ  = -12,
        lThigh   = Angle(-15, 67, -12),
        rThigh   = nil,
        duration = 0.38,
    },
    [2] = {
        pelvisZ  = -114,
        lThigh   = Angle(-15, 67, -12),
        rThigh   = Angle(0, -77, -22),
        duration = 0.82,
    },
}

-- ----------------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------------
local function LerpAngle(t, a, b)
    return Angle(
        Lerp(t, a.p, b.p),
        Lerp(t, a.y, b.y),
        Lerp(t, a.r, b.r)
    )
end

local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- ----------------------------------------------------------------
--  Init  (called from ENT:Init on the living NPC)
-- ----------------------------------------------------------------
function ENT:GekkoDeath_Init()
    self._deathPoseActive = false
end

-- ----------------------------------------------------------------
--  Internal: start a keyframe step on the corpse
-- ----------------------------------------------------------------
local function BeginStep(state, stepIdx)
    local kf = KF[stepIdx]
    if not kf then return end

    state.prev = {
        pelvisZ = state.cur.pelvisZ,
        lThigh  = Angle(state.cur.lThigh.p, state.cur.lThigh.y, state.cur.lThigh.r),
        rThigh  = Angle(state.cur.rThigh.p, state.cur.rThigh.y, state.cur.rThigh.r),
    }
    state.cur = {
        pelvisZ = kf.pelvisZ,
        lThigh  = kf.lThigh and Angle(kf.lThigh.p, kf.lThigh.y, kf.lThigh.r)
                            or  Angle(state.prev.lThigh.p, state.prev.lThigh.y, state.prev.lThigh.r),
        rThigh  = kf.rThigh and Angle(kf.rThigh.p, kf.rThigh.y, kf.rThigh.r)
                            or  Angle(state.prev.rThigh.p, state.prev.rThigh.y, state.prev.rThigh.r),
    }
    state.stepIdx  = stepIdx
    state.stepT    = CurTime()
    state.duration = kf.duration

    if KF[stepIdx + 1] then
        timer.Simple(kf.duration, function()
            if not IsValid(state.corpse) then return end
            BeginStep(state, stepIdx + 1)
        end)
    end
end

-- ----------------------------------------------------------------
--  Internal: per-tick apply loop running on the corpse
-- ----------------------------------------------------------------
local function StartCorpseLoop(corpse)
    local timerName = "GekkoDeath_" .. corpse:EntIndex()

    -- Cache bone indices on the corpse
    local pelvisBone = corpse:LookupBone("b_pelvis")
    local lThighBone = corpse:LookupBone("b_l_thigh")
    local rThighBone = corpse:LookupBone("b_r_thigh")

    pelvisBone = (pelvisBone and pelvisBone >= 0) and pelvisBone or nil
    lThighBone = (lThighBone and lThighBone >= 0) and lThighBone or nil
    rThighBone = (rThighBone and rThighBone >= 0) and rThighBone or nil

    -- Shared state table for this corpse
    local state = {
        corpse   = corpse,
        stepIdx  = 0,
        stepT    = CurTime(),
        duration = 0,
        prev = { pelvisZ = 0, lThigh = Angle(0,0,0), rThigh = Angle(0,0,0) },
        cur  = { pelvisZ = 0, lThigh = Angle(0,0,0), rThigh = Angle(0,0,0) },
    }

    -- Start step 1 after a short settling delay
    timer.Simple(0.30, function()
        if not IsValid(corpse) then return end
        BeginStep(state, 1)
    end)

    -- Repeating apply loop
    timer.Create(timerName, TIMER_INTERVAL, 0, function()
        if not IsValid(corpse) then
            timer.Remove(timerName)
            return
        end

        if state.stepIdx == 0 then return end  -- waiting for first step

        local alpha = Smoothstep(math.Clamp(
            (CurTime() - state.stepT) / math.max(state.duration, 0.001),
            0, 1
        ))

        if pelvisBone then
            corpse:ManipulateBonePosition(
                pelvisBone,
                Vector(0, 0, Lerp(alpha, state.prev.pelvisZ, state.cur.pelvisZ))
            )
        end
        if lThighBone then
            corpse:ManipulateBoneAngles(
                lThighBone,
                LerpAngle(alpha, state.prev.lThigh, state.cur.lThigh)
            )
        end
        if rThighBone then
            corpse:ManipulateBoneAngles(
                rThighBone,
                LerpAngle(alpha, state.prev.rThigh, state.cur.rThigh)
            )
        end
    end)

    print("[GekkoDeath] Corpse loop started: " .. tostring(corpse))
end

-- ----------------------------------------------------------------
--  Trigger  (called from ENT:OnDeath at status=="Finish")
--  Retries finding self.Corpse since VJ Base creates it async.
-- ----------------------------------------------------------------
function ENT:GekkoDeath_Trigger()
    if self._deathPoseActive then return end
    self._deathPoseActive = true

    local selfRef  = self
    local attempts = 0

    local function TryFind()
        attempts = attempts + 1
        local corpse = selfRef.Corpse
        if IsValid(corpse) then
            StartCorpseLoop(corpse)
            return
        end
        if attempts < FIND_RETRIES then
            timer.Simple(FIND_INTERVAL, TryFind)
        else
            print("[GekkoDeath] WARNING: gave up finding Corpse after "
                .. attempts .. " attempts")
        end
    end

    timer.Simple(0, TryFind)
end

-- ----------------------------------------------------------------
--  GekkoDeath_Think is kept as a no-op so OnThink calls don't error
-- ----------------------------------------------------------------
function ENT:GekkoDeath_Think()
end
