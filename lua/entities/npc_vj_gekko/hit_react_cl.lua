-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/hit_react_cl.lua
-- PURPOSE: Visual bone-reaction to incoming damage.
--
-- ARCHITECTURE: ADDITIVE
--   We read the bone's current manipulation each frame and ADD
--   the flinch delta on top of it.  This means the flinch is
--   always visible regardless of what any other driver (kick,
--   spin, headbutt, bite, etc.) is doing to the same bone.
--   On flinch expiry we simply stop adding — we NEVER zero the
--   bone, so no other driver is disturbed.
--
-- NW VARS (written by init.lua):
--   GekkoHitReactPulse  (NWInt)    - increments on each hit
--   GekkoHitPos         (NW2Vector) - world hit position
--   GekkoHitDir         (NW2Vector) - normalised damage direction
--   GekkoHitLarge       (NW2Bool)   - true for explosive/large hits
--
-- ZONE → BONE MAP  (fraction of collision height from feet):
--   frac > 0.75  -> b_spine3        (torso/neck)   amp 0.6
--   frac > 0.45  -> b_pelvis        (core/hip)     amp 1.0
--   frac > 0.20  -> b_l/r_hippiston1 (thigh, sided) amp 1.0
--   frac <= 0.20 -> no reaction     (foot clips)
--
-- AXIS CONVENTIONS (from live bone-list + user notes):
--   b_spine1/2/3  : Angle( pitch, yaw,  roll )
--   b_pelvis      : Angle( yaw,   pitch, roll )  -- note swapped
--   b_r/l_hippiston1 : Angle( yaw, pitch, roll )
--
-- SCOPE: CLIENT only (included from cl_init.lua)
-- ============================================================
if not CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local RAMP_IN   = 0.07
local HOLD      = 0.10
local RAMP_OUT  = 0.22
local TOTAL_DUR = RAMP_IN + HOLD + RAMP_OUT   -- 0.39 s

local DEG_LARGE = 26
local DEG_SMALL = 13

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
-- Returns: boneIdx (int), ampScale (float), axisMode (string)
-- axisMode tells BuildFlinchAngle how to map pitch/yaw/roll
-- onto the bone's actual axis convention.
-- ============================================================
local function HR_SelectBone(self, hitPos)
    local _, maxs = self:GetCollisionBounds()
    local height  = math.max(maxs.z, 1)
    local frac    = math.Clamp((hitPos.z - self:GetPos().z) / height, 0, 1)

    if frac > ZONE_TORSO then
        -- b_spine3: axes are (pitch, yaw, roll) -- standard
        local idx = self:LookupBone("b_spine3")
        return (idx and idx >= 0) and idx or -1, 0.6, "spine"

    elseif frac > ZONE_HIP then
        -- b_pelvis: axes are (yaw, pitch, roll) -- p and y swapped
        local idx = self:LookupBone("b_pelvis")
        return (idx and idx >= 0) and idx or -1, 1.0, "pelvis"

    elseif frac > ZONE_THIGH then
        -- hippiston: axes are (yaw, pitch, roll)
        local side = (hitPos - self:GetPos()):Dot(self:GetRight())
        local name = (side >= 0) and "b_r_hippiston1" or "b_l_hippiston1"
        local idx  = self:LookupBone(name)
        return (idx and idx >= 0) and idx or -1, 1.0, "piston"

    else
        return -1, 0, "none"
    end
end

-- ============================================================
-- BUILD FLINCH ANGLE
-- Converts a hit-direction vector into a bone delta using the
-- correct axis convention for each zone.
-- ============================================================
local function HR_BuildFlinchAngle(self, hitDir, peakDeg, axisMode)
    local fwd   = self:GetForward()
    local right = self:GetRight()
    local up    = self:GetUp()

    -- Raw projections: how much the hit pushes along each axis.
    local push_fwd   = math.Clamp( hitDir:Dot(fwd),    -1, 1) * peakDeg
    local push_right = math.Clamp(-hitDir:Dot(right),   -1, 1) * peakDeg
    local push_up    = math.Clamp( hitDir:Dot(up),     -1, 1) * (peakDeg * 0.35)

    if axisMode == "spine" then
        -- b_spine1/2/3: Angle(pitch, yaw, roll)
        return Angle(push_fwd, push_right, push_up)

    elseif axisMode == "pelvis" then
        -- b_pelvis: Angle(yaw, pitch, roll)  -- p/y swapped
        return Angle(push_right, push_fwd, push_up)

    elseif axisMode == "piston" then
        -- b_r/l_hippiston1: Angle(yaw, pitch, roll)
        return Angle(push_right, push_fwd, push_up)

    else
        return Angle(0, 0, 0)
    end
