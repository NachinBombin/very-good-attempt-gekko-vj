-- ============================================================
--  football_kick_system.lua
--  Melee Attack #5 : Football Kick
--
--  Phases (total FBK_DURATION = 1.2 s):
--    1. t 0.00-0.25  Wind-back    : left leg pulls back, both hips tilt
--    2. t 0.25-0.45  Hold         : stabilisation pause
--    3. t 0.45-0.65  Extension    : leg snaps forward, damage fires
--    4. t 0.65-1.00  Recovery     : both bones return to rest
--
--  Attack shape: forward cone  (dot >= 0.55, radius 180 u)
--  Damage:       FBK_DAMAGE    (server-side, single hit per kick)
--  NW signal:    GekkoFootballKickPulse  (pulsed int, client reads it)
-- ============================================================

-- ============================================================
--  Constants
-- ============================================================
local FBK_DURATION      = 1.2     -- total animation duration (seconds)
local FBK_P3_START      = 0.45    -- normalised t when extension begins
local FBK_P3_END        = 0.65    -- normalised t when extension ends / damage fires

local FBK_DAMAGE        = 120
local FBK_HIT_RADIUS    = 180     -- world units, cone search radius
local FBK_CONE_DOT      = 0.55    -- cos(~56 deg) forward cone
local FBK_FORCE         = 85000   -- impulse applied to physics objects
local FBK_HIT_HEIGHT    = 80      -- Z offset for hit origin (leg height)

local FBK_COOLDOWN_MIN  = 4.0     -- seconds between kicks
local FBK_COOLDOWN_MAX  = 7.0
local FBK_ENGAGE_DIST   = 220     -- max dist to enemy to use kick

local FBK_SOUND_WINDUP  = "physics/metal/metal_solid_impact_hard3.wav"
local FBK_SOUND_HIT     = "physics/metal/metal_solid_impact_hard5.wav"
local FBK_SOUND_SWING   = "physics/body/body_medium_impact_hard3.wav"

-- ============================================================
--  Helpers
-- ============================================================
local function GetActiveEnemy(ent)
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

local function PulseNW(ent)
    local prev = ent:GetNWInt("GekkoFootballKickPulse", 0)
    ent:SetNWInt("GekkoFootballKickPulse", prev + 1)
end

-- ============================================================
--  Damage application (called once at phase-3 peak)
-- ============================================================
local function FBK_ApplyDamage(ent)
    local origin = ent:GetPos() + Vector(0, 0, FBK_HIT_HEIGHT)
    local fwd    = ent:GetForward()

    for _, tgt in ipairs(ents.FindInSphere(origin, FBK_HIT_RADIUS)) do
        if tgt == ent then continue end
        if not IsValid(tgt) then continue end
        if not (tgt:IsNPC() or tgt:IsPlayer()) then continue end

        -- Cone check
        local toTgt = (tgt:GetPos() - origin)
        toTgt.z = 0
        local dist = toTgt:Length()
        if dist > 0.01 then
            toTgt:Normalize()
            if toTgt:Dot(fwd) < FBK_CONE_DOT then continue end
        end

        -- Relationship check (don't hit allies)
        local rel = ent:GetRelationship(tgt)
        if rel == D_LI or rel == D_NU then continue end

        -- Apply damage
        local dmg = DamageInfo()
        dmg:SetDamage(FBK_DAMAGE)
        dmg:SetAttacker(ent)
        dmg:SetInflictor(ent)
        dmg:SetDamageType(DMG_CLUB)
        dmg:SetDamagePosition(tgt:GetPos())
        dmg:SetDamageForce(fwd * FBK_FORCE + Vector(0, 0, FBK_FORCE * 0.25))
        tgt:TakeDamageInfo(dmg)

        -- Knockback on physics-capable targets
        local phys = tgt:GetPhysicsObject()
        if IsValid(phys) then
            phys:ApplyForceCenter(fwd * FBK_FORCE + Vector(0, 0, FBK_FORCE * 0.4))
        end

        print(string.format("[GekkoFBK] Hit %s  dmg=%d  dist=%.0f", tostring(tgt), FBK_DAMAGE, dist))
    end

    ent:EmitSound(FBK_SOUND_HIT, 90, math.random(90, 110))
end

-- ============================================================
--  ENT:GekkoFK_Init()
--  Call once from Init()
-- ============================================================
function ENT:GekkoFK_Init()
    self._fbkActive       = false
    self._fbkStartTime    = -9999
    self._fbkNextKick     = 0
    self._fbkDamageFired  = false
end

-- ============================================================
--  ENT:GekkoFK_ShouldKick()
--  Returns true when conditions are met to trigger a kick.
-- ============================================================
function ENT:GekkoFK_ShouldKick()
    if self._fbkActive then return false end
    if CurTime() < self._fbkNextKick then return false end

    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return false end

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > FBK_ENGAGE_DIST then return false end

    -- Must be facing the enemy (reuse cone dot)
    local fwd    = self:GetForward()
    local toEnm  = (enemy:GetPos() - self:GetPos())
    toEnm.z = 0
    if toEnm:Length() > 0.01 then
        toEnm:Normalize()
        if toEnm:Dot(fwd) < FBK_CONE_DOT then return false end
    end

    return true
end

-- ============================================================
--  ENT:GekkoFK_Execute()
--  Start a kick cycle.
-- ============================================================
function ENT:GekkoFK_Execute()
    if self._fbkActive then return end
    self._fbkActive      = true
    self._fbkStartTime   = CurTime()
    self._fbkDamageFired = false

    -- Suppress locomotion animation during kick
    self._gekkoSuppressActivity = CurTime() + FBK_DURATION + 0.1

    -- Signal client bone driver
    PulseNW(self)

    -- Windup sound
    self:EmitSound(FBK_SOUND_WINDUP, 85, math.random(88, 108))
    -- Swing sound at extension start
    timer.Simple(FBK_DURATION * FBK_P3_START, function()
        if not IsValid(self) then return end
        self:EmitSound(FBK_SOUND_SWING, 88, math.random(90, 115))
    end)

    print(string.format("[GekkoFBK] Execute  t=%.2f", self._fbkStartTime))
end

-- ============================================================
--  ENT:GekkoFK_Think()
--  Call every tick from OnThink()
-- ============================================================
function ENT:GekkoFK_Think()
    if not self._fbkActive then
        -- Check if a kick should be triggered
        if self:GekkoFK_ShouldKick() then
            self:GekkoFK_Execute()
        end
        return
    end

    local elapsed = CurTime() - self._fbkStartTime
    local t       = elapsed / FBK_DURATION

    -- Fire damage once at the peak of phase 3
    if not self._fbkDamageFired and t >= FBK_P3_END then
        self._fbkDamageFired = true
        FBK_ApplyDamage(self)
    end

    -- Animation complete
    if elapsed >= FBK_DURATION then
        self._fbkActive   = false
        self._fbkNextKick = CurTime() + math.Rand(FBK_COOLDOWN_MIN, FBK_COOLDOWN_MAX)
        print(string.format("[GekkoFBK] Complete  nextKick=%.2f", self._fbkNextKick))
    end
end
