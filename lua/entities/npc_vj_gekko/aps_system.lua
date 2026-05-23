-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v2
--
-- Ported from nphalanx_aps (Current-Phalanx repo).
-- NPC differences vs. player Phalanx:
--   • Always active — no ON/OFF toggle
--   • Laser is OFF at all times (not player-operated)
--     Only lights up momentarily before firing (handled client-side
--     via GekkoAPSIntercept net msg — laser state bit = 1 for 80ms)
--   • Burst muzzle flash fires toward the intercept point via
--     the existing GekkoMuzzleFlash net message (preset 3)
--   • Full whitelist of every Gekko-owned munition class
--   • Gekko itself, other NPCs, fast ally NPCs, and players are
--     NEVER deleted — only hostile projectiles are intercepted
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_SCAN_RADIUS    = 1200    -- sphere radius around Gekko, units
local APS_MIN_SPEED      = 350     -- u/s — projectiles below this are ignored
local APS_SCAN_INTERVAL  = 0.05    -- seconds between threat scans
local APS_REARM_DELAY    = 0.30    -- cooldown between successive intercepts
local APS_BURST_SHOTS    = 4       -- muzzle flash pulses per intercept
local APS_BURST_INTERVAL = 0.040   -- seconds between burst pulses
local APS_HEADING_DOT    = 0.25    -- dot-product floor: threat must face Gekko

-- ============================================================
-- OWNED MUNITION WHITELIST
-- Every class Gekko itself fires is listed here.
-- These are NEVER intercepted regardless of speed or class name.
-- ============================================================
local APS_OWNED_CLASSES = {
    -- Missiles & rockets
    ["npc_vj_gekko_nikita"]   = true,   -- Nikita cruise missile
    ["sent_npc_topmissile"]   = true,   -- top-attack missile
    ["sent_npc_trackmissile"] = true,   -- active-track missile
    ["obj_vj_rocket"]         = true,   -- standard gekko rocket
    ["obj_gekko_rocket"]      = true,   -- alternate rocket entity name
    ["sent_orbital_rpg"]      = true,   -- orbital missile
    -- Bushmaster 25 mm cannon rounds
    ["sent_gekko_bushmaster"] = true,
    -- Grenade launcher payloads
    ["bombin_gas_grenade"]    = true,   -- toxic gas grenade
    ["ent_gas_stun"]          = true,   -- stun/gas grenade
    ["ent_flashbang"]         = true,   -- flash grenade
    -- Shell casings (physics debris — never a threat)
    ["prop_physics"]          = true,
    ["prop_dynamic"]          = true,
}

-- ============================================================
-- GLOBAL THREAT TABLE
-- Mirrors the Phalanx INTERCEPT_TARGETS list plus extras that
-- are relevant to threatening a large armoured NPC.
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
    ["obj_vj_rocket"]             = false,  -- overridden by owned whitelist check first
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
-- INTERCEPT SOUNDS  (same palette as Phalanx)
-- ============================================================
local APS_INTERCEPT_SNDS = {
    "ambient/explosions/explode_4.wav",
    "ambient/explosions/explode_5.wav",
    "weapons/stinger/fire.wav",
    "weapons/shotgun/shotgun_fire7.wav",
}
local APS_BURST_SND = "sw/vehicles/weapons/m61_loop.wav"

-- ============================================================
-- SAFE-ENTITY CHECK
-- Returns true if the entity must NEVER be deleted by the APS.
-- Covers: Gekko itself, all players, all NPCs, fast-moving
-- friendly NPCs (e.g. VJ NPCs fleeing), and VJ base entities.
-- ============================================================
local function APS_IsSafeEntity(aps_owner, ent)
    if not IsValid(ent)             then return true  end
    if ent == aps_owner             then return true  end  -- Gekko itself
    if ent:IsPlayer()               then return true  end  -- players
    if ent:IsNPC()                  then return true  end  -- all NPCs
    if ent:IsVehicle()              then return true  end
    -- owner-set projectiles from Gekko
    local owner = ent:GetOwner()
    if IsValid(owner) and owner == aps_owner then return true end
    -- prop_physics / prop_dynamic are in whitelist; belt-and-suspenders
    local cls = ent:GetClass()
    if APS_OWNED_CLASSES[cls]       then return true  end
    return false
end

