-- ============================================================
-- pedestal_dodge_system.lua
-- Sideways dodge via MOVETYPE_FLYGRAVITY + SetVelocity.
--
-- MOVEMENT (from jump_system.lua):
--   MOVETYPE_FLYGRAVITY takes the NPC out of VJ Base locomotion so
--   SetVelocity sticks. timer.Simple(dist/speed) restores MOVETYPE_STEP.
--   FLYGRAVITY applies gravity every tick; vel.z is set to 0 at launch
--   so the slide is a pure flat lateral glide with no hop arc.
--
-- CROUCH (reactive dodge only):
--   Before launching the slide we enter the crouch state manually
--   (hull shrink + _gekkoCrouching = true + NWBool). This makes
--   GeckoCrouch_Update() immediately enforce c_walk/cidle for the whole
--   slide, giving a smooth crouch-down blend from the model.
--   On cleanup we clear _gekkoCrouching so GeckoCrouch_Update() exits
--   normally and plays the stand-up blend on the next tick.
--
-- TWO MODES
--   1. Random strafe  -- NO crouch, no Z hop.
--   2. Reactive dodge -- FULL crouch, flat lateral slide.
-- ============================================================

local SLIDE_DIST          = 100
local SLIDE_SPEED         = 280      -- units/sec

-- No upward hop. vel.z is zeroed at launch; FLYGRAVITY gravity is the only
-- vertical force during the slide, keeping the NPC firmly on the ground.
local SLIDE_HOP_Z         = 0        -- flat slide, no ballistic hop

local STRAFE_INTERVAL_MIN = 1.5
local STRAFE_INTERVAL_MAX = 4.5

local DODGE_CHARGES       = 3
local DODGE_WINDOW        = 6.0
local DODGE_CHANCE        = 0.72
local DODGE_COOLDOWN_MIN  = 0.8
local DODGE_COOLDOWN_MAX  = 2.0
local DODGE_VULN_DUR      = 4.0

-- How long AFTER the slide ends we keep _gekkoDodgeCrouch = true.
-- This prevents the race condition where the timer.Simple fires on the
-- same tick that _gekkoCrouchHoldUntil expires, causing ExitCrouch to
-- fire before the sequence block ever runs with the correct physics velocity.
local DODGE_CROUCH_TAIL   = 0.35

-- Mirrored from crouch_system.lua
local STAND_REARM_DELAY   = 1.0
local HITBOX_HALF_W       = 64
local HITBOX_CROUCH_H     = 130
local HITBOX_STAND_H      = 200
local RAND_CHECK_MIN      = 6
local RAND_CHECK_MAX      = 8

-- ============================================================
-- Internal helpers
-- ============================================================

local function CanFitAt(ent, worldPos)
    local mins = ent:OBBMins()
    local maxs = ent:OBBMaxs()
    local fit = util.TraceHull({
        start  = worldPos + Vector(0, 0, 1),
        endpos = worldPos + Vector(0, 0, 1),
        mins   = mins,
        maxs   = maxs,
        filter = ent,
        mask   = MASK_NPCSOLID,
    })
    return not fit.StartSolid and not fit.AllSolid and not fit.Hit
end

local function PathIsClear(ent, destPos)
    local center = ent:OBBCenter()
    local mins   = ent:OBBMins()
    local maxs   = ent:OBBMaxs()
    local tr = util.TraceHull({
        start  = ent:GetPos() + center,
        endpos = destPos      + center,
        mins   = Vector(mins.x, mins.y, mins.z - center.z),
        maxs   = Vector(maxs.x, maxs.y, maxs.z - center.z),
        filter = ent,
        mask   = MASK_NPCSOLID,
    })
    return not tr.Hit or tr.Fraction > 0.85
end

local function PickSlideDir(ent, preferRight)
    local right  = ent:GetRight()
    local origin = ent:GetPos()
    local dirs   = preferRight and { 1, -1 } or { -1, 1 }
    for _, sign in ipairs(dirs) do
        local candidate = origin + right * (sign * SLIDE_DIST)
        if CanFitAt(ent, candidate) and PathIsClear(ent, candidate) then
            return right * sign
        end
        for _, frac in ipairs({ 0.75, 0.5 }) do
            local shorter = origin + right * (sign * SLIDE_DIST * frac)
            if CanFitAt(ent, shorter) and PathIsClear(ent, shorter) then
                return right * sign
            end
        end
    end
    return nil
end

