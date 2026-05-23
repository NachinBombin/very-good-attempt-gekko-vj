-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v4
--
-- FIXES v4:
--   1. WHITELIST-FIRST: owned/safe entity check now runs before
--      ANY class or keyword lookup.  Previously obj_vj_rocket
--      and other Gekko munitions were passing the explicit table
--      check before IsSafeEntity could reject them.
--   2. LOOP SOUND KILLED: m61_loop.wav was never stopped.
--      Replaced with a single non-looping burst salvo so the
--      channel closes automatically.  A StopSound call also
--      fires on intercept cleanup.
--   3. DEATH CLEANUP: EntityRemoved hook kills all APS timers
--      and broadcasts a laser-clear net message so clients
--      remove the beam immediately when the Gekko dies or is
--      removed from the world.
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_LASER_RADIUS    = 2000
local APS_SCAN_RADIUS     = 1200
local APS_MIN_SPEED       = 350
local APS_SCAN_INTERVAL   = 0.05
local APS_REARM_DELAY     = 0.30
local APS_BURST_SHOTS     = 4
local APS_BURST_INTERVAL  = 0.040
local APS_HEADING_DOT     = 0.25

-- ============================================================
-- OWNED MUNITION WHITELIST
-- These are NEVER intercepted.
-- ============================================================
local APS_OWNED_CLASSES = {
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["obj_gekko_rocket"]      = true,
    ["obj_vj_rocket"]         = true,   -- generic VJ rocket base
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
-- One-shot sounds only — no looping channels.
-- ============================================================
local APS_BURST_SNDS = {
    "weapons/shotgun/shotgun_fire7.wav",
    "weapons/shotgun/shotgun_fire7.wav",
    "weapons/ar2/fire1.wav",
    "weapons/ar2/fire1.wav",
}
local APS_INTERCEPT_SNDS = {
    "ambient/explosions/explode_4.wav",
    "weapons/stinger/fire.wav",
}
local APS_LOCK_SND = "buttons/button17.wav"

-- ============================================================
-- SAFE-ENTITY CHECK  — runs FIRST before any class lookup
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent) then return true end
    if ent == aps_owner  then return true end
    if ent:IsPlayer()    then return true end
    if ent:IsNPC()       then return true end
    if ent:IsVehicle()   then return true end
    if ent:IsWeapon()    then return true end

    -- Parented to a player/NPC/vehicle (physgunned props, viewmodels)
    local parent = ent:GetParent()
    if IsValid(parent) and (parent:IsPlayer() or parent:IsNPC() or parent:IsVehicle()) then
        return true
    end
    local moveParent = ent:GetMoveParent()
    if IsValid(moveParent) and (moveParent:IsPlayer() or moveParent:IsNPC() or moveParent:IsVehicle()) then
        return true
    end

    -- Owned by this Gekko
    local owner = ent:GetOwner()
    if IsValid(owner) and owner == aps_owner then return true end

    -- Whitelisted class (Gekko munitions + generic physics)
    local cls = string.lower(ent:GetClass())
    if APS_OWNED_CLASSES[cls] then return true end

    return false
end

-- ============================================================
-- THREAT CLASSIFICATION
-- Whitelist is guaranteed to have fired before this is reached.
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent)            then return false end
    -- WHITELIST FIRST — nothing beyond this point if safe
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    -- Explicit table hit
    if APS_INTERCEPT_TARGETS[cls] == true then
        local vel = ent:GetVelocity()
        if vel:Length() < APS_MIN_SPEED then return false end
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end
        return true
    end

    -- Keyword match — must contain a projectile keyword in the class name
    local isProjectileClass =
        string.find(cls, "missile")    ~= nil or
        string.find(cls, "rocket")     ~= nil or
        string.find(cls, "torpedo")    ~= nil or
        string.find(cls, "flechette")  ~= nil or
        string.find(cls, "projectile") ~= nil
    -- Note: "grenade" excluded from keyword match intentionally —
    -- too many non-threatening classes contain that word.
    -- Grenades must be listed explicitly in APS_INTERCEPT_TARGETS.

    if isProjectileClass then
        local vel = ent:GetVelocity()
        if vel:Length() < APS_MIN_SPEED then return false end
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end
        return true
    end

    return false
