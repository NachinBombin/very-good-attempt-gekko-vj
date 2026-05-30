-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v4.7
--
-- WHITELIST IS ABSOLUTE AND EVALUATED BEFORE ALL PILLARS.
-- Nothing on the whitelist is ever intercepted.
--
-- THREAT DETECTION: 4 fully independent pillars.
-- ANY single pillar alone is sufficient to flag a threat:
--   1. Exact blacklist match  (APS_INTERCEPT_TARGETS)
--   2. Class-name pattern     (missile / rocket / grenade / etc.)
--      + minimum speed gate   (>= APS_PATTERN_MIN_SPEED)
--   3. Speed alone            (>= APS_MIN_SPEED)
--   4. Heading dot alone      (>= APS_HEADING_DOT, toward Gekko)
--      + minimum speed gate   (>= APS_HEADING_MIN_SPEED)
--
-- Pillars are independent. Each fires on its own.
-- No pillar was merged or removed.
--
-- ── v4.7 CHANGES ─────────────────────────────────────────────
--
-- FIX  — Burst sound guaranteed to play for a full second.
--   CreateSound handle stored on self._apsBurstSnd.  A 1-second
--   timer started at burst begin stops it.  The only early stop
--   is GekkoAPS_Kill(), called when the Gekko dies.  Previously
--   the local variable was discarded before the stop timer fired,
--   so Stop() was never called on the correct handle, leaving the
--   sound silent or cut immediately.
--
-- NEW  — Dual independent laser tracking (2 slots).
-- ============================================================
if CLIENT then return end  -- all logic is server-side

-- ============================================================
-- TUNING CONSTANTS
-- ============================================================
local APS_SCAN_RADIUS    = 1500   -- units: how far to look for threats
local APS_LASER_RADIUS   = 1200   -- units: range where laser is drawn
local APS_INTERCEPT_DIST =  450   -- units: intercept if threat is this close
local APS_SCAN_INTERVAL  = 0.20   -- seconds between scans
local APS_REARM_DELAY    = 3.0    -- seconds before next scan after intercept
local APS_BURST_SHOTS    = 6      -- bullets per burst
local APS_BURST_INTERVAL = 0.05   -- seconds between burst shots
local APS_BURST_SND      = "gekko/aps/aps_burst_01.wav"
local APS_BURST_SND_DURATION = 1.0 -- seconds the burst sound runs

local APS_MIN_SPEED          = 350   -- pillar 3: minimum speed (u/s) for speed-only intercept
local APS_PATTERN_MIN_SPEED  = 150   -- pillar 2: speed gate for pattern intercepts
local APS_HEADING_DOT        = 0.60  -- pillar 4: minimum dot toward Gekko
local APS_HEADING_MIN_SPEED  = 100   -- pillar 4: speed gate for heading intercepts

-- ============================================================
-- BLACKLIST / WHITELIST
-- APS_INTERCEPT_TARGETS  → ALWAYS intercept (exact class name)
-- APS_WHITELIST          → NEVER intercept  (exact class name)
-- ============================================================
local APS_INTERCEPT_TARGETS = {
    ["obj_gekko_rocket"]        = false,   -- own rockets: whitelisted below
    ["sent_npc_topmissile"]     = true,
    ["sent_npc_trackmissile"]   = true,
    ["rpg_rocket"]              = true,
    ["hl2_grenade"]             = true,
    ["grenade_ar2"]             = true,
    ["combine_mine"]            = true,
    ["prop_physics"]            = false,   -- not blacklisted, detected by speed
}

local APS_WHITELIST = {
    ["obj_gekko_rocket"]        = true,   -- own rockets never intercepted
    ["npc_vj_gekko"]            = true,
    ["npc_vj_gekko_nikita"]     = true,
    ["player"]                  = true,
    ["npc_bullseye"]            = true,
    -- anchor physboxes used by the elastic system:
    ["prop_physics"]            = false,   -- allowed through speed / heading pillars
    -- Nikita missile entity from the Gekko itself:
    ["obj_gekko_nikita"]        = true,
    -- Elastic anchor:
    -- (plain phys entities spawned by MakeAnchor have no special class)
}

-- Additional class-name patterns that trigger pillar 2.
-- Checked with string.find(class, pattern, 1, true).
local APS_PATTERN_CLASSES = {
    "missile", "rocket", "grenade", "rpg", "mortar", "bomb",
    "projectile", "shell", "shot", "bolt",
}

