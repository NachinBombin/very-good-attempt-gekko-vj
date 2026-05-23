-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v3.7
--
-- CHANGES in v3.7:
--   WHITELIST HARDENED — now unconditionally guards ALL pillars:
--     * Players are checked FIRST, before anything else.
--     * Any entity stamped with _gekkoOwnedGib = true is immune
--       (set by gib_system.lua on every spawned gib/casing).
--     * prop_physics / prop_dynamic / prop_physics_override kept in
--       APS_OWNED_CLASSES as belt-and-suspenders for shells and any
--       other debris the Gekko throws that isn't explicitly tagged.
--     * All five checks in APS_IsSafeEntity return true BEFORE any
--       pillar (speed, dot, class pattern, blacklist) is evaluated.
--
-- CHANGES in v3.6 (retained):
--   THREAT DETECTION: 4 fully independent pillars.
--     Whitelist wins unconditionally over all of them.
--     ANY single pillar alone is sufficient to flag a threat:
--       1. Exact blacklist match  (APS_INTERCEPT_TARGETS)
--       2. Class-name pattern     (missile / rocket / grenade / etc.)
--       3. Speed alone            (>= APS_MIN_SPEED)
--       4. Heading dot alone      (>= APS_HEADING_DOT, toward Gekko)
--
--   LASER BEHAVIOUR RESTORED (was incorrectly changed in v3.5):
--     Laser broadcasts on every scan tick from the moment a
--     threat enters APS_LASER_RADIUS (2000 u), continuously
--     tracking it until interception. This is intentional.
--
-- Fixes carried from v3.4 (unchanged):
--   1. Sound loop fixed with CreateSound() + scheduled Stop().
--   2. Net entity index written for cl_aps.lua.
--   3. Burst muzzle direction aimed at intercept position.
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
-- Wins over every pillar. Nothing here is ever intercepted.
--
-- prop_physics / prop_dynamic / prop_physics_override are included
-- here as belt-and-suspenders: shells, casings, and any debris
-- the Gekko ejects are all generic physics props. We never want
-- those intercepted regardless of their speed or heading.
-- Gibs additionally receive the _gekkoOwnedGib flag (see gib_system.lua)
-- for the same protection.
-- ============================================================
local APS_OWNED_CLASSES = {
    -- Gekko's own munitions
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["obj_gekko_rocket"]      = true,
    ["sent_orbital_rpg"]      = true,
    ["sent_gekko_bushmaster"] = true,
    -- Grenades / utility
    ["bombin_gas_grenade"]    = true,
    ["ent_gas_stun"]          = true,
    ["ent_flashbang"]         = true,
    -- Generic physics props (gibs, shells, casings, debris)
    ["prop_physics"]          = true,
    ["prop_dynamic"]          = true,
    ["prop_physics_override"] = true,
}

-- ============================================================
-- THREAT TABLE  (pillar 1 -- exact blacklist)
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
-- SAFE-ENTITY CHECK  (whitelist -- wins over EVERY pillar)
--
-- Evaluation order is intentional:
--   1. Invalid entity       -> safe (nothing to intercept)
--   2. The Gekko itself     -> always safe
--   3. Any player           -> always safe (FIRST class check)
--   4. Any NPC              -> always safe
--   5. Any vehicle          -> always safe
--   6. Any weapon           -> always safe
--   7. Gib/casing tag       -> safe (set by gib_system.lua)
--   8. Parent is player/NPC/vehicle -> safe
--   9. MoveParent is player/NPC/vehicle -> safe
--  10. Owner is the Gekko   -> safe (own munitions)
--  11. Class in APS_OWNED_CLASSES -> safe (own munitions + generic props)
--
-- NOTHING proceeds to any threat pillar until ALL of the above
-- return false.  The whitelist is absolute.
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent) then return true end

    -- Hard guards: the Gekko itself and all living entities.
    if ent == aps_owner   then return true end
    if ent:IsPlayer()     then return true end
    if ent:IsNPC()        then return true end
    if ent:IsVehicle()    then return true end
    if ent:IsWeapon()     then return true end

    -- Gib / casing tag: stamped by gib_system.lua on every
    -- prop_physics_override the Gekko spawns as a gib or shell casing.
    if ent._gekkoOwnedGib then return true end

    -- Parent hierarchy guards.
    local parent = ent:GetParent()
    if IsValid(parent) and
       (parent:IsPlayer() or parent:IsNPC() or parent:IsVehicle()) then
        return true
    end
    local moveParent = ent:GetMoveParent()
    if IsValid(moveParent) and
       (moveParent:IsPlayer() or moveParent:IsNPC() or moveParent:IsVehicle()) then
        return true
    end

    -- Owner field guard (covers Gekko's own fired munitions).
    local owner = ent:GetOwner()
    if IsValid(owner) and owner == aps_owner then return true end

    -- Class whitelist (own munitions + all generic physics props).
    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls] then return true end

    return false
end

-- ============================================================
-- THREAT CLASSIFICATION  v3.7
--
-- APS_IsSafeEntity is evaluated FIRST and is absolute.
-- Only entities that pass ALL whitelist checks reach the pillars.
-- Then 4 fully independent pillars, each sufficient alone:
--   1. Exact blacklist match.
--   2. Class-name contains a known projectile keyword.
--   3. Speed alone >= APS_MIN_SPEED.
--   4. Heading dot alone >= APS_HEADING_DOT (moving toward Gekko).
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end

    -- Whitelist is absolute -- checked before every single pillar.
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    -- Pillar 1: exact blacklist.
    if APS_INTERCEPT_TARGETS[cls] == true then return true end

    -- Pillar 2: class-name pattern.
    if  string.find(cls, "missile")    ~= nil or
        string.find(cls, "rocket")     ~= nil or
        string.find(cls, "grenade")    ~= nil or
        string.find(cls, "torpedo")    ~= nil or
        string.find(cls, "flechette")  ~= nil or
        string.find(cls, "projectile") ~= nil
    then
        return true
    end

    local vel = ent:GetVelocity()

    -- Pillar 3: speed alone.
    if vel:Length() >= APS_MIN_SPEED then return true end

    -- Pillar 4: heading dot alone.
    local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
    if vel:GetNormalized():Dot(toGekko) >= APS_HEADING_DOT then return true end

    return false
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
-- Broadcasts on every scan tick from first detection (2000 u)
-- until interception. Wide laser window visually telegraphs the
-- system.
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

-- ============================================================
-- BURST FIRE
-- ============================================================
local function APS_FireBurst(self, interceptPos)
    local timerName = "GekkoAPS_burst_" .. self:EntIndex()
    timer.Remove(timerName)

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

        -- Drop lock if threat is gone or left the outer radius.
        if not APS_IsThreat(self, threat) or
           self:GetPos():Distance(threat:GetPos()) > APS_LASER_RADIUS then
            self._apsLockedEnt = nil
            return
        end

        -- Continuously broadcast laser on every tick (intended).
        APS_BroadcastLaser(self, threat)

        -- Fire when inside intercept radius.
        if APS_ThreatInInterceptRadius(self, threat) then
            self._apsLockedEnt = nil
            APS_Intercept(self, threat)
        end
        return
    end

    -- Scan for new threat.
    local threat = APS_ScanLaserRadius(self)
    if threat then
        self._apsLockedEnt = threat
        self:EmitSound(APS_LOCK_SND, 80, math.random(110, 120), 1)
        APS_BroadcastLaser(self, threat)
    end
end
