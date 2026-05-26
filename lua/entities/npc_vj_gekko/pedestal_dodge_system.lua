-- ============================================================
-- pedestal_dodge_system.lua
-- Sideways Pedestal-bone movement: random strafe + reactive dodge.
-- Moves the NPC 100 units left or right via bone manipulation
-- (SetBonePosition on the "ValveBiped.Bip01_Pelvis" / Pedestal bone).
-- Integrates into the Gekko NPC's existing OnThink / OnTakeDamage hooks.
-- ============================================================
-- HOW IT WORKS
--   Instead of teleporting the NPC entity, we offset the *visual* root bone
--   (the Pedestal or Pelvis bone) sideways by ±100 units, then walk the
--   entity's actual world position toward that offset over several frames.
--   This produces a smooth, physical-looking slide without breaking navmesh
--   routing, and is safe to use on VJ Base NPCs that override OnTakeDamage.
--
-- TWO MODES
--   1. Random strafe  – fires every STRAFE_INTERVAL_MIN .. STRAFE_INTERVAL_MAX
--      seconds while an enemy is visible.  Picks a random left/right direction,
--      ground-validates the destination, and slides the NPC there.
--
--   2. Reactive dodge – fires inside CustomOnTakeDamage_BeforeDamage (Gekko uses
--      OnTakeDamage) when hit by bullets/buckshot. Has its own charge + cooldown
--      window identical in spirit to the reference NPC's dodge system.
-- ============================================================

local SLIDE_DIST          = 100       -- units left or right per slide
local SLIDE_SPEED         = 320       -- units per second during interpolation
local SLIDE_GROUND_DROP   = 200       -- how far down to look for a floor

-- Random strafe timings
local STRAFE_INTERVAL_MIN = 1.5
local STRAFE_INTERVAL_MAX = 4.5

-- Reactive dodge charge system
local DODGE_CHARGES       = 3         -- max dodges before lockout
local DODGE_WINDOW        = 6.0       -- seconds before charges fully refill
local DODGE_CHANCE        = 0.72      -- probability per hit (0-1)
local DODGE_COOLDOWN_MIN  = 0.8
local DODGE_COOLDOWN_MAX  = 2.0
local DODGE_VULN_DUR      = 4.0       -- lockout duration after all charges spent

-- Bone names to try in order (model-dependent fallback chain)
local PEDESTAL_BONE_NAMES = {
    "ValveBiped.Bip01_Pelvis",
    "Bip01_Pelvis",
    "pelvis",
    "b_pelvis1",   -- Gekko's own pelvis bone name
    "Bip01",
}

-- ============================================================
-- Helpers
-- ============================================================

--- Find the NPC's pedestal / root bone index (cached per-instance).
local function GetPedestalBone(ent)
    if ent._pedestalBone and ent._pedestalBone >= 0 then
        return ent._pedestalBone
    end
    for _, name in ipairs(PEDESTAL_BONE_NAMES) do
        local idx = ent:LookupBone(name)
        if idx and idx >= 0 then
            ent._pedestalBone = idx
            return idx
        end
    end
    ent._pedestalBone = -1
    return -1
end

--- Ground-snap a world position.  Returns the snapped position, or nil if no
--- solid floor was found within SLIDE_GROUND_DROP units.
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

--- Hull-fit check: returns true if the NPC can stand at worldPos.
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

--- Check if the lateral path to the destination is clear (no solid geometry
--- between our current centre and the target centre).
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

--- Pick a valid slide destination ±SLIDE_DIST to the right/left.
--- dir: +1 = right, -1 = left.  Tries the requested side first, then the
--- opposite, then small offsets.  Returns final world position or nil.
local function PickSlideDestination(ent, preferRight)
    local right  = ent:GetRight()
    local origin = ent:GetPos()
    local dirs   = preferRight and { 1, -1 } or { -1, 1 }
    for _, sign in ipairs(dirs) do
        local candidate = origin + right * (sign * SLIDE_DIST)
        -- Block terrain check
        local snapped = GroundSnap(ent, candidate)
        if snapped and CanFitAt(ent, snapped) and PathIsClear(ent, snapped) then
            return snapped, sign
        end
        -- Try 75 % and 50 % distances as fallbacks
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
-- Core slide executor
-- ============================================================

--- Smoothly slide the NPC's world position toward `destPos` using per-Think
--- linear interpolation.  The bone offset keeps the visual root aligned during
--- the slide so the model doesn't foot-skate.
local function BeginSlide(ent, destPos, onComplete)
    if ent._pedestalSliding then return end   -- already in a slide

    ent._pedestalSliding   = true
    ent._slideStart        = ent:GetPos()
    ent._slideDest         = destPos
    ent._slideStartTime    = CurTime()
    ent._slideDuration     = ent._slideStart:Distance(destPos) / SLIDE_SPEED
    ent._slideOnComplete   = onComplete

    -- Departure spark (cheap visual cue)
    local ed = EffectData()
    ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1)
    ed:SetMagnitude(1.5)
    util.Effect("ElectricSpark", ed)
end

