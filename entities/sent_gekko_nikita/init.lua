AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  Nikita Homing Missile  -  server
--  v3 – Wide-Scan Omniscient Pathfinder
--
--  MOVEMENT:    MOVETYPE_NOCLIP + SetAbsVelocity (310 u/s constant)
--  HOMING:      self.TrackEnt (set by spawner)
--
-- ┌──────────────────────────────────────────────────────────┐
-- │  PATHFINDING v3 – KEY FIXES OVER v2                     │
-- │                                                          │
-- │  Problem: missile looped beside large openings (garage   │
-- │  doors) because:                                         │
-- │    1. FindAperture only searched near the hit point      │
-- │       (7×7 @ 28u = 168u span) – too small for big doors  │
-- │    2. Apertures scored by grid-centre proximity, not by  │
-- │       "best path to target", so a wide door off-axis     │
-- │       scored lower than a tiny hole straight ahead       │
-- │    3. Scout rays were biased toward missile's fwd facing │
-- │       – a door at 90° scored near zero on dot()         │
-- │    4. PATH_BLEND = 0.70 still leaked 0.30 raw-homing     │
-- │       back toward the wall during approach               │
-- │    5. No approach-angle alignment: entering at steep     │
-- │       angle caused hull clearance to fail at the frame   │
-- │                                                          │
-- │  v3 Solutions:                                           │
-- │    A. WIDE SLAB SCAN: instead of one hit-point grid,     │
-- │       cast a dense slab of hull-sweeps across the entire │
-- │       blocking plane up to SLAB_HALF_SIZE (300u) in      │
-- │       both tangent axes. Finds garage doors, room        │
-- │       openings, and any gap the missile can fit through. │
-- │    B. TARGET-AWARE APERTURE SCORING: each candidate      │
-- │       aperture is scored by how well flying through it   │
-- │       continues progress toward the target, not by       │
-- │       proximity to where the missile happened to hit.    │
-- │    C. APPROACH ALIGNMENT: when an aperture is chosen,    │
-- │       the approach direction is blended with the         │
-- │       aperture's wall-normal so the missile enters       │
-- │       perpendicular to the opening instead of slicing    │
-- │       through the frame at an angle.                     │
-- │    D. FULL-SPHERE SCOUT RAYS (not hemisphere): the 48    │
-- │       scout rays now cover a full sphere. When the       │
-- │       opening is behind-left, a hemisphere scan misses   │
-- │       it entirely.                                       │
-- │    E. STICKY APERTURE: once an aperture is found, the    │
-- │       missile commits to it (PATH_BLEND rises to 0.92)   │
-- │       until it has flown through. Prevents the homing    │
-- │       residual from pulling it back into the wall.       │
-- │    F. INTERVAL: 0.5s (as requested).                     │
-- └──────────────────────────────────────────────────────────┘
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  TUNING CONSTANTS
-- ─────────────────────────────────────────────────────────────

local CRUISE_SPEED  = 310
local TURN_SPEED    = 9.0
local TARGET_Z_OFFS = 40
local LIFETIME      = 45
local ENGINE_DELAY  = 0.5
local PROX_RADIUS   = 280

local EMERG_DIST    = 200
local TACT_DIST     = 600
local STRAT_DIST    = 1800

local EMERG_STRENGTH  = 1.0
local TACT_STRENGTH   = 0.82
local STRAT_STRENGTH  = 0.30

local TACT_CLOSE_BOOST_DIST = 180
local CORRIDOR_TURN_MULT    = 1.6
local BODY_HALF             = 14

-- ─────────────────────────────────────────────────────────────
--  PATHFINDING CONSTANTS
-- ─────────────────────────────────────────────────────────────

local PATHFIND_INTERVAL  = 0.5      -- seconds between full path recalculations

local SCOUT_RAY_DIST     = 1200     -- how far scout rays reach
local PATH_BLEND_NORMAL  = 0.70     -- blend when no aperture locked
local PATH_BLEND_LOCKED  = 0.92     -- blend when committed to an aperture
local SCORE_ANGLE_WEIGHT = 1.5
local SCORE_DIST_WEIGHT  = 1.0
local SCORE_APT_BONUS    = 4.0

