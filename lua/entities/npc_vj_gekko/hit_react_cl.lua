-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/hit_react_cl.lua
-- PURPOSE: Consumes NW2 GekkoHitBoneName / GekkoHitDir /
--          GekkoHitReactPulse and drives ManipulateBoneAngles
--          on the named bone so the limb visually reacts to
--          incoming damage direction.
-- SCOPE: Client only  (include'd from cl_init.lua)
-- ============================================================
if not CLIENT then return end

-- ============================================================
--  TUNING
-- ============================================================
local REACT_DURATION  = 0.35   -- seconds the deflection holds at peak
local REACT_RAMP_IN   = 0.08   -- seconds to ramp from 0 -> peak
local REACT_RAMP_OUT  = 0.22   -- seconds to return from peak -> 0
local REACT_DEG_LARGE = 28     -- peak deflection (degrees) for large hits
local REACT_DEG_SMALL = 14     -- peak deflection (degrees) for small hits

-- ============================================================
--  SMOOTHSTEP  (local, does not conflict with cl_init.lua's)
-- ============================================================
local function HR_Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- ============================================================
--  PER-ENTITY THINK DRIVER
--  Called every frame from ENT:Think (hooked below).
-- ============================================================
function ENT:HitReact_Init()
    self._hr_pulseLast  = self:GetNWInt("GekkoHitReactPulse", 0)
    self._hr_startTime  = -9999
    self._hr_duration   = REACT_DURATION
    self._hr_boneIdx    = -1
    self._hr_peakAng    = Angle(0, 0, 0)
    self._hr_wasActive  = false
end

function ENT:HitReact_Think()
    -- Lazy init
    if self._hr_pulseLast == nil then self:HitReact_Init() end

    local pulse = self:GetNWInt("GekkoHitReactPulse", 0)
    if pulse ~= self._hr_pulseLast then
        self._hr_pulseLast = pulse

        -- Resolve bone index from NW2 name
        local boneName = self:GetNW2String("GekkoHitBoneName", "b_spine3")
        local boneIdx  = self:LookupBone(boneName)
        if not boneIdx or boneIdx < 0 then
            boneIdx = self:LookupBone("b_spine3") or -1
        end
        self._hr_boneIdx = boneIdx

        -- Build a local-space deflection angle from the world hit direction.
        -- We project the hit dir onto the entity's local axes and build a
        -- pitch/yaw tilt that pushes the bone away from the attacker.
        local hitDir = self:GetNW2Vector("GekkoHitDir", Vector(0, 1, 0))
        local islarge = self:GetNW2Bool("GekkoHitLarge", false)
        local peakDeg = islarge and REACT_DEG_LARGE or REACT_DEG_SMALL

        -- Transform world hit dir into entity-local space
        local entAng  = self:GetAngles()
        local localDir = WorldToLocal(
            self:GetPos() + hitDir,
            Angle(0, 0, 0),
            self:GetPos(),
            entAng
        ) -- returns a Vector relative to entity origin

        -- localDir.x = forward component, .y = right component, .z = up component
        -- Deflect the bone in the direction the force came from:
        --   pitch  = tilt forward/back  (driven by local X)
        --   yaw    = twist left/right   (driven by local Y)
        --   roll   = lean               (driven by local Z)
        local pitch = math.Clamp( localDir.x, -1, 1) * peakDeg
        local yaw   = math.Clamp(-localDir.y, -1, 1) * peakDeg
        local roll  = math.Clamp( localDir.z, -1, 1) * (peakDeg * 0.5)

        self._hr_peakAng   = Angle(pitch, yaw, roll)
        self._hr_startTime = CurTime()
        self._hr_duration  = REACT_RAMP_IN + REACT_DURATION + REACT_RAMP_OUT
        self._hr_wasActive = true
    end

    local boneIdx = self._hr_boneIdx
    if not boneIdx or boneIdx < 0 then return end

    local elapsed = CurTime() - (self._hr_startTime or -9999)
    local total   = self._hr_duration or (REACT_RAMP_IN + REACT_DURATION + REACT_RAMP_OUT)

    if elapsed < 0 or elapsed >= total then
        if self._hr_wasActive then
            self._hr_wasActive = false
            self:ManipulateBoneAngles(boneIdx, Angle(0, 0, 0), false)
        end
        return
    end

    -- Envelope: ramp in -> hold -> ramp out
    local env
    if elapsed < REACT_RAMP_IN then
        env = HR_Smoothstep(elapsed / REACT_RAMP_IN)
    elseif elapsed < REACT_RAMP_IN + REACT_DURATION then
        env = 1.0
    else
        local t = (elapsed - REACT_RAMP_IN - REACT_DURATION) / REACT_RAMP_OUT
        env = 1.0 - HR_Smoothstep(t)
    end

    local peak = self._hr_peakAng
    self:ManipulateBoneAngles(boneIdx,
        Angle(peak.p * env, peak.y * env, peak.r * env),
        false)
end