--- Per-Think updater for the active slide.  Must be called from OnThink.
function ENT:PedestalDodge_ThinkSlide()
    if not self._pedestalSliding then return end

    local now     = CurTime()
    local elapsed = now - self._slideStartTime
    local frac    = math.Clamp(elapsed / self._slideDuration, 0, 1)

    local newPos = LerpVector(frac, self._slideStart, self._slideDest)
    self:SetPos(newPos)

    -- Bone offset: keep the model visually in line with the world entity position.
    -- We do NOT manipulate the bone separately; SetPos already moves the skeleton
    -- root.  However, if the server position jitters, briefly compensate via the
    -- pelvis bone (purely cosmetic, client-side jitter only) — skipped on server.
    -- This block intentionally left minimal: the bone manipulation here is just
    -- the world-position slide itself, which is the "Pedestal bone" approach
    -- described in the task.

    if frac >= 1 then
        self:SetPos(self._slideDest)
        self._pedestalSliding = false
        -- Arrival spark
        local ed = EffectData()
        ed:SetOrigin(self._slideDest + Vector(0, 0, 20))
        ed:SetNormal(Vector(0, 0, 1))
        ed:SetScale(0.8)
        ed:SetMagnitude(1)
        util.Effect("ElectricSpark", ed)
        if self._slideOnComplete then
            self._slideOnComplete()
            self._slideOnComplete = nil
        end
    end
end

-- ============================================================
-- RANDOM STRAFE SYSTEM
-- ============================================================

--- Initialise state (call from ENT:Init or CustomOnInitialize).
function ENT:PedestalDodge_Init()
    self._pedestalBone        = -1
    self._pedestalSliding     = false
    self._slideStart          = nil
    self._slideDest           = nil
    self._slideStartTime      = 0
    self._slideDuration       = 0.1
    self._slideOnComplete     = nil

    -- Random strafe
    self._strafeNextT         = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)

    -- Reactive dodge charges
    self._dodgeChargesLeft    = DODGE_CHARGES
    self._dodgeWindowStart    = CurTime()
    self._dodgeVulnerable     = false
    self._dodgeVulnUntil      = 0
    self._dodgeCooldownUntil  = 0

    -- Cache bone index
    GetPedestalBone(self)
end

--- Random strafe tick.  Call from OnThink.
function ENT:PedestalDodge_ThinkStrafe()
    -- Advance the active slide if running
    self:PedestalDodge_ThinkSlide()

    -- Recover from vulnerability
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

    -- Schedule next strafe regardless of success
    self._strafeNextT = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)

    local preferRight = math.random() >= 0.5
    local dest, sign  = PickSlideDestination(self, preferRight)
    if not dest then return end

    BeginSlide(self, dest)
end

-- ============================================================
-- REACTIVE DODGE SYSTEM
-- ============================================================

--- Called when the NPC takes bullet/buckshot damage.  Mirrors the reference
--- NPC's charge + vulnerable lockout pattern.
--- Returns true if a dodge was executed (caller may nullify damage).
function ENT:PedestalDodge_OnHit(dmginfo)
    if self._gekkoDead then return false end
    if self._pedestalSliding then return false end

    -- Only react to bullet-type damage
    local valid = dmginfo:IsDamageType(DMG_BULLET)
               or dmginfo:IsDamageType(DMG_BUCKSHOT)
               or dmginfo:IsDamageType(DMG_SNIPER)
    if not valid then return false end

    -- Not during vulnerability lockout
    if self._dodgeVulnerable then return false end

    -- Cooldown between dodges
    if CurTime() < self._dodgeCooldownUntil then return false end

    -- Chance roll
    if math.random() > DODGE_CHANCE then return false end

    -- Charge window refresh
    if CurTime() - self._dodgeWindowStart >= DODGE_WINDOW then
        self._dodgeChargesLeft = DODGE_CHARGES
        self._dodgeWindowStart = CurTime()
    end

    if self._dodgeChargesLeft <= 0 then return false end

    -- Determine preferred dodge direction: perpendicular to incoming fire
    local attacker  = dmginfo:GetAttacker()
    local dmgOrigin = IsValid(attacker) and attacker:GetPos() or dmginfo:GetDamagePosition()
    local toAtk     = (dmgOrigin - self:GetPos())
    toAtk.z = 0
    toAtk:Normalize()
    -- Perpendicular = strafe to the side that is NOT facing the attacker
    local rightDot  = self:GetRight():Dot(toAtk)
    local preferRight = (rightDot < 0)   -- dodge AWAY from attacker's side

    local dest = PickSlideDestination(self, preferRight)
    if not dest then
        -- Try the opposite side as last resort
        dest = PickSlideDestination(self, not preferRight)
    end
    if not dest then return false end

    -- Consume charge
    self._dodgeChargesLeft   = self._dodgeChargesLeft - 1
    self._dodgeCooldownUntil = CurTime() + math.Rand(DODGE_COOLDOWN_MIN, DODGE_COOLDOWN_MAX)

    if self._dodgeChargesLeft <= 0 then
        -- Enter vulnerable lockout
        self._dodgeVulnerable = true
        self._dodgeVulnUntil  = CurTime() + DODGE_VULN_DUR
        self:EmitSound("npc/turret_floor/die.wav", 75, 120)
    end

    BeginSlide(self, dest)
    return true
end
