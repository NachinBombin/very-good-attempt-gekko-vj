-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v3.1
--
-- Lock-on / intercept range split:
--   APS_LASER_RADIUS   = 2000u  -- laser acquires and tracks here
--   APS_SCAN_RADIUS    = 1200u  -- intercept fires when threat enters here
--
-- Flow:
--   1. Threat enters 2000u  -> lock acquired, laser beam starts tracking
--   2. Threat crosses 1200u -> APS fires, beam snaps off
--   3. If threat leaves 2000u before reaching 1200u -> lock resets
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_LASER_RADIUS   = 2000    -- outer radius: laser acquisition
local APS_SCAN_RADIUS    = 1200    -- inner radius: intercept trigger
local APS_MIN_SPEED      = 350     -- u/s threshold
local APS_SCAN_INTERVAL  = 0.05    -- seconds between scans / laser ticks
local APS_REARM_DELAY    = 0.30    -- cooldown after each intercept
local APS_BURST_SHOTS    = 4       -- muzzle flash pulses per intercept
local APS_BURST_INTERVAL = 0.040   -- seconds between burst pulses
local APS_HEADING_DOT    = 0.25    -- dot-product floor toward Gekko

-- ============================================================
-- OWNED MUNITION WHITELIST
-- Only Gekko's own projectiles are listed here.
-- obj_vj_rocket is a generic VJ base rocket — NOT owned by Gekko,
-- must be intercepted.
-- ============================================================
local APS_OWNED_CLASSES = {
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["obj_gekko_rocket"]      = true,   -- Gekko's own rocket
    ["sent_orbital_rpg"]      = true,
    ["sent_gekko_bushmaster"] = true,
    ["bombin_gas_grenade"]    = true,
    ["ent_gas_stun"]          = true,
    ["ent_flashbang"]         = true,
    ["prop_physics"]          = true,
    ["prop_dynamic"]          = true,
}

-- ============================================================
-- THREAT TABLE
-- ============================================================
local APS_INTERCEPT_TARGETS = {
    ["rpg_missile"]               = true,
    ["grenade_ar2"]               = true,
    ["npc_grenade_frag"]          = true,
    ["prop_combine_ball"]         = true,
    ["hunter_flechette"]          = true,
    ["crossbow_bolt"]             = true,
    ["grenade_helicopter"]        = true,
    ["combine_mine"]              = true,
    ["npc_satchel"]               = true,
    ["satchel_charge"]            = true,
    ["npc_manhack"]               = true,
    ["obj_vj_grenade"]            = true,
    ["obj_vj_rocket"]             = true,   -- enemy VJ rocket — intercept
    ["obj_vj_flechette"]          = true,
    ["sent_javelin_missile"]      = true,
    ["sent_stinger_missile"]      = true,
    ["neuro_missile"]             = true,
    ["neuro_rocket"]              = true,
    ["m9k_released_rpg"]          = true,
    ["m9k_davy_crockett_payload"] = true,
    ["m9k_40mm_grenade"]          = true,
    ["m9k_mad_grenade"]           = true,
    ["cw_grenade_thrown"]         = true,
    ["fas2_thrown_m67"]           = true,
    ["wac_hc_rocket"]             = true,
    ["lvs_missile"]               = true,
    ["lfs_missile"]               = true,
    ["lfs_rocket"]                = true,
    ["lfs_torpedo"]               = true,
    ["tfa_proj_arrow"]            = true,
    ["tfa_proj_arrow_fire"]       = true,
    ["tfa_arrow"]                 = true,
    ["tfa_missile"]               = true,
    ["tfa_rocket"]                = true,
    ["tfa_proj_grenade"]          = true,
    ["tfa_thrown_knife"]          = true,
    ["mw_throwingknife"]          = true,
    ["mw_missile"]                = true,
    ["mw_rocket"]                 = true,
    ["mw_gl_grenade"]             = true,
    ["mw_fraggrenade"]            = true,
    ["mw_semtex"]                 = true,
    ["mw_flashbang"]              = true,
    ["mw_smokegrenade"]           = true,
    ["arccw_rocket"]              = true,
    ["arccw_missile"]             = true,
    ["arccw_gl_projectile"]       = true,
    ["arccw_grenade_thrown"]      = true,
    ["arccw_c4"]                  = true,
    ["arccw_semtex"]              = true,
    ["arccw_flashbang"]           = true,
    ["arccw_smoke"]               = true,
    ["arccw_thermite"]            = true,
    ["arccw9_rocket"]             = true,
    ["arccw9_missile"]            = true,
    ["arccw9_gl_projectile"]      = true,
    ["arccw9_thrown_grenade"]     = true,
    ["arccw9_c4"]                 = true,
    ["simfphys_missile"]          = true,
    ["simfphys_rocket"]           = true,
    ["simfphys_tankrocket"]       = true,
    ["simfphys_glshell"]          = true,
    ["drg_projectile"]            = true,
    ["drg_grenade"]               = true,
    ["drg_rocket"]                = true,
    ["sent_homingrocket"]         = true,
    ["sent_guidedmissile"]        = true,
    ["sent_stickynade"]           = true,
    ["sent_cluster_grenade"]      = true,
    ["sent_flashbang"]            = true,
}