-- ============================================================
-- ENTITIES PRODUCED BY GEKKO SYSTEMS (never intercept these)
-- by the Gekko itself.  All of them already receive
-- ============================================================
local GEKKO_OWN_CLASSES = {
    ["obj_gekko_rocket"]    = true,
    ["sent_gekko_bushmaster"] = true,
    ["obj_gekko_nikita"]    = true,
}

-- ============================================================
-- HELPERS
-- ============================================================
local function IsAliveAndValid(e)
    return IsValid(e) and not e:IsPlayer() and e:Health() > 0
end

local function IsNikitaOrProjectile(e)
    if not IsValid(e) then return false end
    local c = e:GetClass()
    return GEKKO_OWN_CLASSES[c] == true
end

-- ============================================================
-- THREAT CLASSIFICATION (4 independent pillars)
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()

    -- Whitelist is absolute
    if APS_WHITELIST[class] then return false end
    -- Own-class whitelist
    if GEKKO_OWN_CLASSES[class] then return false end
    -- Must be moving to be a threat (avoids detecting static props)
    local vel  = ent:GetAbsVelocity()
    local spd  = vel:Length()

    -- Pillar 1: exact blacklist
    if APS_INTERCEPT_TARGETS[class] == true then return true end

    -- Pillar 2: pattern match + speed gate
    if spd >= APS_PATTERN_MIN_SPEED then
        for _, pat in ipairs(APS_PATTERN_CLASSES) do
            if string.find(class, pat, 1, true) then return true end
        end
    end

    -- Pillar 3: pure speed
    if spd >= APS_MIN_SPEED then return true end

    -- Pillar 4: heading toward Gekko + speed gate
    if spd >= APS_HEADING_MIN_SPEED then
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        local velNorm = vel:GetNormalized()
        if velNorm:Dot(toGekko) >= APS_HEADING_DOT then return true end
    end

    return false
end

