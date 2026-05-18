-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/hit_react_cl.lua
-- PURPOSE: Visual bone-reaction to incoming damage.
--
-- BONE SELECTION: Derived entirely client-side from the hit
-- position Z height relative to the NPC, so no extra NW2
-- writes are needed on the server.
--
-- Zone thresholds (fraction of collision height):
--   Z > 0.75  -> b_spine3  (torso / head region)
--   Z > 0.45  -> b_pelvis  (mid / hip region)
--   Z > 0.20  -> b_l_hippiston1 or b_r_hippiston1  (upper leg)
--   Z <= 0.20 -> no reaction (foot hits, ground clips)
--
-- SCOPE: Client only  (include'd from cl_init.lua)
-- ============================================================
if not CLIENT then return end

-- ============================================================
--  TUNING
-- ============================================================
local RAMP_IN    = 0.07   -- seconds 0 -> peak
local HOLD       = 0.10   -- seconds at peak
local RAMP_OUT   = 0.20   -- seconds peak -> 0
local TOTAL_DUR  = RAMP_IN + HOLD + RAMP_OUT   -- 0.37 s

local DEG_LARGE  = 24
local DEG_SMALL  = 12

-- Z-fraction thresholds (fraction of collision bounds max Z)
local ZONE_TORSO = 0.75
local ZONE_HIP   = 0.45
local ZONE_THIGH = 0.20

-- ============================================================
--  SMOOTHSTEP
-- ============================================================
local function HR_Smooth(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- ============================================================
--  BONE SELECTION  (pure client, no NW2 bone name needed)
-- ============================================================
local function HR_SelectBone(ent, hitPos)
    local _, maxs = ent:GetCollisionBounds()
    local entZ    = ent:GetPos().z
    local height  = maxs.z   -- e.g. 200
    local frac    = (hitPos.z - entZ) / height   -- 0 = feet, 1 = top

    if frac > ZONE_TORSO then
        -- Torso/neck zone — use spine3 but at reduced amplitude so the
        -- head driver doesn't compete visibly.
        local idx = ent:LookupBone("b_spine3")
        return (idx and idx >= 0) and idx or -1, 0.6   -- amplitude scale
    elseif frac > ZONE_HIP then
        -- Pelvis/hip zone
        local idx = ent:LookupBone("b_pelvis")
        return (idx and idx >= 0) and idx or -1, 1.0
    elseif frac > ZONE_THIGH then
        -- Thigh/piston zone — pick left or right based on world hit side
        local toHit = hitPos - ent:GetPos()
        local right = ent:GetRight()
        local side  = toHit:Dot(right)   -- positive = hit from the right side
        local boneName = (side >= 0) and "b_r_hippiston1" or "b_l_hippiston1"
        local idx = ent:LookupBone(boneName)
        return (idx and idx >= 0) and idx or -1, 1.0
    else
        -- Foot zone — no visible reaction
        return -1, 0
    end
end

-- ============================================================
--  PER-ENTITY STATE  (lazy-init on first HitReact_Think call)
-- ============================================================
function ENT:HitReact_Init()
    self._hr_pulseLast  = self:GetNWInt("GekkoHitReactPulse", 0)
    self._hr_startTime  = -9999
    self._hr_boneIdx    = -1
    self._hr_peakAng    = Angle(0, 0, 0)
    self._hr_ampScale   = 1.0
    self._hr_wasActive  = false
end

-- ============================================================
--  MAIN THINK DRIVER  (called every frame from ENT:Think)
-- ============================================================
function ENT:HitReact_Think()
    if self._hr_pulseLast == nil then self:HitReact_Init() end

    local pulse = self:GetNWInt("GekkoHitReactPulse", 0)
    if pulse ~= self._hr_pulseLast then
        self._hr_pulseLast = pulse

        -- Hit metadata written by init.lua OnTakeDamage
        local hitPos  = self:GetNW2Vector("GekkoHitPos",  self:GetPos())
        local hitDir  = self:GetNW2Vector("GekkoHitDir",  Vector(0, 1, 0))
        local isLarge = self:GetNW2Bool("GekkoHitLarge",  false)

        local boneIdx, ampScale = HR_SelectBone(self, hitPos)
        self._hr_boneIdx  = boneIdx
        self._hr_ampScale = ampScale

        if boneIdx < 0 then return end   -- foot zone, skip

        local peakDeg = (isLarge and DEG_LARGE or DEG_SMALL) * ampScale

        -- Build local-space deflection angle.
        -- Project hit direction onto entity axes for a physically-plausible tilt.
        local entAng    = self:GetAngles()
        local localFwd  = ent and ent:GetForward() or Vector(1,0,0)   -- fallback
        -- WorldToLocal only needs vectors; angles not used here.
        local fwd   = self:GetForward()
        local right = self:GetRight()
        local up    = self:GetUp()

        local fx = hitDir:Dot(fwd)    -- forward component
        local fy = hitDir:Dot(right)  -- right component
        local fz = hitDir:Dot(up)     -- up component

        -- Map to bone-local pitch/yaw/roll deflection:
        --   push bone away from incoming force direction
        local pitch = math.Clamp( fx, -1, 1) * peakDeg
        local yaw   = math.Clamp(-fy, -1, 1) * peakDeg
        local roll  = math.Clamp( fz, -1, 1) * (peakDeg * 0.4)

        self._hr_peakAng   = Angle(pitch, yaw, roll)
        self._hr_startTime = CurTime()
        self._hr_wasActive = true
    end

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
