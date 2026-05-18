-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/hit_react_cl.lua
-- PURPOSE: Visual bone-reaction to incoming damage.
--
-- ARCHITECTURE: ADDITIVE
--   We read the bone's current manipulation each frame and ADD
--   the flinch delta on top of it.  This means the flinch is
--   always visible regardless of what any other driver (kick,
--   spin, headbutt, bite, etc.) is doing to the same bone.
--   On flinch expiry we simply stop adding -- we NEVER zero the
--   bone, so no other driver is disturbed.
--
-- NW VARS (written by init.lua):
--   GekkoHitReactPulse  (NWInt)     - increments on each hit
--   GekkoHitPos         (NW2Vector) - world hit position
--   GekkoHitDir         (NW2Vector) - normalised damage direction
--   GekkoHitLarge       (NW2Bool)   - true for explosive/large hits
--
-- ZONE -> BONE MAP  (fraction of collision height from feet):
--   frac > 0.75  -> b_spine4          (torso/neck)    amp 0.6
--   frac > 0.45  -> b_pelvis          (core/hip)      amp 1.0
--   frac > 0.20  -> b_r/l_hippiston1  (thigh, sided)  amp 1.0
--   frac <= 0.20 -> no reaction       (foot clips)
--
-- AXIS CONVENTIONS (confirmed from live 72-bone skeleton dump):
--   b_spine4          : Angle( yaw,   roll,  pitch )
--   b_pelvis          : Angle( yaw,   pitch, roll  )
--   b_r/l_hippiston1  : Angle( yaw,   pitch, roll  )
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
-- SAFE BONE LOOKUP
-- GMod LookupBone returns false (not -1 or nil) on failure.
-- This wrapper always returns a plain integer (-1 on failure)
-- so all callers can safely use idx >= 0 without type errors.
-- ============================================================
local function HR_LookupBone(ent, name)
    local idx = ent:LookupBone(name)
    if type(idx) ~= "number" then
        print(string.format("[HitReact] WARN: LookupBone('%s') returned %s -- bone missing?",
            name, tostring(idx)))
        return -1
    end
    return idx
end

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
-- ============================================================
local function HR_SelectBone(self, hitPos)
    local _, maxs = self:GetCollisionBounds()
    local height  = math.max(maxs.z, 1)
    local frac    = math.Clamp((hitPos.z - self:GetPos().z) / height, 0, 1)

    if frac > ZONE_TORSO then
        local idx = HR_LookupBone(self, "b_spine4")
        return idx, 0.6, "spine4", "b_spine4", frac

    elseif frac > ZONE_HIP then
        local idx = HR_LookupBone(self, "b_pelvis")
        return idx, 1.0, "pelvis", "b_pelvis", frac

    elseif frac > ZONE_THIGH then
        local side = (hitPos - self:GetPos()):Dot(self:GetRight())
        local name = (side >= 0) and "b_r_hippiston1" or "b_l_hippiston1"
        local idx  = HR_LookupBone(self, name)
        return idx, 1.0, "piston", name, frac

    else
        return -1, 0, "none", "none", frac
    end
end

-- ============================================================
-- BUILD FLINCH ANGLE
-- Maps hit-direction onto bone-local axes using the confirmed
-- axis conventions from the live 72-bone skeleton dump.
--
--   b_spine4         : Angle( yaw,   roll,  pitch )
--   b_pelvis         : Angle( yaw,   pitch, roll  )
--   b_r/l_hippiston1 : Angle( yaw,   pitch, roll  )
-- ============================================================
local function HR_BuildFlinchAngle(self, hitDir, peakDeg, axisMode)
    local fwd   = self:GetForward()
    local right = self:GetRight()
    local up    = self:GetUp()

    local push_fwd   = math.Clamp( hitDir:Dot(fwd),   -1, 1) * peakDeg
    local push_right = math.Clamp(-hitDir:Dot(right),  -1, 1) * peakDeg
    local push_up    = math.Clamp( hitDir:Dot(up),    -1, 1) * (peakDeg * 0.35)

    local ang
    if axisMode == "spine4" then
        -- Angle( yaw, roll, pitch )
        ang = Angle(push_right, push_up, push_fwd)

    elseif axisMode == "pelvis" then
        -- Angle( yaw, pitch, roll )
        ang = Angle(push_right, push_fwd, push_up)

    elseif axisMode == "piston" then
        -- Angle( yaw, pitch, roll )
        ang = Angle(push_right, push_fwd, push_up)

    else
        ang = Angle(0, 0, 0)
    end

    return ang
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
    print("[HitReact] Initialised on ent " .. tostring(self:EntIndex()))
end

-- ============================================================
-- MAIN THINK  (called every frame from ENT:Think in cl_init.lua)
-- ============================================================
function ENT:HitReact_Think()
    if self._hr_pulseLast == nil then self:HitReact_Init() end

    local pulse = self:GetNWInt("GekkoHitReactPulse", 0)

    -- --------------------------------------------------------
    -- New hit detected
    -- --------------------------------------------------------
    if pulse ~= self._hr_pulseLast then
        self._hr_pulseLast = pulse

        local hitPos  = self:GetNW2Vector("GekkoHitPos",  self:GetPos())
        local hitDir  = self:GetNW2Vector("GekkoHitDir",  Vector(0, 1, 0))
        local isLarge = self:GetNW2Bool("GekkoHitLarge", false)

        local boneIdx, ampScale, axisMode, boneName, frac =
            HR_SelectBone(self, hitPos)

        local peakDeg = (isLarge and DEG_LARGE or DEG_SMALL) * ampScale

        -- DEBUG: always print hit info so we can verify in console
        print(string.format(
            "[HitReact] HIT pulse=%d | hitPos=(%.0f,%.0f,%.0f) frac=%.2f | zone=%s bone=%s idx=%d | large=%s peakDeg=%.1f",
            pulse,
            hitPos.x, hitPos.y, hitPos.z, frac,
            axisMode, boneName, boneIdx,
            tostring(isLarge), peakDeg
        ))

        if boneIdx < 0 then
            print("[HitReact] -> bone not found or foot-zone, skipping")
            self._hr_active = false
            return
        end

        local peakAng = HR_BuildFlinchAngle(self, hitDir, peakDeg, axisMode)

        print(string.format(
            "[HitReact] -> flinchAngle=(p=%.1f y=%.1f r=%.1f) dir=(%.2f,%.2f,%.2f)",
            peakAng.p, peakAng.y, peakAng.r,
            hitDir.x, hitDir.y, hitDir.z
        ))

        self._hr_boneIdx   = boneIdx
        self._hr_axisMode  = axisMode
        self._hr_peakAng   = peakAng
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
    -- ADDITIVE WRITE
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