-- ============================================================
-- Crouch enter/exit
--
-- Dodge_EnterCrouch sets _gekkoDodgeCrouch = true in addition to
-- _gekkoCrouching. crouch_system.lua checks _gekkoDodgeCrouch to
-- unconditionally keep the crouch alive for the slide + tail window,
-- regardless of wantCrouch or holdUntil expiry. This eliminates the
-- race condition between timer.Simple and _gekkoCrouchHoldUntil.
-- ============================================================

local function Dodge_EnterCrouch(ent, slideDur)
    local now = CurTime()
    ent._gekkoCrouching         = true
    ent._gekkoCrouchJustEntered = true
    -- Hold = slide + generous tail so the hold never expires mid-slide
    ent._gekkoCrouchHoldUntil   = now + slideDur + DODGE_CROUCH_TAIL + 0.5
    ent._gekkoCrouchSeqSet      = -1
    ent._gekkoObsOnSince        = nil
    ent._gekkoObsDebounced      = false
    ent._gekkoObsHullHit        = false
    -- Dedicated flag: crouch_system checks this to skip the wantCrouch
    -- early-exit path for the entire slide + tail window.
    ent._gekkoDodgeCrouch       = true
    ent._gekkoDodgeCrouchUntil  = now + slideDur + DODGE_CROUCH_TAIL

    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_CROUCH_H)
    )
    ent:SetNWBool("GekkoIsCrouching", true)
    print(string.format("[DodgeCrouch] Enter | holdUntil=%.2f  dodgeUntil=%.2f",
        ent._gekkoCrouchHoldUntil, ent._gekkoDodgeCrouchUntil))
end

local function Dodge_ExitCrouch(ent)
    local now = CurTime()
    ent._gekkoCrouching           = false
    ent._gekkoCrouchJustEntered   = false
    ent._gekkoCrouchSeqSet        = -1
    ent._gekkoDodgeCrouch         = false
    ent._gekkoDodgeCrouchUntil    = 0
    ent._gekkoObsRearmT           = now + STAND_REARM_DELAY
    ent._gekkoObsOnSince          = nil
    ent._gekkoObsDebounced        = false
    ent._gekkoObsHullHit          = false
    ent._gekkoCeilingHit          = false
    ent._gekkoCeilNextT           = 0
    ent._gekkoRandomCrouch        = false
    ent._gekkoRandomCrouchEndT    = 0
    ent._gekkoRandomDuration      = 0
    ent._gekkoRandomCrouchNextT   = now + math.Rand(RAND_CHECK_MIN, RAND_CHECK_MAX)

    ent:SetCollisionBounds(
        Vector(-HITBOX_HALF_W, -HITBOX_HALF_W, 0),
        Vector( HITBOX_HALF_W,  HITBOX_HALF_W, HITBOX_STAND_H)
    )
    ent:SetNWBool("GekkoIsCrouching", false)
    ent.VJ_CanMoveThink = true
    print("[DodgeCrouch] Exit | standing")
end

-- ============================================================
-- BeginSlide
-- ============================================================

local function BeginSlide(ent, slideDir, withCrouch)
    if ent._pedestalSliding then return end
    ent._pedestalSliding = true

    local slideDur = SLIDE_DIST / SLIDE_SPEED

    -- Enter crouch BEFORE switching movetype so the sequence change
    -- is visible from the very first frame of the slide.
    if withCrouch then
        Dodge_EnterCrouch(ent, slideDur)
    end

    -- Lock VJ AI movement (mirrors jump_system.lua)
    ent.VJ_IsMoving     = false
    ent.VJ_CanMoveThink = false
    ent:SetSchedule(SCHED_NONE)
    if not withCrouch then
        -- For non-crouch strafe only: suppress activity for the slide window.
        -- When withCrouch=true this is intentionally omitted so
        -- GeckoCrouch_Update can run freely and own the sequence.
        ent._gekkoSuppressActivity = CurTime() + slideDur + 0.1
    end

    -- Switch to physics-owned movetype (same as jump_system.lua).
    -- vel.z = 0 keeps the slide perfectly flat; FLYGRAVITY applies gravity
    -- naturally but since the NPC starts grounded there is no visible hop.
    ent:SetMoveType(MOVETYPE_FLYGRAVITY)

    local vel = slideDir * SLIDE_SPEED
    vel.z     = 0   -- no hop: flat lateral slide so FLYGRAVITY gravity is the only Z force
    ent:SetVelocity(vel)

    -- Spark on start
    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)

    timer.Simple(slideDur, function()
        if not IsValid(ent) then return end

        -- Stop horizontal movement, restore MOVETYPE_STEP.
        ent:SetVelocity(Vector(0, 0, 0))
        ent:SetMoveType(MOVETYPE_STEP)
        ent._pedestalSliding = false

        if withCrouch then
            -- Do NOT call Dodge_ExitCrouch here.
            -- _gekkoDodgeCrouch keeps the crouch animation alive for the
            -- tail window. crouch_system will call ExitCrouch itself once
            -- _gekkoDodgeCrouchUntil expires naturally on its next tick.
            ent.VJ_CanMoveThink = true
        else
            ent.VJ_CanMoveThink = true
        end

        -- Spark on end
        local ed2 = EffectData()
        ed2:SetOrigin(ent:GetPos() + Vector(0, 0, 20))
        ed2:SetNormal(Vector(0, 0, 1))
        ed2:SetScale(0.8)
        ed2:SetMagnitude(1)
        util.Effect("ElectricSpark", ed2)
    end)
