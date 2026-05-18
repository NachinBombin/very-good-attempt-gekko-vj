-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/hit_react_cl.lua
-- PURPOSE: Visual bone-reaction to incoming damage.
--
-- BONE SELECTION: Derived entirely client-side from the hit
-- position Z height relative to the NPC, so no extra NW2
-- writes are needed beyond the three vars set in init.lua:
--   GekkoHitReactPulse  (NWInt  - increments each hit)
--   GekkoHitPos         (NW2Vector - world hit position)
--   GekkoHitDir         (NW2Vector - normalised hit direction)
--
-- Zone thresholds (fraction of collision height from base):
--   frac > 0.75  -> b_spine3        (torso/neck, 0.6x amp)
--   frac > 0.45  -> b_pelvis        (hip, full amp)
--   frac > 0.20  -> b_l/r_hippiston1 (thigh, side-picked)
--   frac <= 0.20 -> no reaction     (foot clips etc.)
--
-- SCOPE: CLIENT only (included from cl_init.lua)
-- ============================================================
if not CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local RAMP_IN   = 0.07
local HOLD      = 0.10
local RAMP_OUT  = 0.20
local TOTAL_DUR = RAMP_IN + HOLD + RAMP_OUT   -- 0.37 s

local DEG_LARGE = 24
local DEG_SMALL = 12

local ZONE_TORSO = 0.75
local ZONE_HIP   = 0.45
local ZONE_THIGH = 0.20

-- ============================================================
-- SMOOTHSTEP
-- ============================================================
local function HR_Smooth(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- ============================================================
-- BONE SELECTION
-- ============================================================
local function HR_SelectBone(self, hitPos)
    local _, maxs = self:GetCollisionBounds()
    local height  = maxs.z                           -- e.g. 200 hu
    local frac    = (hitPos.z - self:GetPos().z) / height

    if frac > ZONE_TORSO then
        local idx = self:LookupBone("b_spine3")
        return (idx and idx >= 0) and idx or -1, 0.6

    elseif frac > ZONE_HIP then
        local idx = self:LookupBone("b_pelvis")
        return (idx and idx >= 0) and idx or -1, 1.0

    elseif frac > ZONE_THIGH then
        -- Pick left or right piston based on which side the hit came from.
        local side = (hitPos - self:GetPos()):Dot(self:GetRight())
        local name = (side >= 0) and "b_r_hippiston1" or "b_l_hippiston1"
        local idx  = self:LookupBone(name)
        return (idx and idx >= 0) and idx or -1, 1.0

    else
        return -1, 0   -- foot zone, no reaction
    end
end

-- ============================================================
-- PER-ENTITY STATE (lazy-init)
-- ============================================================
function ENT:HitReact_Init()
    self._hr_pulseLast = self:GetNWInt("GekkoHitReactPulse", 0)
    self._hr_startTime = -9999
    self._hr_boneIdx   = -1
    self._hr_peakAng   = Angle(0, 0, 0)
    self._hr_wasActive = false
end

-- ============================================================
-- MAIN THINK  (called every frame from ENT:Think / cl_init)
-- ============================================================
function ENT:HitReact_Think()
    -- Lazy init on first call
    if self._hr_pulseLast == nil then self:HitReact_Init() end

    local pulse = self:GetNWInt("GekkoHitReactPulse", 0)

    -- New hit received
    if pulse ~= self._hr_pulseLast then
        self._hr_pulseLast = pulse

        local hitPos  = self:GetNW2Vector("GekkoHitPos", self:GetPos())
        local hitDir  = self:GetNW2Vector("GekkoHitDir", Vector(0, 1, 0))
        local isLarge = self:GetNW2Bool("GekkoHitLarge", false)

        local boneIdx, ampScale = HR_SelectBone(self, hitPos)
        self._hr_boneIdx = boneIdx

        if boneIdx < 0 then return end   -- foot zone

        local peakDeg = (isLarge and DEG_LARGE or DEG_SMALL) * ampScale

        -- Project hit direction onto entity axes.
        local fwd   = self:GetForward()
        local right = self:GetRight()
        local up    = self:GetUp()

        local pitch = math.Clamp( hitDir:Dot(fwd),   -1, 1) * peakDeg
        local yaw   = math.Clamp(-hitDir:Dot(right),  -1, 1) * peakDeg
        local roll  = math.Clamp( hitDir:Dot(up),    -1, 1) * (peakDeg * 0.4)

        self._hr_peakAng   = Angle(pitch, yaw, roll)
        self._hr_startTime = CurTime()
        self._hr_wasActive = true
    end

    -- Nothing active
    local boneIdx = self._hr_boneIdx
    if not boneIdx or boneIdx < 0 then return end

    local elapsed = CurTime() - (self._hr_startTime or -9999)

    if elapsed < 0 or elapsed >= TOTAL_DUR then
        if self._hr_wasActive then
            self._hr_wasActive = false
            self:ManipulateBoneAngles(boneIdx, Angle(0, 0, 0), false)
        end
        return
    end

    -- Envelope: ramp in -> hold -> ramp out
    local env
    if elapsed < RAMP_IN then
        env = HR_Smooth(elapsed / RAMP_IN)
    elseif elapsed < RAMP_IN + HOLD then
        env = 1.0
    else
        env = 1.0 - HR_Smooth((elapsed - RAMP_IN - HOLD) / RAMP_OUT)
    end

    local peak = self._hr_peakAng
    self:ManipulateBoneAngles(boneIdx,
        Angle(peak.p * env, peak.y * env, peak.r * env), false)
end
