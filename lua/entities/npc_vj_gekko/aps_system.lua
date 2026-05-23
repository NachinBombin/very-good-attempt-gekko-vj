-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v4.1
--
-- WHITELIST IS ABSOLUTE AND EVALUATED BEFORE ALL PILLARS.
-- Nothing on the whitelist is ever intercepted regardless of
-- speed, heading, class pattern, or blacklist membership.
--
-- v4.1 fix:
--   CRASH FIX: rawget(ent, "Owner") crashes with
--   "bad argument #1 to 'rawget' (table expected, got userdata)"
--   because GMod entities are userdata, not plain Lua tables.
--   rawget() only works on plain tables. Replaced with ent.Owner
--   which correctly goes through the __index metamethod.
--
-- v4.0 fixes (retained):
--   FIX 1 - viewmodel/predicted_viewmodel added to whitelist.
--   FIX 2 - EntIndex cross-check for Gekko sub-objects on jump.
--   FIX 3 - Owner field check (ent.Owner) alongside GetOwner().
--   FIX 4 - Speed+dot required together (not speed alone).
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
-- OWNED MUNITION + SAFE ENTITY WHITELIST
-- Wins over every pillar unconditionally.
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
    -- Player viewmodel / hands.
    -- ents.FindInSphere returns these. NOT IsPlayer().
    -- Move at player velocity so speed+dot pillar fires on them.
    ["viewmodel"]             = true,
    ["predicted_viewmodel"]   = true,
    -- Extra weapon-related entity classes
    ["weapon_base"]           = true,
    ["weapon_physgun"]        = true,
    ["weapon_physcannon"]     = true,
}

-- ============================================================
-- THREAT TABLE  (Pillar 1 - exact blacklist)
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
-- PARENT-CHAIN WALK HELPER
-- Walks GetParent() and GetMoveParent() up to MAX_DEPTH.
-- Returns true if any ancestor is a player, NPC, or vehicle.
-- ============================================================
local PARENT_WALK_MAX_DEPTH = 8

local function APS_HasLivingAncestor(ent)
    local node, depth

    node  = ent
    depth = 0
    while depth < PARENT_WALK_MAX_DEPTH do
        local p = node:GetParent()
        if not IsValid(p) then break end
        if p:IsPlayer() or p:IsNPC() or p:IsVehicle() then return true end
        node  = p
        depth = depth + 1
    end

    node  = ent
    depth = 0
    while depth < PARENT_WALK_MAX_DEPTH do
        local mp = node:GetMoveParent()
        if not IsValid(mp) then break end
        if mp:IsPlayer() or mp:IsNPC() or mp:IsVehicle() then return true end
        node  = mp
        depth = depth + 1
    end

    return false
end

-- ============================================================
-- SAFE-ENTITY CHECK  (whitelist - wins over EVERY pillar)
--
-- Guards evaluated in order; any true = entity is safe:
--   1.  Invalid entity
--   2.  The Gekko itself (by reference AND EntIndex)
--   3.  IsPlayer()
--   4.  IsNPC()
--   5.  IsVehicle()
--   6.  IsWeapon()
--   7.  _gekkoOwnedGib flag (set by gib_system.lua)
--   8.  Class in APS_OWNED_CLASSES
--   9.  Class prefix "weapon_"
--  10.  Full parent/moveparent chain walk
--  11.  GetOwner() == aps_owner or is player/NPC/vehicle
--  12.  .Owner field == aps_owner or is player/NPC/vehicle
--       (CRASH FIX v4.1: was rawget(ent,"Owner") which crashes
--        because entities are userdata not plain Lua tables.
--        ent.Owner goes through __index correctly.)
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent) then return true end

    if ent == aps_owner then return true end
    if ent:EntIndex() == aps_owner:EntIndex() then return true end

    if ent:IsPlayer()  then return true end
    if ent:IsNPC()     then return true end
    if ent:IsVehicle() then return true end
    if ent:IsWeapon()  then return true end

    if ent._gekkoOwnedGib then return true end

    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls] then return true end
    if string.sub(cls, 1, 7) == "weapon_" then return true end

    if APS_HasLivingAncestor(ent) then return true end

    local ownerMethod = ent:GetOwner()
    if IsValid(ownerMethod) then
        if ownerMethod == aps_owner then return true end
        if ownerMethod:IsPlayer() or ownerMethod:IsNPC() or ownerMethod:IsVehicle() then
            return true
        end
    end

    -- CRASH FIX v4.1: rawget(ent, "Owner") crashes with
    -- "table expected, got userdata". Entities expose fields
    -- via __index metamethod; use ent.Owner directly.
    local ownerField = ent.Owner
    if IsValid(ownerField) then
        if ownerField == aps_owner then return true end
        if ownerField:IsPlayer() or ownerField:IsNPC() or ownerField:IsVehicle() then
            return true
        end
    end

    return false
end

-- ============================================================
-- THREAT CLASSIFICATION
--
-- Whitelist (APS_IsSafeEntity) is absolute - checked first.
-- Only entities that fail every whitelist guard reach pillars.
--
-- Pillars:
--   1. Exact blacklist match          -> threat
--   2. Class-name pattern             -> threat
--   3+4. Speed >= threshold AND
--        heading dot >= threshold     -> threat
--        (both required together to prevent false positives
--        on fast physics props and the jumping Gekko's env)
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end
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

    -- Pillars 3+4: speed AND heading together.
    local vel   = ent:GetVelocity()
    local speed = vel:Length()
    if speed >= APS_MIN_SPEED then
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) >= APS_HEADING_DOT then
            return true
        end
    end

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
-- until interception. Wide laser window is intentional.
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

    -- Final whitelist re-check before removal.
    -- Catches race where entity became safe between lock and fire.
    if APS_IsSafeEntity(self, threat) then
        self._apsLockedEnt = nil
        return
    end

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

        if not APS_IsThreat(self, threat) or
           self:GetPos():Distance(threat:GetPos()) > APS_LASER_RADIUS then
            self._apsLockedEnt = nil
            return
        end

        APS_BroadcastLaser(self, threat)

        if APS_ThreatInInterceptRadius(self, threat) then
            self._apsLockedEnt = nil
            APS_Intercept(self, threat)
        end
        return
    end

    local threat = APS_ScanLaserRadius(self)
    if threat then
        self._apsLockedEnt = threat
        self:EmitSound(APS_LOCK_SND, 80, math.random(110, 120), 1)
        APS_BroadcastLaser(self, threat)
    end
end
