-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v4.0
--
-- WHITELIST IS ABSOLUTE AND EVALUATED BEFORE ALL PILLARS.
-- Nothing on the whitelist is ever intercepted regardless of
-- speed, heading, class pattern, or blacklist membership.
--
-- v4.0 critical fixes:
--
--   FIX 1 — Player hands/viewmodel deletion
--     ents.FindInSphere returns 'viewmodel' and
--     'predicted_viewmodel' entities (the player's arm/hand
--     model). These are NOT IsPlayer(), NOT IsNPC(), NOT
--     IsWeapon(). Previous whitelist did not catch them.
--     Pillar 3 (speed) fired on them when the player ran,
--     SafeRemoveEntity deleted them, player lost hands.
--     Fix: 'viewmodel' and 'predicted_viewmodel' added to
--     APS_OWNED_CLASSES. Additionally, APS_IsSafeEntity now
--     walks the FULL parent chain — not just one level — so
--     any entity parented to a player/NPC/vehicle at ANY
--     depth is unconditionally safe.
--
--   FIX 2 — Gekko self-intercept while jumping
--     jump_system sets MOVETYPE_FLYGRAVITY on the Gekko.
--     While airborne, ents.FindInSphere can return physics
--     sub-objects and move-parent shadow entities that share
--     the Gekko's position but are distinct Lua objects, so
--     ent == aps_owner fails. Added EntIndex cross-check and
--     a full MoveParent walk to catch all of these.
--
--   FIX 3 — Owner set via field vs method
--     Several spawners set  ent.Owner = gekko  (field) instead
--     of  ent:SetOwner(gekko)  (method). The old guard only
--     called ent:GetOwner(). Both paths are now checked.
--
--   FIX 4 — Pillar 3 (speed alone) tightened
--     Speed alone is no longer sufficient to intercept an
--     entity that has no explicit blacklist or pattern match.
--     A high-speed entity now requires BOTH speed >= threshold
--     AND heading dot >= threshold to be intercepted via the
--     speed/dot path. Explicit blacklist (Pillar 1) and class
--     pattern (Pillar 2) still fire immediately on their own.
--
-- v3.7 retained behaviour:
--   * Whitelist wins unconditionally over all pillars.
--   * Laser broadcasts on every scan tick from first detection.
--   * _gekkoOwnedGib tag checked (set by gib_system.lua).
--   * prop_physics / prop_dynamic / prop_physics_override in
--     APS_OWNED_CLASSES as belt-and-suspenders.
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
--
-- Anything in this table is NEVER intercepted, regardless of
-- speed, heading, class pattern, or blacklist membership.
--
-- KEY ADDITIONS in v4.0:
--   viewmodel / predicted_viewmodel  — player hand/arm models.
--     ents.FindInSphere returns these. They move with the player
--     at full running speed. Not IsPlayer, not IsNPC, not
--     IsWeapon — they were silently deleted by Pillar 3 before
--     this fix.
--   weapon_* prefix is handled by IsWeapon() in APS_IsSafeEntity
--     but we keep weapon_base here as an extra guard.
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
    -- ── FIX 1: player viewmodel / hands ─────────────────────
    -- These are the player's first-person arm/hand models.
    -- ents.FindInSphere returns them. They are NOT IsPlayer().
    -- They move at player velocity => speed pillar fires.
    -- SafeRemoveEntity on them destroys the player's viewmodel
    -- permanently for the remainder of the round.
    ["viewmodel"]             = true,
    ["predicted_viewmodel"]   = true,
    -- Extra weapon-related entity classes
    ["weapon_base"]           = true,
    ["weapon_physgun"]        = true,
    ["weapon_physcannon"]     = true,
}

-- ============================================================
-- THREAT TABLE  (Pillar 1 — exact blacklist)
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
--
-- Walks the full GetParent() chain up to MAX_DEPTH levels.
-- Returns true if any ancestor is a player, NPC, or vehicle.
-- This catches viewmodels, weapon world-models, prop_physics
-- children attached to players, and any other entity that is
-- parented at any depth to a living entity.
-- ============================================================
local PARENT_WALK_MAX_DEPTH = 8

local function APS_HasLivingAncestor(ent)
    local node  = ent
    local depth = 0
    while depth < PARENT_WALK_MAX_DEPTH do
        local p = node:GetParent()
        if not IsValid(p) then break end
        if p:IsPlayer() or p:IsNPC() or p:IsVehicle() then
            return true
        end
        node  = p
        depth = depth + 1
    end
    -- Also walk MoveParent chain
    node  = ent
    depth = 0
    while depth < PARENT_WALK_MAX_DEPTH do
        local mp = node:GetMoveParent()
        if not IsValid(mp) then break end
        if mp:IsPlayer() or mp:IsNPC() or mp:IsVehicle() then
            return true
        end
        node  = mp
        depth = depth + 1
    end
    return false
