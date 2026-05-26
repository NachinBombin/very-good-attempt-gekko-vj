-- ============================================================
-- pedestal_dodge_system.lua
-- Sideways Pedestal-bone movement: random strafe + reactive dodge.
--
-- HOW IT WORKS
--   The entity origin NEVER moves.  Instead we accumulate a lateral
--   offset (_boneOffset, a scalar in local-right space) and apply it
--   every Think via SetBonePosition on the root/pedestal bone.
--   Because this is the skeleton root, every child bone (legs, spine,
--   arms) follows through normal IK/constraint propagation, producing
--   natural weight-shift without foot-skating or entity teleporting.
--
--   When the offset reaches its target we commit it to the entity
--   origin with a single SetPos + reset offset to 0, so the navmesh
--   origin stays roughly accurate for the AI pathfinder.
--
-- TWO MODES
--   1. Random strafe  – fires every STRAFE_INTERVAL_MIN..MAX seconds
--      while an enemy is visible.
--   2. Reactive dodge – fires on bullet/buckshot hits, charge-gated.
-- ============================================================

local SLIDE_DIST          = 100      -- units sideways per move
local SLIDE_SPEED         = 280      -- units per second of bone travel
local SLIDE_GROUND_DROP   = 200      -- floor-search depth

local STRAFE_INTERVAL_MIN = 1.5
local STRAFE_INTERVAL_MAX = 4.5

local DODGE_CHARGES       = 3
local DODGE_WINDOW        = 6.0
local DODGE_CHANCE        = 0.72
local DODGE_COOLDOWN_MIN  = 0.8
local DODGE_COOLDOWN_MAX  = 2.0
local DODGE_VULN_DUR      = 4.0

-- Root bone name chain – first match wins (cached per instance)
local ROOT_BONE_NAMES = {
    "b_pelvis1",               -- Gekko's own root
    "ValveBiped.Bip01_Pelvis",
    "Bip01_Pelvis",
    "pelvis",
    "Bip01",
}

-- ============================================================
-- Internal helpers
-- ============================================================

local function GetRootBone(ent)
    if ent._pedestalBone and ent._pedestalBone >= 0 then
        return ent._pedestalBone
    end
    for _, name in ipairs(ROOT_BONE_NAMES) do
        local idx = ent:LookupBone(name)
        if idx and idx >= 0 then
            ent._pedestalBone = idx
            return idx
        end
    end
    ent._pedestalBone = -1
    return -1
end

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
--- Returns (worldPos, sign) or nil.
local function PickSlideDestination(ent, preferRight)
    local right  = ent:GetRight()
    local origin = ent:GetPos()
    local dirs   = preferRight and { 1, -1 } or { -1, 1 }
    for _, sign in ipairs(dirs) do
        local candidate = origin + right * (sign * SLIDE_DIST)
        local snapped   = GroundSnap(ent, candidate)
        if snapped and CanFitAt(ent, snapped) and PathIsClear(ent, snapped) then
            return snapped, sign
        end
        for _, frac in ipairs({ 0.75, 0.5 }) do
            local shorter = origin + right * (sign * SLIDE_DIST * frac)
            local snap2   = GroundSnap(ent, shorter)
            if snap2 and CanFitAt(ent, snap2) and PathIsClear(ent, snap2) then
                return snap2, sign
            end
        end
    end
    return nil
end

-- ============================================================
-- Bone-offset applicator  (called every Think while sliding)
-- ============================================================

--- Apply the current _boneOffset to the root bone in local-right space.
--- The entity origin stays put; only the visual skeleton shifts.
local function ApplyBoneOffset(ent)
    local boneIdx = GetRootBone(ent)
    if boneIdx < 0 then return end

    -- Build the offset in world space: right * scalar
    local worldOffset = ent:GetRight() * ent._boneOffset

    -- GetBonePosition returns the bone's current world pos & angles.
    -- We move it to (naturalWorldPos + offset) to shift the whole skeleton.
    local bonePos, boneAng = ent:GetBonePosition(boneIdx)
    if not bonePos then return end

    -- We store the bone's "natural" position once per slide so we always
    -- add to the same base rather than accumulating drift.
    if not ent._boneNaturalPos then
        ent._boneNaturalPos = bonePos
    end

    ent:SetBonePosition(boneIdx, ent._boneNaturalPos + worldOffset, boneAng)
end

-- ============================================================
-- BeginSlide: start a bone-space slide toward destPos
-- ============================================================

local function BeginSlide(ent, destPos)
    if ent._pedestalSliding then return end

    -- How far right is the destination from current origin?
    local delta       = destPos - ent:GetPos()
    delta.z           = 0
    local rightAxis   = ent:GetRight()
    local targetOff   = rightAxis:Dot(delta)   -- signed scalar in right-space

    ent._pedestalSliding  = true
    ent._boneOffsetStart  = ent._boneOffset or 0
    ent._boneOffsetTarget = targetOff
    ent._slideStartTime   = CurTime()
    ent._slideDuration    = math.abs(targetOff - (ent._boneOffset or 0)) / SLIDE_SPEED
    ent._slideDestWorld   = destPos   -- where to commit origin when done
    ent._boneNaturalPos   = nil       -- reset so ApplyBoneOffset re-samples

    -- Departure spark
    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)
end

-- ============================================================
-- Per-Think slide tick
-- ============================================================

function ENT:PedestalDodge_ThinkSlide()
    if not self._pedestalSliding then return end

    local elapsed = CurTime() - self._slideStartTime
    local dur     = math.max(self._slideDuration, 0.01)
    local frac    = math.Clamp(elapsed / dur, 0, 1)

    -- Lerp the bone offset scalar
    self._boneOffset = Lerp(frac, self._boneOffsetStart, self._boneOffsetTarget)

    -- Push skeleton root sideways
    ApplyBoneOffset(self)

    if frac >= 1 then
        -- Commit: move entity origin to the real destination,
        -- then zero the bone offset so the skeleton sits naturally again.
        self:SetPos(self._slideDestWorld)
        self._boneOffset      = 0
        self._boneNaturalPos  = nil
        self._pedestalSliding = false

        -- Clear the bone override so the animation system retakes control
        local boneIdx = GetRootBone(self)
        if boneIdx >= 0 then
            local bonePos, boneAng = self:GetBonePosition(boneIdx)
            if bonePos then
                self:SetBonePosition(boneIdx, bonePos, boneAng)
            end
        end

        -- Arrival spark
        local ed = EffectData()
        ed:SetOrigin(self._slideDestWorld + Vector(0, 0, 20))
        ed:SetNormal(Vector(0, 0, 1))
        ed:SetScale(0.8)
        ed:SetMagnitude(1)
        util.Effect("ElectricSpark", ed)
    end
end

-- ============================================================
-- INIT
-- ============================================================

function ENT:PedestalDodge_Init()
    self._pedestalBone       = -1
    self._pedestalSliding    = false
    self._boneOffset         = 0
    self._boneOffsetStart    = 0
    self._boneOffsetTarget   = 0
    self._boneNaturalPos     = nil
    self._slideStartTime     = 0
    self._slideDuration      = 0.1
    self._slideDestWorld     = nil
    self._strafeNextT        = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
    self._dodgeChargesLeft   = DODGE_CHARGES
    self._dodgeWindowStart   = CurTime()
    self._dodgeVulnerable    = false
    self._dodgeVulnUntil     = 0
    self._dodgeCooldownUntil = 0
    GetRootBone(self)
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
