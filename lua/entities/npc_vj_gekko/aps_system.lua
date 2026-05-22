-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM (APS)
--
-- Always-on threat-scan that detects and intercepts hostile
-- high-speed projectiles before they hit the Gekko.
--
-- Design:
--  • Server scans nearby entities every APS_TICK seconds.
--  • Whitelisted classes (Gekko's own weapons) are never shot down.
--  • Gekko itself and friendly fast-movers are guarded from deletion.
--  • Laser draw: DISABLED (NPC, not a player-operated CIWS).
--  • Muzzle flash burst IS played toward the interception direction,
--    reusing the existing GekkoMuzzleFlash net message (preset 1 = MG).
--    A 3-shot staggered burst is sent to mimic a real CIWS volley.
--  • Interception explosion + sound plays at the target position.
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_SCAN_RADIUS       = 1200   -- units - radius to search for threats
local APS_MIN_SPEED         = 350    -- units/s - minimum projectile speed to engage
local APS_TICK              = 0.12   -- seconds between scan cycles
local APS_REARM_DELAY       = 0.25   -- seconds between successive intercepts
local APS_BURST_SHOTS       = 3      -- muzzle flash bursts per intercept
local APS_BURST_INTERVAL    = 0.045  -- seconds between burst shots
local APS_EXPLODE_RADIUS    = 120    -- blast radius of interception explosion
local APS_EXPLODE_DAMAGE    = 0      -- interception itself deals no damage (APS removes projectile)

-- ============================================================
-- CLASS WHITELIST  (Gekko's own munitions - never intercepted)
-- ============================================================
local APS_WHITELIST = {
    -- Gekko own projectiles
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["sent_gekko_bushmaster"] = true,
    ["obj_vj_rocket"]         = true,
    ["sent_orbital_rpg"]      = true,
    -- Grenade launcher grenades (Gekko-fired)
    ["bombin_gas_grenade"]    = true,
    ["ent_gas_stun"]          = true,
    ["ent_flashbang"]         = true,
    -- Generic safe classes
    ["prop_physics"]          = true,   -- shell casings etc.
    ["prop_dynamic"]          = true,
    ["npc_vj_gekko"]          = true,   -- the gekko itself
}

-- ============================================================
-- OWNER-CHECK HELPER
-- Returns true when 'proj' was fired by 'gekko' or by another
-- entity that belongs to the same faction (CLASS_COMBINE).
-- ============================================================
local function IsOwnedByGekko(proj, gekko)
    -- Direct owner match
    local owner = proj:GetOwner()
    if IsValid(owner) then
        if owner == gekko then return true end
        -- Same NPC class (another Gekko in the world)
        if owner:IsNPC() and owner:GetClass() == "npc_vj_gekko" then return true end
    end
    -- Creator stored in other common keys
    if proj.Owner and proj.Owner == gekko then return true end
    if proj.CreatedBy and proj.CreatedBy == gekko then return true end
    return false
end

-- ============================================================
-- IS THREAT?
-- Fast pre-filter before we do the expensive speed check.
-- ============================================================
local function IsThreat(proj, gekko)
    if not IsValid(proj) then return false end
    if proj == gekko       then return false end  -- never intercept self

    local cls = proj:GetClass()

    -- Whitelist by class
    if APS_WHITELIST[cls] then return false end

    -- Protect Gekko's own grenades by owner tag
    if IsOwnedByGekko(proj, gekko) then return false end

    -- Guard against NPC / player deletion
    if proj:IsNPC() or proj:IsPlayer() then return false end

    -- Must have physics (projectile) or be moving entity
    local phys = proj:GetPhysicsObject()
    if IsValid(phys) then
        local speed = phys:GetVelocity():Length()
        if speed < APS_MIN_SPEED then return false end
    else
        -- Some scripted projectiles move via velocity without a PhysObj
        local vel = proj:GetVelocity()
        if vel:Length() < APS_MIN_SPEED then return false end
    end

    return true
end

-- ============================================================
-- INTERCEPTION EFFECTS
-- Server-side explosion + net message for muzzle burst toward
-- the interception point.
-- ============================================================
local function DoInterceptExplosion(pos)
    local e = EffectData()
    e:SetOrigin(pos)
    e:SetMagnitude(1)
    e:SetScale(1)
    e:SetRadius(APS_EXPLODE_RADIUS)
    util.Effect("Explosion", e)
 end

-- Sends a tight burst of muzzle flashes from the Gekko's body
-- toward the interception position, using the existing MuzzleFlash
-- net message infrastructure so cl_init / muzzleflash_system.lua
-- handles the projected-light rendering automatically.
local function SendInterceptMuzzleBurst(gekko, interceptPos)
    for i = 0, APS_BURST_SHOTS - 1 do
        timer.Simple(i * APS_BURST_INTERVAL, function()
            if not IsValid(gekko) then return end

            -- Fire position: use machinegun attachment (att 3) if available,
            -- otherwise fall back to body centre.
            local attData = gekko:GetAttachment(3)   -- ATT_MACHINEGUN
            local src = attData and attData.Pos or
                        (gekko:GetPos() + Vector(0, 0, 100))

            -- Direction toward intercept point
            local dir = (interceptPos - src):GetNormalized()
            if dir:LengthSqr() < 0.01 then dir = gekko:GetForward() end

            -- Use preset 1 (MG rapid flash) - small, fast, many
            net.Start("GekkoMuzzleFlash")
                net.WriteVector(src)
                net.WriteVector(dir)
                net.WriteUInt(1, 3)
            net.Broadcast()

            -- Also play a quiet burst fire sound at the gekko position
            gekko:EmitSound("npc/metropolice/metropolice_shot1.wav", 80, math.random(110, 130), 0.6)
        end)
    end
end

-- ============================================================
-- INIT  (called from ENT:Initialize in init.lua)
-- ============================================================
function GekkoAPS_Init(ent)
    ent._apsNextScan  = 0
    ent._apsRearmTime = 0
    ent._apsIntercepted = {}  -- weak table of recently intercepted entity IDs
end

-- ============================================================
-- THINK  (called every frame from ENT:Think in init.lua)
-- ============================================================
function GekkoAPS_Think(ent, now)
    if not IsValid(ent) then return end

    if now < ent._apsNextScan  then return end
    if now < ent._apsRearmTime then return end

    ent._apsNextScan = now + APS_TICK

    local origin = ent:GetPos() + Vector(0, 0, 80)

    -- Sphere search for candidates
    local candidates = ents.FindInSphere(origin, APS_SCAN_RADIUS)

    for _, proj in ipairs(candidates) do
        if not IsThreat(proj, ent) then continue end

        -- Additional heading check: must be travelling roughly toward Gekko
        local phys    = proj:GetPhysicsObject()
        local vel     = IsValid(phys) and phys:GetVelocity() or proj:GetVelocity()
        local toGekko = (origin - proj:GetPos()):GetNormalized()
        local dot     = vel:GetNormalized():Dot(toGekko)
        if dot < 0.35 then continue end  -- travelling away or perpendicular — ignore

        -- ---- INTERCEPT ----
        local interceptPos = proj:GetPos()

        -- 1. Remove the projectile
        proj:Remove()

        -- 2. Explosion visual at intercept point
        DoInterceptExplosion(interceptPos)

        -- 3. Muzzle flash burst from Gekko body toward intercept
        SendInterceptMuzzleBurst(ent, interceptPos)

        -- 4. Screen shake / impact sound at intercept position (propagates to clients)
        ent:EmitSound("weapons/c4/c4_beep4.wav", 90, math.random(90, 110), 1)

        -- 5. Set rearm cooldown so we do not instantly shoot another
        ent._apsRearmTime = now + APS_REARM_DELAY

        print(string.format("[GekkoAPS] Intercepted '%s' at (%.0f,%.0f,%.0f)",
            proj:GetClass(), interceptPos.x, interceptPos.y, interceptPos.z))

        -- Only intercept one projectile per tick to avoid spam
        return
    end
end