-- ============================================================
-- SCAN FOR THREATS IN RADIUS
-- ============================================================
local function APS_FindThreats(self)
    local nearby = ents.FindInSphere(self:GetPos(), APS_SCAN_RADIUS)
    local threats = {}
    for _, ent in ipairs(nearby) do
        if APS_IsThreat(self, ent) then
            threats[#threats + 1] = ent
        end
    end
    return threats
end

local function APS_ThreatInInterceptRadius(self, ent)
    return self:GetPos():Distance(ent:GetPos()) <= APS_SCAN_RADIUS
end

-- ============================================================
-- MUZZLE POSITION HELPER
-- Returns the world-space muzzle/laser origin, fully model-relative.
-- Primary:  GetAttachment(attIdx).Pos  -- already model-relative in GMod.
-- Fallback: bone matrix translation + bone Up * offset, so the point
--           follows the NPC model even during crouch or leg-down tilt.
-- ============================================================
local function APS_GetMuzzlePos(self, attIdx)
    local attData = self:GetAttachment(attIdx or 3)
    if attData then return attData.Pos end
    -- Bone-relative fallback: use spine or pelvis bone so muzzle tracks
    -- the model even when the NPC is crouching or downed by leg disable.
    local boneIdx = self.GekkoSpineBone or self.GekkoPelvisBone or -1
    if boneIdx >= 0 then
        local m = self:GetBoneMatrix(boneIdx)
        if m then return m:GetTranslation() + m:GetUp() * 60 end
    end
    -- Last resort: entity origin + model-relative up offset
    local up = self:GetAngles():Up()
    return self:GetPos() + up * 180
end

-- ============================================================
-- LASER TRACKING BROADCAST
-- ============================================================
local function APS_BroadcastLaser(self, threat, slotIndex)
    if not IsValid(threat) then return end
    local src = APS_GetMuzzlePos(self, 3)
    net.Start("GekkoAPSLaser")
        net.WriteVector(src)
        net.WriteVector(threat:GetPos())
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteUInt(slotIndex, 4)
    net.Broadcast()
end

-- ============================================================
-- BURST SOUND
-- ============================================================
local function APS_PlayBurstSound(self)
    if self._apsBurstSnd then
        self._apsBurstSnd:Stop()
        self._apsBurstSnd = nil
    end
    if self._apsBurstSndTimer then
        timer.Remove(self._apsBurstSndTimer)
        self._apsBurstSndTimer = nil
    end

    local snd = CreateSound(self, APS_BURST_SND)
    if not snd then return end
    snd:PlayEx(0.85, math.random(97, 108))

    self._apsBurstSnd = snd

    local timerName = "GekkoAPS_burstSnd_" .. self:EntIndex()
    self._apsBurstSndTimer = timerName
    timer.Create(timerName, APS_BURST_SND_DURATION, 1, function()
        if IsValid(self) and self._apsBurstSnd then
            self._apsBurstSnd:Stop()
            self._apsBurstSnd      = nil
            self._apsBurstSndTimer = nil
        end
    end)
end

-- ============================================================
-- BURST FIRE
-- ============================================================
local function APS_FireBurst(self, interceptPos)
    local timerName = "GekkoAPS_burst_" .. self:EntIndex()
    timer.Remove(timerName)

    APS_PlayBurstSound(self)

    local shotsFired = 0
    timer.Create(timerName, APS_BURST_INTERVAL, APS_BURST_SHOTS, function()
        if not IsValid(self) then timer.Remove(timerName); return end
        shotsFired = shotsFired + 1

        local attIdx  = (shotsFired % 2 == 0) and 9 or 3
        local src = APS_GetMuzzlePos(self, attIdx)
        local dir = (interceptPos - src):GetNormalized()

        net.Start("GekkoAPSIntercept")
            net.WriteVector(src)
            net.WriteVector(dir)
            net.WriteVector(interceptPos)
            net.WriteBool(shotsFired == 1)
            net.WriteUInt(self:EntIndex(), 16)
        net.Broadcast()

        if shotsFired == 1 then
            net.Start("GekkoMuzzleFlash")
                net.WriteVector(src)
                net.WriteVector(dir)
                net.WriteUInt(1, 3)
            net.Broadcast()
        end
    end)
end

-- ============================================================
-- INTERCEPT
-- ============================================================
local function APS_Intercept(self, threat)
    if not IsValid(threat) then return end

    local targetPos = threat:GetPos()

    -- Nudge the intercept point slightly ahead of the threat
    local vel = threat:GetAbsVelocity()
    if vel:LengthSqr() > 1 then
        targetPos = targetPos + vel:GetNormalized() * 40
    end

    local ed = EffectData()
    ed:SetOrigin(targetPos)
    ed:SetScale(2)
    util.Effect("Explosion", ed)

    threat:TakeDamage(threat:GetMaxHealth() * 2, self, self)

    APS_FireBurst(self, targetPos)

    self._apsNextScanT = CurTime() + APS_REARM_DELAY
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function ENT:GekkoAPS_Init()
    self._apsNextScanT  = 0
    self._apsActive     = true
    self._apsLockedEnts = {}
    self._apsBurstSnd   = nil
    self._apsBurstSndTimer = nil
    print("[GekkoAPS] Initialised on " .. self:EntIndex())
end

function ENT:GekkoAPS_Kill()
    if self._apsBurstSnd then
        self._apsBurstSnd:Stop()
        self._apsBurstSnd = nil
    end
    if self._apsBurstSndTimer then
        timer.Remove(self._apsBurstSndTimer)
        self._apsBurstSndTimer = nil
    end
    self._apsActive = false
end

function ENT:GekkoAPS_Think()
    if self._gekkoDead         then return end
    if not self._apsActive     then return end
    if CurTime() < (self._apsNextScanT or 0) then return end

    self._apsNextScanT = CurTime() + APS_SCAN_INTERVAL

    local stillLocked = {}
    for slotIndex, threat in ipairs(self._apsLockedEnts) do
        if IsValid(threat) and
           APS_IsThreat(self, threat) and
           self:GetPos():Distance(threat:GetPos()) <= APS_LASER_RADIUS
        then
            APS_BroadcastLaser(self, threat, slotIndex - 1)

            if APS_ThreatInInterceptRadius(self, threat) then
                APS_Intercept(self, threat)
            else
                stillLocked[#stillLocked + 1] = threat
            end
        end
    end
    self._apsLockedEnts = stillLocked

    if CurTime() < (self._apsNextScanT or 0) then return end  -- intercept may have reset timer

    -- Acquire new threats
    local threats = APS_FindThreats(self)
    for _, threat in ipairs(threats) do
        -- check not already tracked
        local alreadyTracked = false
        for _, t in ipairs(self._apsLockedEnts) do
            if t == threat then alreadyTracked = true; break end
        end
        if not alreadyTracked and #self._apsLockedEnts < 2 then
            self._apsLockedEnts[#self._apsLockedEnts + 1] = threat
        end
    end
end
