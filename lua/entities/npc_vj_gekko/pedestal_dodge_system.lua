-- ============================================================
-- pedestal_dodge_system.lua
-- Sideways movement via incremental SetPos each Think.
--
-- WHY SetPos AND NOT SetAbsVelocity/SetLocalVelocity:
--   VJ Base MOVETYPE_STEP NPCs have their velocity reset by the engine
--   every RunAI tick (the locomotion task owns the velocity).  SetPos
--   bypasses that and physically repositions the NPC.
--
-- WHY THE OLD VERSION STUTTERED:
--   GroundSnap (hull-trace) returned a slightly different Z value every
--   frame, making the entity bob up and down visibly.  Fix: we snapshot
--   the NPC's current Z at slide-start and keep it constant throughout
--   the slide. One DropToFloor at the end re-syncs to ground.
--
-- TWO MODES
--   1. Random strafe  – fires every STRAFE_INTERVAL_MIN..MAX seconds
--      while an enemy is visible.
--   2. Reactive dodge – fires on bullet/buckshot/sniper hits, charge-gated.
-- ============================================================

local SLIDE_DIST          = 100      -- units sideways per move
local SLIDE_SPEED         = 160      -- units per second

local STRAFE_INTERVAL_MIN = 1.5
local STRAFE_INTERVAL_MAX = 4.5

local DODGE_CHARGES       = 3
local DODGE_WINDOW        = 6.0
local DODGE_CHANCE        = 0.72
local DODGE_COOLDOWN_MIN  = 0.8
local DODGE_COOLDOWN_MAX  = 2.0
local DODGE_VULN_DUR      = 4.0

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

local function PickSlideDestination(ent, preferRight)
    local right  = ent:GetRight()
    local origin = ent:GetPos()
    local dirs   = preferRight and { 1, -1 } or { -1, 1 }
    for _, sign in ipairs(dirs) do
        local candidate = origin + right * (sign * SLIDE_DIST)
        if CanFitAt(ent, candidate) and PathIsClear(ent, candidate) then
            return candidate
        end
        for _, frac in ipairs({ 0.75, 0.5 }) do
            local shorter = origin + right * (sign * SLIDE_DIST * frac)
            if CanFitAt(ent, shorter) and PathIsClear(ent, shorter) then
                return shorter
            end
        end
    end
    return nil
end

-- ============================================================
-- BeginSlide
-- Snapshot the NPC's current Z so it stays locked during the slide.
-- This prevents the per-frame Z-jitter that caused the old stutter.
-- ============================================================

local function BeginSlide(ent, destPos)
    if ent._pedestalSliding then return end
    ent._pedestalSliding = true
    -- Lock the destination Z to the NPC's current Z so we only
    -- move horizontally each Think.  One DropToFloor on arrival
    -- will re-sync to the actual ground level.
    ent._slideDestWorld  = Vector(destPos.x, destPos.y, ent:GetPos().z)

    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)
end

-- ============================================================
-- Per-Think slide tick
-- Moves only on the XY plane at a fixed Z, preventing Z-jitter.
-- ============================================================

function ENT:PedestalDodge_ThinkSlide()
    if not self._pedestalSliding then return end

    local dest  = self._slideDestWorld
    local cur   = self:GetPos()
    -- Work purely in XY; Z stays pinned to _slideDestWorld.z
    local dx    = dest.x - cur.x
    local dy    = dest.y - cur.y
    local dist  = math.sqrt(dx * dx + dy * dy)

    if dist <= 4 then
        -- Arrived: snap to XY target, keep current Z, then re-sync ground.
        self:SetPos(Vector(dest.x, dest.y, cur.z))
        self:DropToFloor()
        self._pedestalSliding = false

        local ed = EffectData()
        ed:SetOrigin(self:GetPos() + Vector(0, 0, 20))
        ed:SetNormal(Vector(0, 0, 1))
        ed:SetScale(0.8)
        ed:SetMagnitude(1)
        util.Effect("ElectricSpark", ed)
        return
    end

    -- Step this frame (XY only, Z unchanged).
    local step  = math.min(SLIDE_SPEED * FrameTime(), dist)
    local nx    = cur.x + (dx / dist) * step
    local ny    = cur.y + (dy / dist) * step
    self:SetPos(Vector(nx, ny, dest.z))
end

-- ============================================================
-- INIT
-- ============================================================

function ENT:PedestalDodge_Init()
    self._pedestalSliding    = false
    self._slideDestWorld     = nil
    self._strafeNextT        = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
    self._dodgeChargesLeft   = DODGE_CHARGES
    self._dodgeWindowStart   = CurTime()
    self._dodgeVulnerable    = false
    self._dodgeVulnUntil     = 0
    self._dodgeCooldownUntil = 0
end

-- ============================================================
-- RANDOM STRAFE TICK
-- ============================================================

function ENT:PedestalDodge_ThinkStrafe()
    self:PedestalDodge_ThinkSlide()

    if self._dodgeVulnerable and CurTime() >= self._dodgeVulnUntil then
        self._dodgeVulnerable  = false
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = CurTime()
    end

    if self._pedestalSliding then return end
    if self._dodgeVulnerable then return end
    if CurTime() < self._strafeNextT then return end

    -- Guard: entity may be mid-removal when this Think fires.
    if not IsValid(self) then return end

    local enemy = self.VJ_TheEnemy
    if not IsValid(enemy) then
        local ok, result = pcall(function() return self:GetEnemy() end)
        if ok and IsValid(result) then enemy = result end
    end
    if not IsValid(enemy) then return end
    if not self:Visible(enemy) then return end

    self._strafeNextT = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)

    local dest = PickSlideDestination(self, math.random() >= 0.5)
    if not dest then return end

    BeginSlide(self, dest)
end

-- ============================================================
-- REACTIVE DODGE ON HIT
-- ============================================================

function ENT:PedestalDodge_OnHit(dmginfo)
    if self._gekkoDead then return false end
    if self._pedestalSliding then return false end

    local valid = dmginfo:IsDamageType(DMG_BULLET)
               or dmginfo:IsDamageType(DMG_BUCKSHOT)
               or dmginfo:IsDamageType(DMG_SNIPER)
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

    local dest = PickSlideDestination(self, preferRight)
    if not dest then dest = PickSlideDestination(self, not preferRight) end
    if not dest then return false end

    self._dodgeChargesLeft   = self._dodgeChargesLeft - 1
    self._dodgeCooldownUntil = CurTime() + math.Rand(DODGE_COOLDOWN_MIN, DODGE_COOLDOWN_MAX)

    if self._dodgeChargesLeft <= 0 then
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = CurTime() + DODGE_VULN_DUR
        self:EmitSound("npc/turret_floor/die.wav", 75, 120)
    end

    BeginSlide(self, dest)
    return true
end