end

-- ============================================================
-- PER-ENTITY STATE  (lazy-init on first Think call)
-- ============================================================
function ENT:HitReact_Init()
    self._hr_pulseLast  = self:GetNWInt("GekkoHitReactPulse", 0)
    self._hr_startTime  = -9999
    self._hr_boneIdx    = -1
    self._hr_peakAng    = Angle(0, 0, 0)
    self._hr_axisMode   = "none"
    self._hr_active     = false
end

-- ============================================================
-- MAIN THINK  (called every frame from ENT:Think in cl_init.lua)
-- ============================================================
function ENT:HitReact_Think()
    if self._hr_pulseLast == nil then self:HitReact_Init() end

    local pulse = self:GetNWInt("GekkoHitReactPulse", 0)

    -- --------------------------------------------------------
    -- New hit: pick bone and build peak angle
    -- --------------------------------------------------------
    if pulse ~= self._hr_pulseLast then
        self._hr_pulseLast = pulse

        local hitPos  = self:GetNW2Vector("GekkoHitPos",  self:GetPos())
        local hitDir  = self:GetNW2Vector("GekkoHitDir",  Vector(0, 1, 0))
        local isLarge = self:GetNW2Bool("GekkoHitLarge", false)

        local boneIdx, ampScale, axisMode = HR_SelectBone(self, hitPos)

        if boneIdx < 0 then
            self._hr_active = false
            return
        end

        local peakDeg = (isLarge and DEG_LARGE or DEG_SMALL) * ampScale

        self._hr_boneIdx   = boneIdx
        self._hr_axisMode  = axisMode
        self._hr_peakAng   = HR_BuildFlinchAngle(self, hitDir, peakDeg, axisMode)
        self._hr_startTime = CurTime()
        self._hr_active    = true
    end

    -- --------------------------------------------------------
    -- Nothing active - early out, touch NOTHING
    -- --------------------------------------------------------
    if not self._hr_active then return end

    local boneIdx = self._hr_boneIdx
    if not boneIdx or boneIdx < 0 then return end

    local elapsed = CurTime() - (self._hr_startTime or -9999)

    if elapsed < 0 or elapsed >= TOTAL_DUR then
        -- Flinch expired: mark inactive, DO NOT zero the bone.
        -- Whatever other driver owns this bone will write its own
        -- value next frame.  Zeroing here is what killed them before.
        self._hr_active = false
        return
    end

    -- --------------------------------------------------------
    -- Envelope: ramp in -> hold -> ramp out
    -- --------------------------------------------------------
    local env
    if elapsed < RAMP_IN then
        env = HR_Smooth(elapsed / RAMP_IN)
    elseif elapsed < RAMP_IN + HOLD then
        env = 1.0
    else
        env = 1.0 - HR_Smooth((elapsed - RAMP_IN - HOLD) / RAMP_OUT)
    end

    -- --------------------------------------------------------
    -- ADDITIVE WRITE:
    -- Read what the current manipulation already is (set by any
    -- other driver this frame), then add our flinch delta on top.
    -- This makes the hit react visible regardless of what else
    -- is driving the bone (spin, kick, headbutt, idle, etc.).
    -- --------------------------------------------------------
    local current = self:GetManipulateBoneAngles(boneIdx)
    local peak    = self._hr_peakAng

    self:ManipulateBoneAngles(boneIdx,
        Angle(
            current.p + peak.p * env,
            current.y + peak.y * env,
            current.r + peak.r * env
        ),
        false
    )
end