end

-- ============================================================
-- SAFE-ENTITY CHECK  (whitelist — wins over EVERY pillar)
--
-- Evaluation order (all must return false before pillars run):
--   1.  Invalid entity                          -> safe
--   2.  The Gekko itself (== and EntIndex)      -> safe  [FIX 2]
--   3.  IsPlayer()                              -> safe
--   4.  IsNPC()                                 -> safe
--   5.  IsVehicle()                             -> safe
--   6.  IsWeapon()                              -> safe
--   7.  _gekkoOwnedGib flag                     -> safe
--   8.  Class in APS_OWNED_CLASSES              -> safe  [FIX 1 key]
--   9.  Class starts with "weapon_"             -> safe
--  10.  Full parent-chain walk (any depth)      -> safe  [FIX 1 key]
--  11.  Owner == aps_owner (method)             -> safe
--  12.  .Owner field == aps_owner (field)       -> safe  [FIX 3]
--  13.  Owner is any player/NPC/vehicle         -> safe
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent) then return true end

    -- Guard 1-2: Gekko itself, by reference AND by entity index
    -- (physics sub-objects during jump share the index check)
    if ent == aps_owner then return true end
    if ent:EntIndex() == aps_owner:EntIndex() then return true end

    -- Guard 3-6: living / holdable entity types
    if ent:IsPlayer()  then return true end
    if ent:IsNPC()     then return true end
    if ent:IsVehicle() then return true end
    if ent:IsWeapon()  then return true end

    -- Guard 7: gib/casing tag set by gib_system.lua
    if ent._gekkoOwnedGib then return true end

    -- Guard 8: class whitelist
    -- Includes 'viewmodel' and 'predicted_viewmodel' (FIX 1).
    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls] then return true end

    -- Guard 9: any weapon_ class not individually listed
    if string.sub(cls, 1, 7) == "weapon_" then return true end

    -- Guard 10: full parent-chain walk (FIX 1 — viewmodels are
    -- parented to players; this is the depth-walk fallback that
    -- catches anything parented to a living entity at any depth).
    if APS_HasLivingAncestor(ent) then return true end

    -- Guard 11-12: owner checks — method AND field (FIX 3)
    -- Several Gekko spawners use  ent.Owner = gekko  (field)
    -- rather than  ent:SetOwner(gekko)  (method).
    local ownerMethod = ent:GetOwner()
    if IsValid(ownerMethod) then
        if ownerMethod == aps_owner then return true end
        if ownerMethod:IsPlayer() or ownerMethod:IsNPC() or ownerMethod:IsVehicle() then
            return true
        end
    end
    local ownerField = rawget(ent, "Owner")
    if IsValid(ownerField) then
        if ownerField == aps_owner then return true end
        if ownerField:IsPlayer() or ownerField:IsNPC() or ownerField:IsVehicle() then
            return true
        end
    end

    return false
end

-- ============================================================
-- THREAT CLASSIFICATION  v4.0
--
-- APS_IsSafeEntity is absolute — evaluated first, before every
-- pillar. Only entities that fail ALL whitelist checks reach
-- the pillars below.
--
-- Pillars:
--   1. Exact blacklist match          (immediate intercept)
--   2. Class-name pattern             (immediate intercept)
--   3+4. Speed AND heading combined   (FIX 4 — speed alone is
--         no longer sufficient; both thresholds must be met to
--         prevent interception of stray fast physics props).
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end

    -- Whitelist is absolute.
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    -- Pillar 1: exact blacklist.
    if APS_INTERCEPT_TARGETS[cls] == true then return true end

    -- Pillar 2: class-name pattern (missile / rocket / grenade / etc.)
    if  string.find(cls, "missile")    ~= nil or
        string.find(cls, "rocket")     ~= nil or
        string.find(cls, "grenade")    ~= nil or
        string.find(cls, "torpedo")    ~= nil or
        string.find(cls, "flechette")  ~= nil or
        string.find(cls, "projectile") ~= nil
    then
        return true
    end

    -- Pillars 3+4: speed AND heading (FIX 4)
    -- Previously speed alone (Pillar 3) was sufficient, which caused
    -- any fast-moving entity — including the player's running viewmodel,
    -- stray physics props, and the Gekko's own launched gibs that
    -- somehow missed the tag — to be intercepted and deleted.
    -- Now BOTH thresholds must be satisfied simultaneously.
    local vel = ent:GetVelocity()
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
-- until interception.
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

    -- Final whitelist re-check immediately before removal.
    -- Covers the rare race where an entity became safe between
    -- lock acquisition and intercept execution.
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

        -- Drop lock if threat became safe or left outer radius.
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