-- Wide slab scan for aperture detection
-- Scans a grid across the blocking surface.
-- SLAB_HALF_SIZE = how far (in units) to scan left/right/up/down from hit centre.
-- SLAB_STEP      = spacing between probe points (should be ~2x BODY_HALF).
-- Using 300u half-size and 36u step → ~(17×17 = 289 probes) max.
-- A standard garage door is 200–300u wide; this will cover it.
local SLAB_HALF_SIZE = 300
local SLAB_STEP      = 36
local SLAB_PROBE_LEN = 120   -- depth of each probe through the wall

-- After finding an aperture, how close must the missile fly to it
-- before we consider it "entered" and release the sticky lock.
local APERTURE_REACHED_DIST = 120

-- Full-sphere scout ray table: {pitch, yaw}
-- 48 rays covering a full sphere at ~30° intervals,
-- denser in the forward hemisphere where we spend most time.
local SCOUT_RAYS = {
    -- Forward hemisphere (denser)
    {  0,   0 },
    {  0,  30 }, {  0, -30 }, {  0,  60 }, {  0, -60 },
    {  0,  90 }, {  0, -90 }, {  0, 120 }, {  0,-120 },
    {  0, 150 }, {  0,-150 }, {  0, 180 },
    { 30,   0 }, {-30,   0 }, { 60,   0 }, {-60,   0 },
    { 30,  45 }, { 30, -45 }, {-30,  45 }, {-30, -45 },
    { 30,  90 }, { 30, -90 }, {-30,  90 }, {-30, -90 },
    { 30, 135 }, { 30,-135 }, {-30, 135 }, {-30,-135 },
    { 60,  60 }, { 60, -60 }, {-60,  60 }, {-60, -60 },
    { 60,  90 }, { 60, -90 }, {-60,  90 }, {-60, -90 },
    -- Straight up/down
    { 90,   0 }, {-90,   0 },
    -- Diagonal up/down
    { 45,   0 }, {-45,   0 }, { 45, 180 }, {-45, 180 },
    { 45,  90 }, { 45, -90 }, {-45,  90 }, {-45, -90 },
}

-- ─────────────────────────────────────────────────────────────
--  COLLISION RESILIENCE CONSTANTS
-- ─────────────────────────────────────────────────────────────

local ARMOR_MAX               = 8
local BUMP_COOLDOWN           = 0.15
local ARMOR_REGEN_AMOUNT      = 1
local ARMOR_REGEN_INTERVAL    = 2.0
local STREAK_MAX              = 7
local STREAK_WINDOW           = 1.5
local WALL_KICK_STRENGTH      = 0.6
local PROP_MASS_LIMIT         = 80
local PROP_KNOCKBACK          = 28000
local DEBRIS_DAMAGE_THRESHOLD = 15

-- ─────────────────────────────────────────────────────────────
--  REACTIVE RAY FANS (every tick)
-- ─────────────────────────────────────────────────────────────

local RAYS_EMERG = {
    { 0,    0,    1.2 },
    { 0,    45,   1.0 }, { 0,   -45,  1.0 },
    { 0,    90,   1.0 }, { 0,   -90,  1.0 },
    { 0,   135,   0.8 }, { 0,  -135,  0.8 },
    { 0,   180,   0.6 },
    {-90,   0,    1.0 }, { 90,   0,   1.0 },
    {-45,   0,    1.0 }, {-45,  90,   0.9 }, {-45, -90,  0.9 },
    {-45,  45,    0.9 }, {-45, -45,   0.9 },
    { 45,   0,    1.0 }, { 45,  90,   0.9 }, { 45, -90,  0.9 },
    { 45,  45,    0.9 }, { 45, -45,   0.9 },
    {-20,  22,    1.0 }, {-20, -22,   1.0 },
    { 20,  22,    1.0 }, { 20, -22,   1.0 },
    { 0,   22,    1.1 }, { 0,  -22,   1.1 },
}

local RAYS_TACT = {
    { 0,    0,    1.4 },
    { 0,    15,   1.2 }, { 0,  -15,   1.2 },
    { 0,    30,   1.1 }, { 0,  -30,   1.1 },
    { 0,    50,   1.0 }, { 0,  -50,   1.0 },
    { 0,    70,   0.8 }, { 0,  -70,   0.8 },
    {-15,   0,    1.1 }, { 15,   0,   1.1 },
    {-30,   0,    1.0 }, { 30,   0,   1.0 },
    {-20,  30,    1.0 }, {-20, -30,   1.0 },
    { 20,  30,    1.0 }, { 20, -30,   1.0 },
    { 0,   90,    0.7 }, { 0,  -90,   0.7 },
}

