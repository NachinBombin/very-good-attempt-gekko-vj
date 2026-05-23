-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v4.5
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
--      EXCLUDING prop_physics / prop_physics_override / prop_dynamic
--      (those classes are never dangerous by speed alone; they are
--       bullet casings, loose debris, and similar physics props).
--   4. Heading dot alone      (>= APS_HEADING_DOT, toward Gekko)
--      + minimum speed gate   (>= APS_HEADING_MIN_SPEED)
--      Slow-moving gibs that happen to be drifting toward the Gekko
--      will NOT trigger this pillar unless they are also fast.
--
-- Pillars are independent. Each fires on its own.
-- No pillar was merged or removed; they were only refined.
--
-- ── v4.5 CHANGES (surgical fixes, no pillar removed) ────────
--
-- BUG FIX — Guard 11 / Guard 12 ("owner is any NPC/player = safe"):
--   The old code returned safe=true whenever GetOwner() or .Owner
--   was ANY player or NPC.  This silently whitelisted every grenade,
--   rocket, and projectile launched by an enemy NPC because their
--   GetOwner() pointed at that NPC.  The guards now only mark an
--   entity safe when owner == the Gekko itself.  Actual player,
--   NPC, vehicle, and weapon entities are still exempt via the
--   unchanged Guards 3-6, so nothing is lost on that side.
--
-- BUG FIX — Pillar 3 (speed alone):
--   prop_physics, prop_physics_override, and prop_dynamic entities
--   are now excluded from Pillar 3.  Shell casings from enemy
--   weapons (and any other loose physics prop) happen to eject at
--   350-700 u/s, which is squarely inside the old speed window.
--   Those classes are never dedicated weapon projectiles; they must
--   be explicitly blacklisted (Pillar 1) or match a name pattern
--   above the pattern speed floor (Pillar 2) to be intercepted.
--
-- BUG FIX — Pillar 4 (heading dot alone):
--   A minimum speed floor (APS_HEADING_MIN_SPEED) was added.
--   Gib pieces and debris that scatter in every direction will
--   sometimes randomly point toward the Gekko at low velocity.
--   Those false positives are now suppressed.
--
-- BUG FIX — Pillar 2 (class-name pattern):
--   A minimum speed floor (APS_PATTERN_MIN_SPEED) was added.
--   A static or barely-moving entity whose class name contains
--   "grenade" or "rocket" (e.g. a placed satchel, a dud) will not
--   trigger the APS just from the name match alone.
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_LASER_RADIUS        = 2000
local APS_SCAN_RADIUS         = 1200
local APS_MIN_SPEED           = 350   -- Pillar 3: speed-only threshold
local APS_PATTERN_MIN_SPEED   = 80    -- Pillar 2: name-pattern requires at least this speed
local APS_HEADING_MIN_SPEED   = 180   -- Pillar 4: heading-dot requires at least this speed
local APS_SCAN_INTERVAL       = 0.05
local APS_REARM_DELAY         = 0.30
local APS_BURST_SHOTS         = 4
local APS_BURST_INTERVAL      = 0.040
local APS_BURST_DURATION      = APS_BURST_SHOTS * APS_BURST_INTERVAL + 0.05
local APS_HEADING_DOT         = 0.25

-- ============================================================
-- PHYSICS PROP CLASSES EXCLUDED FROM PILLAR 3
-- These are NEVER intercepted by speed alone.
-- They can still be intercepted via Pillar 1 (explicit blacklist)
-- or Pillar 2 (name pattern + speed floor).
-- ============================================================
local APS_PHYSICS_PROP_CLASSES = {
    ["prop_physics"]          = true,
    ["prop_physics_override"] = true,
    ["prop_dynamic"]          = true,
    ["prop_ragdoll"]          = true,
}

-- ============================================================
-- OWNED MUNITION + SAFE ENTITY WHITELIST
-- Wins unconditionally over all pillars.
--
-- NOTE: prop_physics, prop_physics_override, prop_dynamic are
-- intentionally NOT listed here. Those classes were blanket-
-- whitelisting physics grenades and causing zero detections.
-- They are instead excluded only from Pillar 3 (see above).
-- Gibs: protected by _gekkoOwnedGib flag (gib_system.lua).
-- Shell casings: protected by _gekkoOwnedGib flag (init.lua).
-- ============================================================
local APS_OWNED_CLASSES = {
    -- Gekko's own munitions
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["obj_gekko_rocket"]      = true,
    ["sent_orbital_rpg"]      = true,
    ["sent_gekko_bushmaster"] = true,
    -- Grenades launched by Gekko
    ["bombin_gas_grenade"]    = true,
    ["ent_gas_stun"]          = true,
    ["ent_flashbang"]         = true,
    -- Player first-person arm/hand models.
    -- ents.FindInSphere returns these; they are NOT IsPlayer(),
    -- NOT IsNPC(), NOT IsWeapon(). They move at player speed so
    -- without this entry Pillar 3 fires on them and permanently
    -- deletes the player's hands via SafeRemoveEntity.
    ["viewmodel"]             = true,
    ["predicted_viewmodel"]   = true,
}

