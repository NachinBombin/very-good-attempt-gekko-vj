-- ============================================================
-- FILE: lua/entities/npc_vj_gekko/hit_react_cl.lua
-- PURPOSE: Visual bone-reaction to incoming damage.
--
-- ARCHITECTURE: ABSOLUTE
--   We write peak * envelope directly each frame. The bone is
--   zeroed on expiry. This prevents accumulation across hits or
--   frames. Each flinch is a self-contained impulse.
--
-- NW VARS (written by gekko_juicy_bleeding.lua):
--   GekkoHitReactPulse  (NWInt)     - increments on each hit
--   GekkoHitPos         (NW2Vector) - world hit position
--   GekkoHitDir         (NW2Vector) - normalised damage direction
--   GekkoHitLarge       (NW2Bool)   - true for explosive/large hits
--
-- ZONE -> BONE MAP  (fraction of collision height from feet):
--   frac > 0.75  -> b_spine3               (upper torso)  amp 0.6
--   frac > 0.45  -> b_r/l_hippiston1       (hip, sided)   amp 1.0
--   frac > 0.20  -> b_r/l_calf1            (leg, sided)   amp 0.9
--   frac <= 0.20 -> no reaction
--
-- WORLD-SPACE AXIS MAPPING (all zones, orientation-independent):
--   hitDir.x (world lateral)  -> roll  (lean left/right)
--   hitDir.y (world forward)  -> pitch (nod fwd/back)
--   hitDir.z (world vertical) -> yaw   (axial twist, suppressed)
-- Each axis gets an independent per-hit jitter weight [0.4, 1.0].
-- Overall amplitude is also jittered [0.75, 1.25] per hit.
--
-- FIRE PROBABILITY: 50%  (HR_FIRE_CHANCE)
--   Half of all incoming pulses are silently skipped so the
--   reaction feels occasional rather than mechanical.
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

local DEG_LARGE = 38
local DEG_SMALL = 24

local HR_FIRE_CHANCE  = 0.50   -- probability a hit triggers a reaction

-- Per-hit jitter (applied to every zone)
local JITTER_AMP_MIN  = 0.75   -- overall amplitude multiplier range
local JITTER_AMP_MAX  = 1.25
local JITTER_AXIS_MIN = 0.40   -- per-axis weight (never fully zero)
local JITTER_AXIS_MAX = 1.00
local NOISE_DEG       = 1.2    -- +/- pure noise degrees on pitch and roll

-- Vertical axis (hitDir.z) suppression per zone
-- (twist looks wrong at full amplitude on limb bones)
local YAW_SCALE_SPINE  = 0.30
local YAW_SCALE_PISTON = 0.39
local YAW_SCALE_CALF   = 0.35

local ZONE_TORSO = 0.75
local ZONE_HIP   = 0.45
local ZONE_THIGH = 0.20

-- ============================================================
-- SAFE BONE LOOKUP
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
-- Returns: boneIdx, ampScale, axisMode, boneName, frac
-- ============================================================
local function HR_SelectBone(self, hitPos)
    local _, maxs = self:GetCollisionBounds()
    local height  = math.max(maxs.z, 1)
    local frac    = math.Clamp((hitPos.z - self:GetPos().z) / height, 0, 1)

    if frac > ZONE_TORSO then
        local idx = HR_LookupBone(self, "b_spine3")
        return idx, 0.6, "spine3", "b_spine3", frac

    elseif frac > ZONE_HIP then
        -- b_pelvis/b_pedestal NEVER touched: they move the whole entity
        local side = (hitPos - self:GetPos()):Dot(self:GetRight())
        local name = (side >= 0) and "b_r_hippiston1" or "b_l_hippiston1"
        local idx  = HR_LookupBone(self, name)
        return idx, 1.0, "piston", name, frac

    elseif frac > ZONE_THIGH then
        local side = (hitPos - self:GetPos()):Dot(self:GetRight())
        local name = (side >= 0) and "b_r_calf1" or "b_l_calf1"
        local idx  = HR_LookupBone(self, name)
        if idx < 0 then
            name = (side >= 0) and "b_r_thigh1" or "b_l_thigh1"
            idx  = HR_LookupBone(self, name)
        end
        return idx, 0.9, "calf", name, frac

    else
        return -1, 0, "none", "none", frac
    end
end

