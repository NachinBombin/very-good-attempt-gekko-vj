-- ============================================================
-- pedestal_dodge_system.lua
-- Sideways movement via incremental SetPos each Think.
--
-- HOW IT WORKS
--   Each Think we advance the entity origin a small delta toward
--   the destination at SLIDE_SPEED units/s.  Moving the origin
--   physically triggers normal IK / skeletal follow-through so
--   legs and body shift naturally.  No bone manipulation needed.
--
-- TWO MODES
--   1. Random strafe  – fires every STRAFE_INTERVAL_MIN..MAX seconds
--      while an enemy is visible.
--   2. Reactive dodge – fires on bullet/buckshot/sniper hits, charge-gated.
-- ============================================================

local SLIDE_DIST          = 100      -- units sideways per move
local SLIDE_SPEED         = 160      -- units per second (tweak freely)
local SLIDE_GROUND_DROP   = 200      -- floor-search depth

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

local function GroundSnap(ent, worldPos)
    local mins = ent:OBBMins()
    local maxs = ent:OBBMaxs()
    local tr = util.TraceHull({
        start  = worldPos + Vector(0, 0, 40),
        endpos = worldPos - Vector(0, 0, SLIDE_GROUND_DROP),
        mins   = Vector(mins.x, mins.y, 0),
        maxs   = Vector(maxs.x, maxs.y, 1),
        filter = ent,
        mask   = MASK_NPCSOLID_BRUSHONLY,
    })
    if not tr.Hit or tr.StartSolid or tr.HitSky then return nil end
    return tr.HitPos
end

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

--- Pick a valid world-space destination ±SLIDE_DIST from origin.
--- Returns world position or nil.
local function PickSlideDestination(ent, preferRight)
    local right  = ent:GetRight()
    local origin = ent:GetPos()
    local dirs   = preferRight and { 1, -1 } or { -1, 1 }
    for _, sign in ipairs(dirs) do
        local candidate = origin + right * (sign * SLIDE_DIST)
        local snapped   = GroundSnap(ent, candidate)
        if snapped and CanFitAt(ent, snapped) and PathIsClear(ent, snapped) then
            return snapped
        end
        for _, frac in ipairs({ 0.75, 0.5 }) do
            local shorter = origin + right * (sign * SLIDE_DIST * frac)
            local snap2   = GroundSnap(ent, shorter)
            if snap2 and CanFitAt(ent, snap2) and PathIsClear(ent, snap2) then
                return snap2
            end
        end
    end
    return nil
end

-- ============================================================
-- BeginSlide
-- ============================================================

local function BeginSlide(ent, destPos)
    if ent._pedestalSliding then return end

    ent._pedestalSliding = true
    ent._slideDestWorld  = destPos

    -- Departure spark
    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)
end

-- ============================================================
-- Per-Think slide tick  (incremental origin movement)
-- ============================================================

function ENT:PedestalDodge_ThinkSlide()
    if not self._pedestalSliding then return end

    local dest   = self._slideDestWorld
    local cur    = self:GetPos()
    local delta  = dest - cur
    delta.z      = 0                          -- keep on ground plane
    local dist   = delta:Length()

    if dist <= 1 then
        -- Close enough: snap to destination and finish
        self:SetPos(dest)
        self._pedestalSliding = false

        -- Arrival spark
        local ed = EffectData()
        ed:SetOrigin(dest + Vector(0, 0, 20))
        ed:SetNormal(Vector(0, 0, 1))
        ed:SetScale(0.8)
        ed:SetMagnitude(1)
        util.Effect("ElectricSpark", ed)
        return
    end

    -- Step this frame
    local step = math.min(SLIDE_SPEED * FrameTime(), dist)
    local newPos = cur + delta:GetNormal() * step

    -- Keep ground-snapped so we don't float over ramps
    local snapped = GroundSnap(self, newPos)
    self:SetPos(snapped or newPos)
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

    local enemy = self.VJ_TheEnemy
    if not IsValid(enemy) then enemy = self:GetEnemy() end
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