-- ============================================================
-- THREAT CLASSIFICATION
-- Returns true if 'ent' is a valid intercept target for 'self'.
-- ============================================================
local function APS_IsThreat(self, ent)
    if not IsValid(ent) then return false end

    -- Never shoot safe entities
    if APS_IsSafeEntity(self, ent) then return false end

    local cls = string.lower(ent:GetClass())

    -- Explicit intercept table hit
    if APS_INTERCEPT_TARGETS[cls] == true then
        -- Heading check: velocity dot toward Gekko
        local vel = ent:GetVelocity()
        local spd = vel:Length()
        if spd < APS_MIN_SPEED then return false end
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end
        return true
    end

    -- Pattern matching (missile / rocket / grenade in class name)
    local isProjectileClass =
        string.find(cls, "missile")  ~= nil or
        string.find(cls, "rocket")   ~= nil or
        string.find(cls, "grenade")  ~= nil or
        string.find(cls, "torpedo")  ~= nil

    if isProjectileClass then
        local vel = ent:GetVelocity()
        local spd = vel:Length()
        if spd < APS_MIN_SPEED then return false end
        local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
        if vel:GetNormalized():Dot(toGekko) < APS_HEADING_DOT then return false end
        return true
    end

    -- High-speed unclassified entity (catch-all – must NOT be NPC/player/vehicle)
    if not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
        local vel = ent:GetVelocity()
        local spd = vel:Length()
        if spd >= APS_MIN_SPEED then
            local toGekko = (self:GetPos() - ent:GetPos()):GetNormalized()
            if vel:GetNormalized():Dot(toGekko) >= APS_HEADING_DOT then
                return true
            end
        end
    end

    return false
end

-- ============================================================
-- SCAN FOR THREAT
-- ============================================================
local function APS_ScanForThreat(self)
    local myPos    = self:GetPos()
    local nearby   = ents.FindInSphere(myPos, APS_SCAN_RADIUS)

    for _, ent in ipairs(nearby) do
        if APS_IsThreat(self, ent) then
            return ent
        end
    end
    return nil
end

-- ============================================================
-- BURST MUZZLE FLASH  (server → client via GekkoAPSIntercept)
-- Fires APS_BURST_SHOTS pulses, each separated by APS_BURST_INTERVAL.
-- Direction is toward the intercept explosion position.
-- Uses GekkoMuzzleFlash preset 3 (Bushmaster — bright, punchy).
-- ============================================================
local function APS_FireBurst(self, interceptPos)
    local timerName = "GekkoAPS_burst_" .. self:EntIndex()
    timer.Remove(timerName)

    -- Brief burst sound
    self:EmitSound(APS_BURST_SND, 90, math.random(97, 108), 1)

    local shotsFired = 0
    timer.Create(timerName, APS_BURST_INTERVAL, APS_BURST_SHOTS, function()
        if not IsValid(self) then
            timer.Remove(timerName)
            return
        end
        shotsFired = shotsFired + 1

        -- Choose a firing attachment: cycle through machine-gun and missile ports
        local attIdx = (shotsFired % 2 == 0) and 9 or 3   -- ATT_MISSILE_L or ATT_MACHINEGUN
        local attData = self:GetAttachment(attIdx)
        local src, dir
        if attData then
            src = attData.Pos
            dir = (interceptPos - src):GetNormalized()
        else
            src = self:GetPos() + Vector(0, 0, 180)
            dir = (interceptPos - src):GetNormalized()
        end

        -- Tell all clients: flash + tracer toward intercept point
        net.Start("GekkoAPSIntercept")
            net.WriteVector(src)
            net.WriteVector(dir)
            net.WriteVector(interceptPos)
            net.WriteBool(shotsFired == 1)   -- firstShot flag: laser briefly visible
        net.Broadcast()
    end)
end

-- ============================================================
-- INTERCEPT
-- ============================================================
local function APS_Intercept(self, threat)
    if not IsValid(threat) then return end

    local targetPos = threat:GetPos()

    -- Explosion at target
    local ed = EffectData()
    ed:SetOrigin(targetPos)
    util.Effect("Explosion", ed)

    -- Intercept sounds
    for _, snd in ipairs(APS_INTERCEPT_SNDS) do
        self:EmitSound(snd, 95, math.random(95, 105), 1)
    end

    -- Screen shake for nearby players
    util.ScreenShake(targetPos, 18, 220, 0.6, 1200)

    -- Nullify callbacks and remove the projectile
    if threat.Destroyed       ~= nil then threat.Destroyed       = true  end
    if threat.ExplodeCallback ~= nil then threat.ExplodeCallback = nil   end
    SafeRemoveEntity(threat)

    -- Fire the burst muzzle flash toward the intercept point
    APS_FireBurst(self, targetPos)

    -- Arm cooldown
    self._apsNextScanT = CurTime() + APS_REARM_DELAY
end

-- ============================================================
-- PUBLIC API — called from ENT:Init() and ENT:OnThink()
-- ============================================================
function ENT:GekkoAPS_Init()
    self._apsNextScanT = 0
    self._apsActive    = true
    print("[GekkoAPS] Initialised on " .. self:EntIndex())
end

function ENT:GekkoAPS_Think()
    if self._gekkoDead              then return end
    if not self._apsActive          then return end
    if CurTime() < (self._apsNextScanT or 0) then return end

    self._apsNextScanT = CurTime() + APS_SCAN_INTERVAL

    local threat = APS_ScanForThreat(self)
    if threat then
        APS_Intercept(self, threat)
    end
end