-- ============================================================
-- BUILD FLINCH ANGLE  (world-space mapping, all zones)
--
-- We map hitDir world components directly onto bone axes.
-- This is orientation-independent: the result is the same
-- regardless of which way the Gekko is facing, unlike
-- entity-local dot products which collapse when the Gekko
-- faces away from the attacker.
--
-- Mapping (shared by all zones):
--   hitDir.x -> roll   (lateral lean)
--   hitDir.y -> pitch  (fwd/back nod)
--   hitDir.z -> yaw    (axial twist, per-zone suppression)
--
-- Bone axis conventions (Angle = pitch, yaw, roll in GMod):
--   b_spine3         Angle( yaw_scale*z, x, y )  -- yaw,roll,pitch
--   b_r/l_hippiston1 Angle( yaw_scale*z, y, x )  -- yaw,pitch,roll
--   b_r/l_calf1      Angle( yaw_scale*z, y, x )  -- yaw,pitch,roll
-- ============================================================
local function HR_BuildFlinchAngle(hitDir, peakDeg, axisMode)
    -- Per-hit randomisation
    local amp    = math.Remap(math.random(), 0, 1, JITTER_AMP_MIN,  JITTER_AMP_MAX)
    local wX     = math.Remap(math.random(), 0, 1, JITTER_AXIS_MIN, JITTER_AXIS_MAX)
    local wY     = math.Remap(math.random(), 0, 1, JITTER_AXIS_MIN, JITTER_AXIS_MAX)
    local noiseP = math.Remap(math.random(), 0, 1, -NOISE_DEG, NOISE_DEG)
    local noiseR = math.Remap(math.random(), 0, 1, -NOISE_DEG, NOISE_DEG)

    local dx = math.Clamp(hitDir.x, -1, 1) * peakDeg * amp
    local dy = math.Clamp(hitDir.y, -1, 1) * peakDeg * amp
    local dz = math.Clamp(hitDir.z, -1, 1) * peakDeg * amp

    if axisMode == "spine3" then
        -- Angle( yaw, roll, pitch )
        return Angle(
            dz * YAW_SCALE_SPINE,
            dx * wX + noiseR,
            dy * wY + noiseP
        )

    elseif axisMode == "piston" then
        -- Angle( yaw, pitch, roll )
        return Angle(
            dz * YAW_SCALE_PISTON,
            dy * wY + noiseP,
            dx * wX + noiseR
        )

    elseif axisMode == "calf" then
        -- Angle( yaw, pitch, roll )
        return Angle(
            dz * YAW_SCALE_CALF,
            dy * wY + noiseP,
            dx * wX + noiseR
        )
    end

    return Angle(0, 0, 0)
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

        -- Zero previous bone immediately before any early-out
        if self._hr_active and self._hr_boneIdx and self._hr_boneIdx >= 0 then
            self:ManipulateBoneAngles(self._hr_boneIdx, Angle(0, 0, 0), false)
            self._hr_active = false
        end

        -- 50% probability gate -- skip silently half the time
        if math.random() > HR_FIRE_CHANCE then
            print(string.format("[HitReact] pulse=%d SKIPPED (probability)", pulse))
            return
        end

        local hitPos  = self:GetNW2Vector("GekkoHitPos",  self:GetPos())
        local hitDir  = self:GetNW2Vector("GekkoHitDir",  Vector(0, 1, 0))
        local isLarge = self:GetNW2Bool("GekkoHitLarge", false)

        local boneIdx, ampScale, axisMode, boneName, frac =
            HR_SelectBone(self, hitPos)

        local peakDeg = (isLarge and DEG_LARGE or DEG_SMALL) * ampScale

        print(string.format(
            "[HitReact] HIT pulse=%d | hitPos=(%.0f,%.0f,%.0f) frac=%.2f | zone=%s bone=%s idx=%d | large=%s peakDeg=%.1f",
            pulse, hitPos.x, hitPos.y, hitPos.z, frac,
            axisMode, boneName, boneIdx, tostring(isLarge), peakDeg
        ))

        if boneIdx < 0 then
            print("[HitReact] -> bone not found or foot-zone, skipping")
            return
        end

        local peakAng = HR_BuildFlinchAngle(hitDir, peakDeg, axisMode)

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
        self:ManipulateBoneAngles(boneIdx, Angle(0, 0, 0), false)
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
    -- ABSOLUTE WRITE  (peak * envelope, no accumulation)
    -- --------------------------------------------------------
    local peak = self._hr_peakAng

    self:ManipulateBoneAngles(boneIdx,
        Angle(
            peak.p * env,
            peak.y * env,
            peak.r * env
        ),
        true
    )
end