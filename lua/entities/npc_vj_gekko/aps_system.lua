-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v3.4
--
-- FIXES in this version:
--   1. SOUND LOOP BUG: APS_FireBurst used EmitSound() with a
--      looping .wav (m61_loop.wav). Fixed with CreateSound() +
--      scheduled Stop() after burst duration.
--   2. NET MESSAGE INDEX MISMATCH: GekkoAPSLaser and
--      GekkoAPSIntercept now write net.WriteUInt(entIndex,16)
--      so cl_aps.lua ReadUInt(16) reads the correct value.
--   3. BURST MUZZLE DIRECTION: dir is now computed as
--      (interceptPos - src):GetNormalized() so MuzzleEffect
--      and tracers face the actual interception point.
--      First shot also sends GekkoMuzzleFlash preset 1 (MG).
--
-- INTENTIONAL BEHAVIOUR (not changed):
--   - Laser broadcasts on EVERY scan tick from the moment a
--     threat enters APS_LASER_RADIUS (2000 u), continuously
--     tracking it until interception.
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_LASER_RADIUS   = 2000
local APS_SCAN_RADIUS    = 1200
local APS_MIN_SPEED      = 350
local APS_SCAN_INTERVAL  = 0.05
local APS_REARM_DELAY    = 0.30
local APS_BURST_SHOTS    = 4
local APS_BURST_INTERVAL = 0.040
local APS_BURST_DURATION = APS_BURST_SHOTS * APS_BURST_INTERVAL + 0.05
local APS_HEADING_DOT    = 0.25

-- ============================================================
-- OWNED MUNITION WHITELIST
-- ============================================================
local APS_OWNED_CLASSES = {
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["obj_gekko_rocket"]      = true,
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
    ["obj_vj_rocket"]             = true,
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
    if not IsValid(ent) then return true end
    if ent == aps_owner then return true end
    if ent:IsPlayer()   then return true end
    if ent:IsNPC()      then return true end   -- covers all npc_vj_*
    if ent:IsVehicle()  then return true end
    if ent:IsWeapon()   then return true end

    local parent = ent:GetParent()
    if IsValid(parent) and (parent:IsPlayer() or parent:IsNPC() or parent:IsVehicle()) then
        return true
    end
    local moveParent = ent:GetMoveParent()
    if IsValid(moveParent) and (moveParent:IsPlayer() or moveParent:IsNPC() or moveParent:IsVehicle()) then
        return true
    end

    local owner = ent:GetOwner()
    if IsValid(owner) and owner == aps_owner then return true end

    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls] then return true end

    return false
end

-- ============================================================
-- THREAT CLASSIFICATION
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    local isKnown = APS_INTERCEPT_TARGETS[cls] == true
    local isProjectileClass =
        string.find(cls, "missile")    ~= nil or
        string.find(cls, "rocket")     ~= nil or
        string.find(cls, "grenade")    ~= nil or
        string.find(cls, "torpedo")    ~= nil or
        string.find(cls, "flechette")  ~= nil or
        string.find(cls, "projectile") ~= nil

    if not isKnown and not isProjectileClass then return false end

    local vel = ent:GetVelocity()
    if vel:Length() < APS_MIN_SPEED then return false end
    local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
    if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end

    return true
end

-- ============================================================
-- SCAN HELPERS
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
-- LASER TRACKING BROADCAST
-- Sends the beam from the muzzle attachment to the threat on
-- every scan tick from first detection until interception.
-- FIX: now writes entity index so cl_aps.lua ReadUInt(16) matches.
-- ============================================================
local function APS_BroadcastLaser(self, threat)
    if not IsValid(threat) then return end
    local attData = self:GetAttachment(3)
    local src = attData and attData.Pos or (self:GetPos() + Vector(0, 0, 180))
    net.Start("GekkoAPSLaser")
        net.WriteVector(src)
        net.WriteVector(threat:GetPos())
        net.WriteUInt(self:EntIndex(), 16)   -- FIX: was missing; client reads this
    net.Broadcast()
end

-- ============================================================
-- BURST FIRE
-- FIX 1 (sound): CreateSound() + scheduled Stop().
-- FIX 3 (muzzle dir): dir = (interceptPos - src):GetNormalized()
-- FIX 2 (net index): writes entity index in GekkoAPSIntercept.
-- ============================================================
local function APS_FireBurst(self, interceptPos)
    local timerName = "GekkoAPS_burst_" .. self:EntIndex()
    timer.Remove(timerName)

    -- FIX 1: managed sound object; stop after burst ends
    local burstSnd = CreateSound(self, APS_BURST_SND)
    if burstSnd then
        burstSnd:PlayEx(0.85, math.random(97, 108))
        timer.Simple(APS_BURST_DURATION + 0.05, function()
            if burstSnd then burstSnd:Stop(); burstSnd = nil end
        end)
    end

    local shotsFired = 0
    timer.Create(timerName, APS_BURST_INTERVAL, APS_BURST_SHOTS, function()
        if not IsValid(self) then timer.Remove(timerName); return end
        shotsFired = shotsFired + 1

        local attIdx  = (shotsFired % 2 == 0) and 9 or 3
        local attData = self:GetAttachment(attIdx)
        local src
        if attData then
            src = attData.Pos
        else
            src = self:GetPos() + Vector(0, 0, 180)
        end
        -- FIX 3: direction aimed at the actual intercept position
        local dir = (interceptPos - src):GetNormalized()

        -- FIX 2: write entity index
        net.Start("GekkoAPSIntercept")
            net.WriteVector(src)
            net.WriteVector(dir)
            net.WriteVector(interceptPos)
            net.WriteBool(shotsFired == 1)
            net.WriteUInt(self:EntIndex(), 16)
        net.Broadcast()

        -- First shot: GekkoMuzzleFlash preset 1 (MG) for projected light
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

    self._apsNextScanT = CurTime() + APS_REARM_DELAY
    self._apsLockedEnt = nil
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

    if IsValid(self._apsLockedEnt) then
        local threat = self._apsLockedEnt

        -- Drop lock if threat is gone or has left the outer radius
        if not APS_IsThreat(self, threat) or
           self:GetPos():Distance(threat:GetPos()) > APS_LASER_RADIUS then
            self._apsLockedEnt = nil
            return
        end

        -- Continuously track with laser beam every tick
        APS_BroadcastLaser(self, threat)

        -- Fire when inside intercept radius
        if APS_ThreatInInterceptRadius(self, threat) then
            self._apsLockedEnt = nil
            APS_Intercept(self, threat)
        end
        return
    end

    -- Scan for new threat
    local threat = APS_ScanLaserRadius(self)
    if threat then
        self._apsLockedEnt = threat
        self:EmitSound(APS_LOCK_SND, 80, math.random(110, 120), 1)
        -- Broadcast laser immediately on first detection
        APS_BroadcastLaser(self, threat)
    end
end