local RAYS_STRAT = {
    { 0,    0,    1.0 },
    { 0,   18,    0.8 }, { 0,  -18,   0.8 },
    {-18,   0,    0.8 }, { 18,   0,   0.8 },
}

-- ─────────────────────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────────────────────

local function GetAimPos(trackEnt, fallback)
    if IsValid(trackEnt) then
        local p = trackEnt:GetPos()
        return Vector(p.x, p.y, p.z + TARGET_Z_OFFS)
    end
    return fallback
end

local function CastLocalRay(ent, origin, pitch, yaw, maxDist, filter)
    local dir = ent:LocalToWorldAngles(Angle(pitch, yaw, 0)):Forward()
    local tr  = util.TraceLine({
        start  = origin,
        endpos = origin + dir * maxDist,
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    return tr, dir
end

local function ComputeRepulsion(ent, origin, rayTable, maxDist, pushDist, filter)
    local repulsion = Vector(0, 0, 0)
    local anyHit    = false
    local minDist   = math.huge

    for _, ray in ipairs(rayTable) do
        local tr, dir = CastLocalRay(ent, origin, ray[1], ray[2], maxDist, filter)
        if tr.Hit then
            local d = (origin - tr.HitPos):Length()
            if d < minDist then minDist = d end
            local proxW = 1.0 - math.Clamp(d / maxDist, 0, 1)
            if d < TACT_CLOSE_BOOST_DIST then proxW = proxW * 2.0 end
            repulsion = repulsion + tr.HitNormal * (proxW * ray[3])
            anyHit    = true
        end
    end

    return repulsion, anyHit, minDist
end

-- Hull-sweep clearance: returns (openDist, fits)
local function BodyFits(origin, dir, len, filter)
    local tr = util.TraceHull({
        start  = origin,
        endpos = origin + dir * len,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if not tr.Hit then return len, true end
    return (origin - tr.HitPos):Length(), false
end

-- Build two orthonormal tangent vectors for a given normal.
local function BuildTangents(normal)
    local up    = Vector(0, 0, 1)
    local right = normal:Cross(up)
    if right:LengthSqr() < 0.001 then
        right = normal:Cross(Vector(1, 0, 0))
    end
    right:Normalize()
    local tang = right:Cross(normal)
    tang:Normalize()
    return right, tang
end

-- ─────────────────────────────────────────────────────────────
--  WIDE SLAB APERTURE SCANNER  (v3 core improvement)
--
--  Casts a dense grid of hull-sweeps across the entire blocking
--  surface.  Each open cell is scored by how well flying through
--  it continues progress toward aimPos.
--
--  hitPos    – world pos where direct trace hit the wall
--  hitNormal – outward face normal of the blocking surface
--  missilePos– missile's current position
--  aimPos    – world pos of the target
--  filter    – trace filter
--
--  Returns:
--    bestPoint   (Vector)  – world-space centre of best aperture, or nil
--    bestNormal  (Vector)  – wall-outward normal (approach axis), or nil
-- ─────────────────────────────────────────────────────────────
local function WideSlabScan(hitPos, hitNormal, missilePos, aimPos, filter)
    local right, tang = BuildTangents(hitNormal)

    -- Step back from the surface so probes start in open air
    local origin = hitPos + hitNormal * (BODY_HALF + 8)

    -- Direction through the wall (away from missile)
    local probeDir = -hitNormal

    -- Direction from hit point toward target (used for scoring)
    local toTarget = (aimPos - hitPos):GetNormalized()

    local bestPoint  = nil
    local bestNormal = nil
    local bestScore  = -math.huge

    local half = SLAB_HALF_SIZE
    local step = SLAB_STEP

    for row = -half, half, step do
        for col = -half, half, step do
            local pt = origin + right * col + tang * row

            -- Quick line check first – skip expensive hull if even a ray is blocked
            local quickTr = util.TraceLine({
                start  = pt,
                endpos = pt + probeDir * SLAB_PROBE_LEN,
                mask   = MASK_SOLID_BRUSHONLY,
                filter = filter,
            })
            if not quickTr.Hit then
                -- Full hull sweep to confirm the missile body fits
                local _, fits = BodyFits(pt, probeDir, SLAB_PROBE_LEN, filter)
                if fits then
                    -- Score 1: does flying through here continue progress toward target?
                    local aptToTarget  = (aimPos - pt):GetNormalized()
                    local progressDot  = aptToTarget:Dot(-hitNormal)

                    -- Score 2: how well does the missile's approach angle align?
                    local missileToPt  = (pt - missilePos):GetNormalized()
                    local approachDot  = math.max(0, missileToPt:Dot(toTarget))

                    -- Score 3: altitude match – prefer apertures at missile's Z
                    local zDiff  = math.abs(pt.z - missilePos.z)
                    local zScore = 1.0 - math.Clamp(zDiff / 300, 0, 1)

                    local score = progressDot * 2.0 + approachDot * 1.5 + zScore * 0.8

                    if score > bestScore then
                        bestScore  = score
                        bestPoint  = pt
                        bestNormal = hitNormal
                    end
                end
            end
        end
    end

    return bestPoint, bestNormal
end

-- ─────────────────────────────────────────────────────────────
--  3-D OMNISCIENT PATHFINDER  (v3)
--
--  Called every PATHFIND_INTERVAL seconds.
--  Writes into self:
--    _pathDir       (Vector|nil)  – steering override direction
--    _aptPoint      (Vector|nil)  – locked aperture world-pos
--    _aptNormal     (Vector|nil)  – aperture wall-normal
--    _aptLocked     (bool)        – missile is committed to an aperture
-- ─────────────────────────────────────────────────────────────
local function UpdatePath(self, myPos, aimPos, filter)
    if not aimPos then
        self._pathDir   = nil
        self._aptPoint  = nil
        self._aptNormal = nil
        self._aptLocked = false
        return
    end

    -- ── Check if we have already passed through a locked aperture ────
    if self._aptLocked and self._aptPoint then
        local distToApt = (myPos - self._aptPoint):Length()
        if distToApt < APERTURE_REACHED_DIST then
            -- Through the opening: release lock
            self._aptLocked = false
            self._aptPoint  = nil
            self._aptNormal = nil
            self._pathDir   = nil
            return
        end
        -- Still approaching: verify the aperture is still reachable
        local verifyTr = util.TraceLine({
            start  = myPos,
            endpos = self._aptPoint,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })
        if not verifyTr.Hit then
            -- Clear line to aperture: fly straight at it, blended with approach normal
            local toApt   = (self._aptPoint - myPos):GetNormalized()
            local aligned = LerpVector(0.35, toApt, -self._aptNormal)
            aligned:Normalize()
            self._pathDir = aligned
            return
        end
        -- Blocked (door closed?): release lock and re-scan below
        self._aptLocked = false
        self._aptPoint  = nil
        self._aptNormal = nil
    end

    -- ── Step 1: hull-trace directly to target ────────────────────────
    local directTr = util.TraceHull({
        start  = myPos,
        endpos = aimPos,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })

    if not directTr.Hit then
        self._pathDir   = nil
        self._aptPoint  = nil
        self._aptNormal = nil
        self._aptLocked = false
        return
    end

    -- ── Step 2: wide slab scan on the blocking surface ───────────────
    local aptPoint, aptNormal = WideSlabScan(
        directTr.HitPos, directTr.HitNormal,
        myPos, aimPos, filter
    )

    if aptPoint then
        local toAptTr = util.TraceLine({
            start  = myPos,
            endpos = aptPoint,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })

        if not toAptTr.Hit then
            -- Lock onto this aperture
            self._aptPoint  = aptPoint
            self._aptNormal = aptNormal
            self._aptLocked = true

            local toApt   = (aptPoint - myPos):GetNormalized()
            local aligned = LerpVector(0.35, toApt, -aptNormal)
            aligned:Normalize()
            self._pathDir = aligned
            return
        end

        -- Aperture reachable only as soft bias
        local toApt = (aptPoint - myPos):GetNormalized()
        self._pathDir   = toApt
        self._aptLocked = false
        return
    end

    -- ── Step 3: no aperture found – fall back to best scout ray ──────
    local toTarget  = (aimPos - myPos):GetNormalized()
    local bestScore = -math.huge
    local bestDir   = nil

    for _, ray in ipairs(SCOUT_RAYS) do
        local dir = self:LocalToWorldAngles(Angle(ray[1], ray[2], 0)):Forward()
        local openDist, fits = BodyFits(myPos, dir, SCOUT_RAY_DIST, filter)
        local dot       = math.max(0, dir:Dot(toTarget))
        local distScore = openDist / SCOUT_RAY_DIST
        local aptBonus  = fits and SCORE_APT_BONUS or 0
        local score = SCORE_ANGLE_WEIGHT * dot + SCORE_DIST_WEIGHT * distScore + aptBonus

        if score > bestScore then
            bestScore = score
            bestDir   = dir
        end
    end

    self._pathDir   = bestDir
    self._aptLocked = false
end

-- ─────────────────────────────────────────────────────────────
--  CLEARANCE PROBE  (immediate obstacle slide)
-- ─────────────────────────────────────────────────────────────
local function ClearanceProbe(origin, moveDir, filter)
    local trC = util.TraceHull({
        start  = origin,
        endpos = origin + moveDir * 80,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if not trC.Hit then return true, nil end

    local normal = trC.HitNormal
    local slide  = moveDir - normal * moveDir:Dot(normal)
    if slide:LengthSqr() < 0.001 then
        local tangA, tangB = BuildTangents(normal)
        slide = math.abs(tangA:Dot(moveDir)) >= math.abs(tangB:Dot(moveDir)) and tangA or tangB
    end
    slide:Normalize()
    return false, slide
end

-- ─────────────────────────────────────────────────────────────
--  COLLISION RESILIENCE HELPERS
-- ─────────────────────────────────────────────────────────────

local function BumpArmor(self, now)
    if now - self._lastBumpTime < BUMP_COOLDOWN then return false end
    self._lastBumpTime = now
    self.ArmorHP       = self.ArmorHP - 1
    if now - self._streakStart > STREAK_WINDOW then
        self._bumpStreak  = 0
        self._streakStart = now
    end
    self._bumpStreak = self._bumpStreak + 1
    if self.ArmorHP <= 0             then return true end
    if self._bumpStreak > STREAK_MAX then return true end
    return false
end

local function WallKick(self, hitNormal)
    local cur     = self:GetForward()
    local reflect = cur - hitNormal * (2 * cur:Dot(hitNormal))
    local kicked  = LerpVector(WALL_KICK_STRENGTH, cur, reflect)
    kicked:Normalize()
    self:SetAngles(kicked:Angle())
    self:SetAbsVelocity(kicked * CRUISE_SPEED)
end

local function HandlePropContact(self, ent)
    if not IsValid(ent) then return false end
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return false end
    if phys:GetMass() < PROP_MASS_LIMIT then
        local pushDir = (ent:GetPos() - self:GetPos()):GetNormalized()
        phys:ApplyForceCenter(pushDir * PROP_KNOCKBACK)
        return true
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
--  ENTITY LIFECYCLE
-- ─────────────────────────────────────────────────────────────

function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_launch.mdl")
    self:SetModelScale(7, 0)
    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = 50
    self.Damage       = 0
    self.Radius       = 0

    self._prevDistSqr = math.huge

    -- Path state
    self._pathDir     = nil
    self._aptPoint    = nil
    self._aptNormal   = nil
    self._aptLocked   = false
    self._nextPathTime= 0

    -- Collision resilience
    self.ArmorHP        = ARMOR_MAX
    self._lastBumpTime  = -999
    self._bumpStreak    = 0
    self._streakStart   = CurTime()
    self._nextArmorRegen= CurTime() + ARMOR_REGEN_INTERVAL

    self:SetNWFloat("NikitaBoost", 0)

    -- Spawner must set:
    --   self.TrackEnt       = <entity or nil>
    --   self.FallbackTarget = <Vector or nil>
    --   self.NikitaOwner    = <entity>

    self:SetAbsVelocity(self:GetForward() * 80)

    local selfRef = self
    timer.Simple(ENGINE_DELAY, function()
        if not IsValid(selfRef) or selfRef.Destroyed then return end
        selfRef.Damage       = math.random(25, 45)
        selfRef.Radius       = math.random(700, 1024)
        selfRef.EngineActive = true
    end)

    self:NextThink(CurTime())
end

-- ─────────────────────────────────────────────────────────────
--  THINK
-- ─────────────────────────────────────────────────────────────

function ENT:Think()
    self:NextThink(CurTime())
    if self.Destroyed then return true end

    local now = CurTime()
    local dt  = math.max(FrameTime(), 0.001)

    if now - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion(); return true
    end

    if not self.EngineActive then return true end

    -- Armor regen
    if now >= self._nextArmorRegen then
        self._nextArmorRegen = now + ARMOR_REGEN_INTERVAL
        self.ArmorHP = math.min(self.ArmorHP + ARMOR_REGEN_AMOUNT, ARMOR_MAX)
    end

    local myPos      = self:GetPos()
    local currentDir = self:GetForward()
    local filter     = { self, IsValid(self.NikitaOwner) and self.NikitaOwner or self }

    -- 1. HOMING TARGET
    local aimPos = GetAimPos(self.TrackEnt, self.FallbackTarget)

    -- 2. PROXIMITY DETONATION
    if aimPos then
        local distSqr = (myPos - aimPos):LengthSqr()
        if distSqr < PROX_RADIUS * PROX_RADIUS then
            self:MissileDoExplosion(); return true
        end
        if IsValid(self.TrackEnt) then
            local rawSqr = (myPos - self.TrackEnt:GetPos()):LengthSqr()
            if rawSqr < PROX_RADIUS * PROX_RADIUS then
                self:MissileDoExplosion(); return true
            end
        end
        local gate = (PROX_RADIUS * 4) * (PROX_RADIUS * 4)
        if distSqr > self._prevDistSqr and distSqr < gate then
            self:MissileDoExplosion(); return true
        end
        self._prevDistSqr = distSqr
    else
        self._prevDistSqr = math.huge
    end

    -- 3. PATH UPDATE (every PATHFIND_INTERVAL)
    if now >= self._nextPathTime then
        self._nextPathTime = now + PATHFIND_INTERVAL
        UpdatePath(self, myPos, aimPos, filter)
    end

    -- 4. THREE-LAYER SPATIAL AWARENESS (reactive, every tick)
    local noseTip = myPos + currentDir * 20

    local emergRepulsion, emergHit, emergMin =
        ComputeRepulsion(self, noseTip, RAYS_EMERG, EMERG_DIST, EMERG_DIST * 0.5, filter)
    local tactRepulsion, tactHit, tactMin =
        ComputeRepulsion(self, noseTip, RAYS_TACT, TACT_DIST, TACT_DIST * 0.5, filter)

    local stratRepulsion, stratHit = Vector(0,0,0), false

    local trL = CastLocalRay(self, noseTip,  0,  90, TACT_DIST, filter)
    local trR = CastLocalRay(self, noseTip,  0, -90, TACT_DIST, filter)
    local inCorridor = trL.Hit and trR.Hit
        and (noseTip - trL.HitPos):Length() < TACT_DIST
        and (noseTip - trR.HitPos):Length() < TACT_DIST

    local activeTurnSpeed = TURN_SPEED
    if inCorridor then
        activeTurnSpeed = TURN_SPEED * CORRIDOR_TURN_MULT
    else
        stratRepulsion, stratHit =
            ComputeRepulsion(self, noseTip, RAYS_STRAT, STRAT_DIST, STRAT_DIST * 0.3, filter)
    end

    -- 5. COMPOSE STEERING DIRECTION
    local rawHomingDir = aimPos and (aimPos - myPos):GetNormalized() or currentDir

    local pathBlend = self._aptLocked and PATH_BLEND_LOCKED or PATH_BLEND_NORMAL

    local homingDir = rawHomingDir
    if self._pathDir then
        homingDir = LerpVector(pathBlend, rawHomingDir, self._pathDir)
        homingDir:Normalize()
    end

    local totalRepulsion = Vector(0,0,0)
    if emergHit then
        local n = emergRepulsion:Length()
        if n > 0 then totalRepulsion = totalRepulsion + (emergRepulsion/n) * EMERG_STRENGTH end
    end
    if tactHit then
        local n = tactRepulsion:Length()
        if n > 0 then totalRepulsion = totalRepulsion + (tactRepulsion/n) * TACT_STRENGTH end
    end
    if stratHit then
        local n = stratRepulsion:Length()
        if n > 0 then totalRepulsion = totalRepulsion + (stratRepulsion/n) * STRAT_STRENGTH end
    end

    local desiredDir
    local repLen = totalRepulsion:Length()
    if repLen > 0.01 then
        local blendFactor
        if emergHit and emergMin < EMERG_DIST then
            blendFactor = 1.0
        elseif tactHit then
            blendFactor = math.Clamp(1.0 - (tactMin / TACT_DIST), 0, TACT_STRENGTH)
        else
            blendFactor = STRAT_STRENGTH * 0.5
        end
        -- When locked onto aperture, suppress repulsion except emergency
        if self._aptLocked and not (emergHit and emergMin < EMERG_DIST) then
            blendFactor = blendFactor * 0.4
        end
        desiredDir = LerpVector(blendFactor, homingDir, totalRepulsion:GetNormalized())
        desiredDir:Normalize()
    else
        desiredDir = homingDir
    end

    -- 6. CLEARANCE PROBE
    local fits, slideDir = ClearanceProbe(myPos, desiredDir, filter)
    if not fits and slideDir then
        desiredDir = LerpVector(0.7, desiredDir, slideDir)
        desiredDir:Normalize()
    end

    -- 7. TURN + VELOCITY (time-based angle-clamped slerp)
    local maxAngle = activeTurnSpeed * dt
    local cosAngle = math.Clamp(currentDir:Dot(desiredDir), -1, 1)
    local angle    = math.acos(cosAngle)

    local moveDir
    if angle < 0.001 then
        moveDir = desiredDir
    else
        local t = math.min(maxAngle / angle, 1.0)
        moveDir = LerpVector(t, currentDir, desiredDir)
        moveDir:Normalize()
    end

    self:SetNWFloat("NikitaBoost", (self._aptLocked or self._pathDir ~= nil) and 1 or 0)
    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    -- 8. AHEAD HULL TRACE – collision resilience
    local stepDist = CRUISE_SPEED * dt + 16
    local tr = util.TraceHull({
        start  = myPos,
        endpos = myPos + moveDir * stepDist,
        mins   = Vector(-8, -8, -8),
        maxs   = Vector( 8,  8,  8),
        mask   = MASK_SHOT,
        filter = filter,
    })

    if tr.Hit then
        if tr.HitWorld then
            local shouldDetonate = BumpArmor(self, now)
            if shouldDetonate then self:MissileDoExplosion(); return true end
            WallKick(self, tr.HitNormal)
        elseif IsValid(tr.Entity) then
            local ent = tr.Entity
            if ent == self.NikitaOwner then
                -- ignore
            elseif ent:IsPlayer() or ent:IsNPC() then
                self:MissileDoExplosion(); return true
            else
                local knocked = HandlePropContact(self, ent)
                if not knocked then self:MissileDoExplosion(); return true end
                local shouldDetonate = BumpArmor(self, now)
                if shouldDetonate then self:MissileDoExplosion(); return true end
            end
        end
    end

    return true
end

-- ─────────────────────────────────────────────────────────────
--  TOUCH / DAMAGE / EXPLOSION
-- ─────────────────────────────────────────────────────────────

function ENT:Touch(ent)
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.NikitaOwner then return end
    if IsValid(ent) and (ent:IsPlayer() or ent:IsNPC()) then
        self:MissileDoExplosion(); return
    end
    local shouldDetonate = BumpArmor(self, CurTime())
    if shouldDetonate then self:MissileDoExplosion() end
end

function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end
    local dmg = dmginfo:GetDamage()
    if dmg >= DEBRIS_DAMAGE_THRESHOLD then
        self:MissileDoExplosion(); return
    end
    self.HealthVal = self.HealthVal - dmg
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true
    self:StopParticles()

    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 700
    local owner = IsValid(self.NikitaOwner) and self.NikitaOwner or self

    sound.Play("ambient/explosions/explode_8.wav", pos, 100, 100)
    util.ScreenShake(pos, 16, 200, 1, 3000)

    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed)

    local pe = ents.Create("env_physexplosion")
    if IsValid(pe) then
        pe:SetPos(pos)
        pe:SetKeyValue("Magnitude",  tostring(math.floor(dmg * 5)))
        pe:SetKeyValue("radius",     tostring(rad))
        pe:SetKeyValue("spawnflags", "19")
        pe:Spawn(); pe:Activate()
        pe:Fire("Explode", "", 0)
        pe:Fire("Kill",    "", 0.5)
    end

    util.BlastDamage(self, owner, pos + Vector(0,0,50), rad, dmg)
    self:Remove()
end

function ENT:OnRemove()
    self.Destroyed = true
    self:StopParticles()
end