-- ============================================================
-- SOUNDS
-- ============================================================
local APS_INTERCEPT_SNDS = {
    "ambient/explosions/explode_4.wav",
    "ambient/explosions/explode_5.wav",
    "weapons/stinger/fire.wav",
    "weapons/shotgun/shotgun_fire7.wav",
}
local APS_BURST_SND = "sw/vehicles/weapons/m61_loop.wav"
local APS_LOCK_SND  = "buttons/button17.wav"

-- ============================================================
-- SAFE-ENTITY CHECK
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent)                          then return true end
    if ent == aps_owner                          then return true end
    if ent:IsPlayer()                            then return true end
    if ent:IsNPC()                               then return true end
    if ent:IsVehicle()                           then return true end
    local owner = ent:GetOwner()
    if IsValid(owner) and owner == aps_owner     then return true end
    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls]                    then return true end
    return false
end

-- ============================================================
-- THREAT CLASSIFICATION  (radius-agnostic)
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    if APS_INTERCEPT_TARGETS[cls] == true then
        local vel = ent:GetVelocity()
        if vel:Length() < APS_MIN_SPEED then return false end
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end
        return true
    end

    local isProjectileClass =
        string.find(cls, "missile")  ~= nil or
        string.find(cls, "rocket")   ~= nil or
        string.find(cls, "grenade")  ~= nil or
        string.find(cls, "torpedo")  ~= nil

    if isProjectileClass then
        local vel = ent:GetVelocity()
        if vel:Length() < APS_MIN_SPEED then return false end
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end
        return true
    end

    if not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
        local vel = ent:GetVelocity()
        if vel:Length() >= APS_MIN_SPEED then
            local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
            if vel:GetNormalized():Dot(toGekko) >= APS_HEADING_DOT then
                return true
            end
        end
    end

    return false
end

-- ============================================================
-- SCAN helpers
-- ============================================================
local function APS_ScanLaserRadius(self)
    local nearby = ents.FindInSphere(self:GetPos(), APS_LASER_RADIUS)
    for _, ent in ipairs(nearby) do
        if APS_IsThreat(self, ent) then return ent end
    end
    return nil
end

local function APS_ThreatInInterceptRadius(self, ent)
    if not IsValid(ent) then return false end
    return self:GetPos():Distance(ent:GetPos()) <= APS_SCAN_RADIUS
end

-- ============================================================
-- LASER TRACKING BROADCAST  (every scan tick during lock)
-- ============================================================
local function APS_BroadcastLaser(self, threat)
    if not IsValid(threat) then return end
    local attData = self:GetAttachment(3)   -- ATT_MACHINEGUN
    local src = attData and attData.Pos or (self:GetPos() + Vector(0, 0, 180))
    net.Start("GekkoAPSLaser")
        net.WriteVector(src)
        net.WriteVector(threat:GetPos())
    net.Broadcast()