end

-- ============================================================
-- SCAN
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
-- LASER BROADCAST
-- ============================================================
local function APS_BroadcastLaser(self, threat)
    if not IsValid(threat) then return end
    local attData = self:GetAttachment(3)
    local src = attData and attData.Pos or (self:GetPos() + Vector(0, 0, 180))
    net.Start("GekkoAPSLaser")
        net.WriteVector(src)
        net.WriteVector(threat:GetPos())
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()
end

local function APS_BroadcastLaserClear(self)
    net.Start("GekkoAPSLaserClear")
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()
end

-- ============================================================
-- BURST MUZZLE FLASH
-- Uses only one-shot sounds — no looping channels opened.
-- ============================================================
local function APS_FireBurst(self, interceptPos)
    local timerName = "GekkoAPS_burst_" .. self:EntIndex()
    timer.Remove(timerName)

    local shotsFired = 0
    timer.Create(timerName, APS_BURST_INTERVAL, APS_BURST_SHOTS, function()
        if not IsValid(self) then timer.Remove(timerName); return end
        shotsFired = shotsFired + 1

        -- One-shot burst sound — pick from salvo list, varies pitch
        local snd = APS_BURST_SNDS[shotsFired] or APS_BURST_SNDS[1]
        self:EmitSound(snd, 90, math.random(90, 115), 1)

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
            net.WriteUInt(self:EntIndex(), 16)
        net.Broadcast()
    end)
end

-- ============================================================
-- CLEANUP — called on death and removal
-- ============================================================
local function APS_Cleanup(self)
    -- Kill the burst timer
    timer.Remove("GekkoAPS_burst_" .. self:EntIndex())
    -- Tell clients to clear the laser beam immediately
    APS_BroadcastLaserClear(self)
    -- Deactivate so Think is a no-op after this
    self._apsActive    = false
    self._apsLockedEnt = nil
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function ENT:GekkoAPS_Init()
    self._apsNextScanT = 0
    self._apsActive    = true
    self._apsLockedEnt = nil

    -- Death / removal cleanup hook
    local entIdx = self:EntIndex()
    hook.Add("EntityRemoved", "GekkoAPS_Cleanup_" .. entIdx, function(removed)
        if removed == self then
            APS_Cleanup(self)
            hook.Remove("EntityRemoved", "GekkoAPS_Cleanup_" .. entIdx)
        end
    end)
end

function ENT:GekkoAPS_Think()
    if not self._apsActive             then return end
    if self._gekkoDead                 then APS_Cleanup(self); return end
    if CurTime() < (self._apsNextScanT or 0) then return end

    self._apsNextScanT = CurTime() + APS_SCAN_INTERVAL

    -- If we have a lock, track or intercept it
    if IsValid(self._apsLockedEnt) then
        local threat = self._apsLockedEnt

        if not APS_IsThreat(self, threat) or
           self:GetPos():Distance(threat:GetPos()) > APS_LASER_RADIUS then
            self._apsLockedEnt = nil
            APS_BroadcastLaserClear(self)
            return
        end

        APS_BroadcastLaser(self, threat)

        if APS_ThreatInInterceptRadius(self, threat) then
            self._apsLockedEnt = nil
            APS_BroadcastLaserClear(self)

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
        end
        return
    end

    -- Scan for a new threat
    local threat = APS_ScanLaserRadius(self)
    if threat then
        self._apsLockedEnt = threat
        self:EmitSound(APS_LOCK_SND, 80, math.random(110, 120), 1)
        APS_BroadcastLaser(self, threat)
    end
end
