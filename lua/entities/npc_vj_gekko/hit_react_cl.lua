-- hit_react_cl.lua  (CLIENT)
-- Handles clientside bone-driven hit reactions and Bushmaster recoil.
-- Included by cl_init.lua.
-- ============================================================
if SERVER then return end

-- ============================================================
--  HIT REACT
-- ============================================================

local HR_RAMP_IN   = 0.06
local HR_HOLD      = 0.10
local HR_RAMP_OUT  = 0.30
local HR_TOTAL     = HR_RAMP_IN + HR_HOLD + HR_RAMP_OUT

local HR_SPINE3_DEG = 22
local HR_SPINE4_DEG = 14

local function HR_Smooth(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

net.Receive("GekkoHitReact", function()
    local gekko    = net.ReadEntity()
    local hitDir   = net.ReadVector()
    local hitForce = net.ReadFloat()

    if not IsValid(gekko) then return end

    local s3 = gekko:LookupBone("b_spine3")
    local s4 = gekko:LookupBone("b_spine4")

    if type(s3) ~= "number" or s3 < 0 then return end
    if type(s4) ~= "number" or s4 < 0 then return end

    local noiseP = math.Remap(math.random(), 0, 1, -1.2, 1.2)
    local noiseR = math.Remap(math.random(), 0, 1, -0.8, 0.8)

    local forceMul = math.Clamp(hitForce / 200, 0.4, 1.4)

    local s3Peak = Angle(
        math.Clamp(-hitDir.y, -1, 1) * HR_SPINE3_DEG * forceMul + noiseP,
        math.Clamp( hitDir.z, -1, 1) * HR_SPINE3_DEG * 0.20 * forceMul,
        math.Clamp(-hitDir.x, -1, 1) * HR_SPINE3_DEG * 0.55 * forceMul + noiseR
    )
    local s4Peak = Angle(
        math.Clamp(-hitDir.y, -1, 1) * HR_SPINE4_DEG * forceMul + noiseP * 0.6,
        math.Clamp( hitDir.z, -1, 1) * HR_SPINE4_DEG * 0.20 * forceMul,
        math.Clamp(-hitDir.x, -1, 1) * HR_SPINE4_DEG * 0.55 * forceMul + noiseR * 0.6
    )

    gekko._hr_s3Idx     = s3
    gekko._hr_s4Idx     = s4
    gekko._hr_s3Peak    = s3Peak
    gekko._hr_s4Peak    = s4Peak
    gekko._hr_startTime = CurTime()
    gekko._hr_active    = true
end)

function ENT:HitReact_Think()
    if not self._hr_active then return end

    local s3 = self._hr_s3Idx
    local s4 = self._hr_s4Idx
    if not s3 or s3 < 0 or not s4 or s4 < 0 then
        self._hr_active = false
        return
    end

    local elapsed = CurTime() - (self._hr_startTime or -9999)
    if elapsed < 0 or elapsed >= HR_TOTAL then
        self._hr_active = false
        self:ManipulateBoneAngles(s3, Angle(0, 0, 0), false)
        self:ManipulateBoneAngles(s4, Angle(0, 0, 0), false)
        return
    end

    local env
    if elapsed < HR_RAMP_IN then
        env = HR_Smooth(elapsed / HR_RAMP_IN)
    elseif elapsed < HR_RAMP_IN + HR_HOLD then
        env = 1.0
    else
        env = 1.0 - HR_Smooth((elapsed - HR_RAMP_IN - HR_HOLD) / HR_RAMP_OUT)
    end

    local s3p = self._hr_s3Peak
    local s4p = self._hr_s4Peak
    self:ManipulateBoneAngles(s3, Angle(s3p.p * env, s3p.y * env, s3p.r * env), true)
    self:ManipulateBoneAngles(s4, Angle(s4p.p * env, s4p.y * env, s4p.r * env), true)
end


-- ============================================================
-- BUSHMASTER FIRE-RECOIL  (separate from HitReact, no prob gate)
-- Bone: b_spine3.  Always fires on every shot.
-- Architecture: ABSOLUTE write, same envelope as hit_react_cl.
-- State vars prefixed _bfr_* to never collide with _hr_* above.
-- Triggered by net message "GekkoBushRecoil" sent from init.lua
-- when the Bushmaster fires.  Call BushmasterRecoil_Think(self)
-- from ENT:Think() in cl_init.lua alongside HitReact_Think.
-- ============================================================
local BFR_RAMP_IN  = 0.05
local BFR_HOLD     = 0.07
local BFR_RAMP_OUT = 0.18
local BFR_TOTAL    = BFR_RAMP_IN + BFR_HOLD + BFR_RAMP_OUT   -- 0.30 s

local BFR_DEG      = 18   -- peak degrees. Tune: 12 subtle, 22 punchy.

local function BFR_Smooth(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

net.Receive("GekkoBushRecoil", function()
    local gekko     = net.ReadEntity()
    local src       = net.ReadVector()
    local recoilDir = net.ReadVector()   -- already normalized -dir from server

    if not IsValid(gekko) then return end

    -- ── Bone recoil (existing) ────────────────────────────────────────────────
    local boneIdx = gekko:LookupBone("b_spine3")
    if type(boneIdx) ~= "number" or boneIdx < 0 then return end

    local noiseP = math.Remap(math.random(), 0, 1, -0.8, 0.8)
    local noiseR = math.Remap(math.random(), 0, 1, -0.8, 0.8)
    local peakAng = Angle(
        math.Clamp(recoilDir.y, -1, 1) * BFR_DEG + noiseP,
        math.Clamp(recoilDir.z, -1, 1) * BFR_DEG * 0.15,
        math.Clamp(recoilDir.x, -1, 1) * BFR_DEG * 0.6 + noiseR
    )

    gekko._bfr_boneIdx   = boneIdx
    gekko._bfr_peakAng   = peakAng
    gekko._bfr_startTime = CurTime()
    gekko._bfr_active    = true

    -- ── Shell casing  (CW-base pattern, louder than MG) ───────────────────────
    -- recoilDir is the cannon's fire direction; the ejection port sits at src.
    -- Convert the fire direction to an Angle so Right()/Up() give us the
    -- sideways/upward axes for the CW-style eject velocity.
    GekkoSpawnBushmasterShell(src, recoilDir:Angle())
end)

function BushmasterRecoil_Think(self)
    if not self._bfr_active then return end
    local boneIdx = self._bfr_boneIdx
    if not boneIdx or boneIdx < 0 then self._bfr_active = false; return end

    local elapsed = CurTime() - (self._bfr_startTime or -9999)
    if elapsed < 0 or elapsed >= BFR_TOTAL then
        self._bfr_active = false
        self:ManipulateBoneAngles(boneIdx, Angle(0, 0, 0), false)
        return
    end

    local env
    if elapsed < BFR_RAMP_IN then
        env = BFR_Smooth(elapsed / BFR_RAMP_IN)
    elseif elapsed < BFR_RAMP_IN + BFR_HOLD then
        env = 1.0
    else
        env = 1.0 - BFR_Smooth((elapsed - BFR_RAMP_IN - BFR_HOLD) / BFR_RAMP_OUT)
    end

    local peak = self._bfr_peakAng
    self:ManipulateBoneAngles(boneIdx,
        Angle(peak.p * env, peak.y * env, peak.r * env),
        true
    )
end