end

-- ============================================================
-- BURST MUZZLE FLASH  (GekkoAPSIntercept)
-- ============================================================
local function APS_FireBurst(self, interceptPos)
    local timerName = "GekkoAPS_burst_" .. self:EntIndex()
    timer.Remove(timerName)
    self:EmitSound(APS_BURST_SND, 90, math.random(97, 108), 1)

    local shotsFired = 0
    timer.Create(timerName, APS_BURST_INTERVAL, APS_BURST_SHOTS, function()
        if not IsValid(self) then timer.Remove(timerName); return end
        shotsFired = shotsFired + 1

        local attIdx  = (shotsFired % 2 == 0) and 9 or 3
        local attData = self:GetAttachment(attIdx)
        local src, dir
        if attData then
            src = attData.Pos
            dir = (interceptPos - src):GetNormalized()
        else
            src = self:GetPos() + Vector(0, 0, 180)
            dir = (interceptPos - src):GetNormalized()
        end

        net.Start("GekkoAPSIntercept")
            net.WriteVector(src)
            net.WriteVector(dir)
            net.WriteVector(interceptPos)
            net.WriteBool(shotsFired == 1)
        net.Broadcast()
    end)
end

-- ============================================================
-- INTERCEPT
-- ============================================================
local function APS_Intercept(self, threat)
    if not IsValid(threat) then return end

    local targetPos = threat:GetPos()

    local ed = EffectData()
    ed:SetOrigin(targetPos)
    ed:SetScale(0.3)
    ed:SetMagnitude(0.3)
    util.Effect("Explosion", ed)

    for _, snd in ipairs(APS_INTERCEPT_SNDS) do
        self:EmitSound(snd, 88, math.random(98, 108), 1)
    end

    if threat.Destroyed       ~= nil then threat.Destroyed       = true end
    if threat.ExplodeCallback ~= nil then threat.ExplodeCallback = nil  end
    SafeRemoveEntity(threat)

    APS_FireBurst(self, targetPos)

    self._apsNextScanT  = CurTime() + APS_REARM_DELAY
    self._apsLockedEnt  = nil
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function ENT:GekkoAPS_Init()
    self._apsNextScanT = 0
    self._apsActive    = true
    self._apsLockedEnt = nil
    print("[GekkoAPS] Initialised on " .. self:EntIndex())
end

function ENT:GekkoAPS_Think()
    if self._gekkoDead         then return end
    if not self._apsActive     then return end
    if CurTime() < (self._apsNextScanT or 0) then return end

    self._apsNextScanT = CurTime() + APS_SCAN_INTERVAL

    -- --------------------------------------------------------
    -- LOCK PHASE: tracking a threat inside laser radius
    -- --------------------------------------------------------
    if IsValid(self._apsLockedEnt) then
        local threat = self._apsLockedEnt

        -- Drop lock if threat is no longer valid or left the laser radius
        if not APS_IsThreat(self, threat) or
           self:GetPos():Distance(threat:GetPos()) > APS_LASER_RADIUS then
            self._apsLockedEnt = nil
            return
        end

        -- Keep broadcasting the tracking beam
        APS_BroadcastLaser(self, threat)

        -- Fire the moment it crosses into the intercept radius
        if APS_ThreatInInterceptRadius(self, threat) then
            self._apsLockedEnt = nil
            APS_Intercept(self, threat)
        end
        return
    end

    -- --------------------------------------------------------
    -- SCAN PHASE: look for a new threat in the laser radius
    -- --------------------------------------------------------
    local threat = APS_ScanLaserRadius(self)
    if threat then
        self._apsLockedEnt = threat
        self:EmitSound(APS_LOCK_SND, 80, math.random(110, 120), 1)
        APS_BroadcastLaser(self, threat)
    end
end