-- ============================================================
-- THREAT TABLE  (Pillar 1 -- exact blacklist)
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
-- Walks GetParent() and GetMoveParent() up to MAX_DEPTH levels.
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
-- SAFE-ENTITY CHECK  (whitelist -- wins over EVERY pillar)
--
--  1.  Invalid entity
--  2.  The Gekko itself (by reference AND by EntIndex)
--  3.  IsPlayer()
--  4.  IsNPC()
--  5.  IsVehicle()
--  6.  IsWeapon()
--  7.  _gekkoOwnedGib flag (stamped by gib_system.lua and
--      SpawnCartridge in init.lua)
--  8.  Class in APS_OWNED_CLASSES
--  9.  Class prefix "weapon_"
-- 10.  Full parent/moveparent chain walk (APS_HasLivingAncestor)
-- 11.  GetOwner() == aps_owner  (Gekko's OWN projectiles only)
-- 12.  .Owner field == aps_owner (Gekko's OWN projectiles only)
--
-- !! v4.5 change: Guards 11 and 12 no longer whitelist entities
--    that are owned by ANY player or NPC.  The old broad check
--    (ownerMethod:IsPlayer() or ownerMethod:IsNPC()) was silently
--    exempting every grenade and rocket that an enemy NPC fired
--    because those projectiles report their launcher as GetOwner().
--    Guards 3-6 already handle actual player/NPC/vehicle entities
--    themselves, so nothing legitimate is lost by this removal.
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent) then return true end

    -- Guard 2: Gekko itself
    if ent == aps_owner then return true end
    if ent:EntIndex() == aps_owner:EntIndex() then return true end

    -- Guard 3-6: living / holdable types
    if ent:IsPlayer()  then return true end
    if ent:IsNPC()     then return true end
    if ent:IsVehicle() then return true end
    if ent:IsWeapon()  then return true end

    -- Guard 7: gib/casing ownership tag
    if ent._gekkoOwnedGib then return true end

    -- Guard 8-9: class whitelist and weapon_ prefix
    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls] then return true end
    if string.sub(cls, 1, 7) == "weapon_" then return true end

    -- Guard 10: full parent-chain walk
    if APS_HasLivingAncestor(ent) then return true end

    -- Guard 11: engine owner method — only exempt Gekko's own munitions.
    -- (v4.5: removed the IsPlayer()/IsNPC()/IsVehicle() broad exemption
    -- that was whitelisting enemy-launched grenades and rockets.)
    local ownerMethod = ent:GetOwner()
    if IsValid(ownerMethod) then
        if ownerMethod == aps_owner then return true end
    end

    -- Guard 12: raw .Owner field — same narrowing as Guard 11.
    local ownerField = ent.Owner
    if IsValid(ownerField) then
        if ownerField == aps_owner then return true end
    end

    return false
end

-- ============================================================
-- THREAT CLASSIFICATION
--
-- APS_IsSafeEntity is absolute -- checked before every pillar.
-- 4 fully independent pillars. ANY single one alone is
-- sufficient to flag a threat, subject to the per-pillar
-- refinements documented at the top of this file.
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    -- Pillar 1: exact blacklist — no additional gate.
    if APS_INTERCEPT_TARGETS[cls] == true then return true end

    -- Pillar 2: class-name pattern + minimum speed gate.
    -- A static or barely-moving entity matching a weapon keyword
    -- (placed satchel, dud grenade on the floor) must not fire the
    -- APS from the name alone.  Require at least APS_PATTERN_MIN_SPEED.
    if  string.find(cls, "missile")    ~= nil or
        string.find(cls, "rocket")     ~= nil or
        string.find(cls, "grenade")    ~= nil or
        string.find(cls, "torpedo")    ~= nil or
        string.find(cls, "flechette")  ~= nil or
        string.find(cls, "projectile") ~= nil
    then
        if ent:GetVelocity():Length() >= APS_PATTERN_MIN_SPEED then
            return true
        end
        -- Below the speed floor: still evaluated by Pillars 3 & 4.
    end

    local vel    = ent:GetVelocity()
    local speed  = vel:Length()

    -- Pillar 3: speed alone >= APS_MIN_SPEED.
    -- EXCLUDED: prop_physics / prop_physics_override / prop_dynamic / prop_ragdoll.
    -- Those are physical simulation objects (shell casings, loose debris,
    -- collision props) that routinely reach 350-700 u/s after being struck.
    -- They are NEVER dedicated weapon projectiles.  If one is a real threat
    -- it must be named in the Pillar 1 blacklist.
    if speed >= APS_MIN_SPEED then
        if not APS_PHYSICS_PROP_CLASSES[cls] then
            return true
        end
    end

    -- Pillar 4: heading dot alone >= APS_HEADING_DOT toward the Gekko,
    -- AND minimum speed >= APS_HEADING_MIN_SPEED.
    -- Slow gib pieces that scatter in all directions will occasionally
    -- point toward the Gekko by chance.  The speed floor eliminates them.
    if speed >= APS_HEADING_MIN_SPEED then
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