end

-- ============================================================
-- INIT
-- ============================================================

function ENT:PedestalDodge_Init()
    self._pedestalSliding       = false
    self._strafeNextT           = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
    self._dodgeChargesLeft      = DODGE_CHARGES
    self._dodgeWindowStart      = CurTime()
    self._dodgeVulnerable       = false
    self._dodgeVulnUntil        = 0
    self._dodgeCooldownUntil    = 0
    self._gekkoDodgeCrouch      = false
    self._gekkoDodgeCrouchUntil = 0
end

-- ============================================================
-- RANDOM STRAFE TICK  (no crouch)
-- ============================================================

function ENT:PedestalDodge_ThinkStrafe()
    if self._dodgeVulnerable and CurTime() >= self._dodgeVulnUntil then
        self._dodgeVulnerable  = false
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = CurTime()
    end

    if self._pedestalSliding then return end
    if self._dodgeVulnerable then return end
    if CurTime() < self._strafeNextT then return end
    if not IsValid(self) then return end

    local enemy = self.VJ_TheEnemy
    if not IsValid(enemy) then
        local ok, result = pcall(function() return self:GetEnemy() end)
        if ok and IsValid(result) then enemy = result end
    end
    if not IsValid(enemy) then return end
    if not self:Visible(enemy) then return end

    self._strafeNextT = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)

    local dir = PickSlideDir(self, math.random() >= 0.5)
    if not dir then return end

    BeginSlide(self, dir, false)  -- no crouch, flat slide
end

-- ============================================================
-- REACTIVE DODGE ON HIT  (with crouch)
-- ============================================================

function ENT:PedestalDodge_OnHit(dmginfo)
    if self._gekkoDead then return false end
    if self._pedestalSliding then return false end

    local valid = dmginfo:IsDamageType(DMG_BULLET)
               or dmginfo:IsDamageType(DMG_BUCKSHOT)
               or dmginfo:IsDamageType(DMG_SNIPER)
               or dmginfo:IsDamageType(DMG_BLAST)
               or dmginfo:IsDamageType(DMG_EXPLOSION)
    if not valid then return false end

    if self._dodgeVulnerable then return false end
    if CurTime() < self._dodgeCooldownUntil then return false end
    if math.random() > DODGE_CHANCE then return false end

    if CurTime() - self._dodgeWindowStart >= DODGE_WINDOW then
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = CurTime()
    end
    if self._dodgeChargesLeft <= 0 then return false end

    local attacker  = dmginfo:GetAttacker()
    local dmgOrigin = IsValid(attacker) and attacker:GetPos() or dmginfo:GetDamagePosition()
    local toAtk     = (dmgOrigin - self:GetPos())
    toAtk.z = 0
    toAtk:Normalize()
    local preferRight = self:GetRight():Dot(toAtk) < 0

    local dir = PickSlideDir(self, preferRight)
    if not dir then dir = PickSlideDir(self, not preferRight) end
    if not dir then return false end

    self._dodgeChargesLeft   = self._dodgeChargesLeft - 1
    self._dodgeCooldownUntil = CurTime() + math.Rand(DODGE_COOLDOWN_MIN, DODGE_COOLDOWN_MAX)

    if self._dodgeChargesLeft <= 0 then
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = CurTime() + DODGE_VULN_DUR
        self:EmitSound("npc/turret_floor/die.wav", 75, 120)
    end

    BeginSlide(self, dir, true)  -- with crouch, flat slide
    return true
end
