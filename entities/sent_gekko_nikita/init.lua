AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  Nikita Homing Missile  -  server
--  v2 – Omniscient 3D Pathfinder Edition
--
--  MOVEMENT:    MOVETYPE_NOCLIP + SetAbsVelocity (310 u/s constant)
--  HOMING:      self.TrackEnt (set by spawner)
--
-- ┌──────────────────────────────────────────────────────────
-- │  PATHFINDING – "APERTURE SEEKER"                        │
-- │                                                          │
-- │  Every PATHFIND_INTERVAL seconds the missile builds a    │
-- │  lightweight path:                                       │
-- │    1. Cast a ray from self → target.                     │
-- │       If clear  → direct path, no waypoint needed.       │
-- │    2. If blocked, fire a hemi-sphere of SCOUT_RAYS rays  │
-- │       from the missile. Each ray is scored:              │
-- │         + angular proximity to target                    │
-- │         + distance remaining clear                       │
-- │         + aperture width (hull-sweep to check if Nikita  │
-- │           body fits through each candidate opening)      │
-- │    3. Best-scoring open direction becomes _pathDir.      │
-- │    4. Additional GAP_RAYS spiral pattern scans for       │
-- │       apertures (doors/windows) in the wall that blocked │
-- │       the direct path; if found, _pathDir biases toward  │
-- │       the aperture centre.                               │
-- │                                                          │
-- │  SPATIAL AWARENESS  (reactive, every Think tick)         │
-- │    Layer 1 – EMERGENCY  (<200 u)  : 26-ray dense sphere  │
-- │    Layer 2 – TACTICAL   (200-600 u): 18-ray hemisphere   │
-- │    Layer 3 – STRATEGIC  (600-1800 u): 5-ray scout        │
-- │                                                          │
-- │  COLLISION RESILIENCE                                    │
-- │    ArmorHP, wall-kick, BumpStreak, prop knockback        │
-- │    (unchanged from v1; see constants below)              │
-- └──────────────────────────────────────────────────────────
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  TUNING CONSTANTS
-- ─────────────────────────────────────────────────────────────

local CRUISE_SPEED  = 310
local TURN_SPEED    = 9.0          -- rad/s equivalent (time-based, not frame-based)
local TARGET_Z_OFFS = 40
local LIFETIME      = 45
local ENGINE_DELAY  = 0.5
local PROX_RADIUS   = 280

-- Avoidance layer thresholds
local EMERG_DIST    = 200
local TACT_DIST     = 600
local STRAT_DIST    = 1800

-- Repulsion strength per layer
local EMERG_STRENGTH  = 1.0
local TACT_STRENGTH   = 0.82
local STRAT_STRENGTH  = 0.30

local TACT_CLOSE_BOOST_DIST = 180

-- Corridor mode
local CORRIDOR_TURN_MULT = 1.6

-- Missile body half-width for clearance probes
local BODY_HALF = 14

-- ─────────────────────────────────────────────────────────────
--  PATHFINDING CONSTANTS
-- ─────────────────────────────────────────────────────────────

-- How often to recompute the 3-D path (seconds)
local PATHFIND_INTERVAL  = 0.15

-- How far ahead each scout ray reaches when building the path
local SCOUT_RAY_DIST     = 900

-- Weight given to path direction vs raw homing (0..1)
-- Higher = missile prioritises finding gaps over bee-lining to target
local PATH_BLEND         = 0.70

-- Angular cost: penalise directions far from the target angle
local SCORE_ANGLE_WEIGHT = 2.0
-- Distance score: reward rays that stay open further
local SCORE_DIST_WEIGHT  = 1.0
-- Aperture bonus: reward directions where the missile body fits
local SCORE_APT_BONUS    = 3.0

-- Scout ray fan (pitch, yaw) offsets – hemisphere forward + up/down arcs
-- These 37 rays are only cast during the path-update interval, not every tick.
local SCOUT_RAYS = {
    {  0,   0 },
    {  0,  20 }, {  0, -20 }, {  0,  40 }, {  0, -40 },
    {  0,  60 }, {  0, -60 }, {  0,  80 }, {  0, -80 },
    {  0, 100 }, {  0,-100 }, {  0, 120 }, {  0,-120 },
    { 20,   0 }, {-20,   0 }, { 30,   0 }, {-30,   0 },
    { 45,   0 }, {-45,   0 },
    { 20,  30 }, { 20, -30 }, {-20,  30 }, {-20, -30 },
    { 30,  45 }, { 30, -45 }, {-30,  45 }, {-30, -45 },
    { 15,  60 }, { 15, -60 }, {-15,  60 }, {-15, -60 },
    { 45,  45 }, { 45, -45 }, {-45,  45 }, {-45, -45 },
    { 10,  10 }, {-10, -10 },
}

-- How many aperture-search rays to fire inside the blocking wall plane
-- when the direct path is blocked.  Arranged as a 2-D grid spanning
-- APERTURE_GRID_HALF rows/cols on each side of the hit point.
local APERTURE_GRID_HALF = 3     -- rows/cols each side of centre
local APERTURE_STEP      = 28    -- units between grid points (approx 2x BODY_HALF)
local APERTURE_PROBE_LEN = 80    -- length of each grid probe

-- ─────────────────────────────────────────────────────────────
--  COLLISION RESILIENCE CONSTANTS
-- ─────────────────────────────────────────────────────────────

local ARMOR_MAX           = 8
local BUMP_COOLDOWN       = 0.15
local ARMOR_REGEN_AMOUNT  = 1
local ARMOR_REGEN_INTERVAL= 2.0
local STREAK_MAX          = 7        -- raised from 5 (less hair-trigger in tight gaps)
local STREAK_WINDOW       = 1.5
local WALL_KICK_STRENGTH  = 0.6
local PROP_MASS_LIMIT     = 80
local PROP_KNOCKBACK      = 28000
local DEBRIS_DAMAGE_THRESHOLD = 15

-- ─────────────────────────────────────────────────────────────
--  RAY FANS  (reactive, every tick)
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

            local totalW  = proxW * ray[3]
            local pushDir = tr.HitNormal
            repulsion     = repulsion + pushDir * totalW
            anyHit        = true
        end
    end

    return repulsion, anyHit, minDist
end

-- Body-fitting clearance check: hull-trace along dir for len units.
-- Returns open distance (full len if unblocked) and whether it fits.
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
    local d = (origin - tr.HitPos):Length()
    return d, false
end

-- ─────────────────────────────────────────────────────────────
--  APERTURE DETECTOR
--
--  Given the world position of a wall-hit and the wall normal,
--  scan a grid of points across the wall face and probe each with
--  a short hull-trace to find openings (doors / windows).
--
--  Returns: best aperture centre (Vector) or nil
-- ─────────────────────────────────────────────────────────────
local function FindAperture(hitPos, hitNormal, filter)
    -- Build two tangent axes perpendicular to the normal
    local up    = Vector(0, 0, 1)
    local right = hitNormal:Cross(up)
    if right:LengthSqr() < 0.001 then
        right = hitNormal:Cross(Vector(1, 0, 0))
    end
    right:Normalize()
    local tang  = right:Cross(hitNormal)
    tang:Normalize()

    -- Probe origin: step slightly back from the wall so we start in open air
    local probeOrigin = hitPos + hitNormal * (BODY_HALF + 4)

    local bestPos   = nil
    local bestScore = -1

    for row = -APERTURE_GRID_HALF, APERTURE_GRID_HALF do
        for col = -APERTURE_GRID_HALF, APERTURE_GRID_HALF do
            local offset = right * (col * APERTURE_STEP) + tang * (row * APERTURE_STEP)
            local pt     = probeOrigin + offset

            -- Hull-probe in the direction of travel (into the wall)
            local probeDir = -hitNormal
            local openDist, fits = BodyFits(pt, probeDir, APERTURE_PROBE_LEN, filter)

            if fits then
                -- Score: prefer cells close to the centre of the grid
                local centreDist = math.sqrt(row*row + col*col)
                local score = APERTURE_PROBE_LEN - centreDist * APERTURE_STEP * 0.5
                if score > bestScore then
                    bestScore = score
                    bestPos   = pt
                end
            end
        end
    end

    return bestPos  -- nil if no opening found
end

-- ─────────────────────────────────────────────────────────────
--  3-D SCOUT PATHFINDER
--
--  Called every PATHFIND_INTERVAL seconds.
--  Sets self._pathDir (normalised Vector) or nil (direct path clear).
-- ─────────────────────────────────────────────────────────────
local function UpdatePath(self, myPos, aimPos, filter)
    if not aimPos then
        self._pathDir      = nil
        self._apertureHint = nil
        return
    end

    local toTarget = (aimPos - myPos):GetNormalized()

    -- Step 1: is the direct path clear?
    local directTr = util.TraceHull({
        start  = myPos,
        endpos = aimPos,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })

    if not directTr.Hit then
        self._pathDir      = nil
        self._apertureHint = nil
        return
    end

    -- Step 2: scan for best open direction via scored scout rays
    local bestScore = -math.huge
    local bestDir   = nil

    for _, ray in ipairs(SCOUT_RAYS) do
        local dir = self:LocalToWorldAngles(Angle(ray[1], ray[2], 0)):Forward()

        local openDist, fits = BodyFits(myPos, dir, SCOUT_RAY_DIST, filter)

        -- Angular score: how close is this direction to the target?
        local dot = math.max(0, dir:Dot(toTarget))

        -- Distance score: further clear = better
        local distScore = openDist / SCOUT_RAY_DIST

        -- Aperture bonus: reward directions where the body fits
        local aptBonus = fits and SCORE_APT_BONUS or 0

        local score = SCORE_ANGLE_WEIGHT * dot + SCORE_DIST_WEIGHT * distScore + aptBonus

        if score > bestScore then
            bestScore = score
            bestDir   = dir
        end
    end

    -- Step 3: aperture search in the blocking wall
    local apertureHint = FindAperture(directTr.HitPos, directTr.HitNormal, filter)
    self._apertureHint = apertureHint

    -- If we found an aperture, strongly bias bestDir toward it
    if apertureHint then
        local toApt = (apertureHint - myPos):GetNormalized()
        local aptTr = util.TraceLine({
            start  = myPos,
            endpos = apertureHint,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })
        if not aptTr.Hit then
            -- Unobstructed path to the aperture: strongly bias toward it
            bestDir = LerpVector(0.80, bestDir or toApt, toApt)
            bestDir:Normalize()
        end
    end

    self._pathDir = bestDir
end

-- ─────────────────────────────────────────────────────────────
--  CLEARANCE PROBE  (immediate obstacle slide)
-- ─────────────────────────────────────────────────────────────
local function ClearanceProbe(origin, moveDir, filter)
    local probeLen = 80
    local probeEnd = origin + moveDir * probeLen

    local trC = util.TraceHull({
        start  = origin,
        endpos = probeEnd,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })

    if not trC.Hit then return true, nil end

    local normal = trC.HitNormal
    local slide  = moveDir - normal * moveDir:Dot(normal)
    if slide:LengthSqr() < 0.001 then
        -- Improved fallback: pick the tangent axis most aligned with moveDir
        local up    = Vector(0, 0, 1)
        local tangA = normal:Cross(up); tangA:Normalize()
        local tangB = normal:Cross(tangA); tangB:Normalize()
        slide = math.abs(tangA:Dot(moveDir)) >= math.abs(tangB:Dot(moveDir)) and tangA or tangB
    end
    slide:Normalize()
    return false, slide
end

-- ─────────────────────────────────────────────────────────────
--  COLLISION RESILIENCE HELPERS
-- ─────────────────────────────────────────────────────────────

local function BumpArmor(self, now)
    if now - self._lastBumpTime < BUMP_COOLDOWN then
        return false
    end

    self._lastBumpTime = now
    self.ArmorHP = self.ArmorHP - 1

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
    local mass = phys:GetMass()
    if mass < PROP_MASS_LIMIT then
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

    self.Destroyed     = false
    self.EngineActive  = false
    self.SpawnTime     = CurTime()
    self.HealthVal     = 50
    self.Damage        = 0
    self.Radius        = 0

    self._prevDistSqr  = math.huge

    -- 3-D path state
    self._pathDir       = nil
    self._apertureHint  = nil
    self._nextPathTime  = 0

    -- Collision resilience state
    self.ArmorHP        = ARMOR_MAX
    self._lastBumpTime  = -999
    self._bumpStreak    = 0
    self._streakStart   = CurTime()
    self._nextArmorRegen= CurTime() + ARMOR_REGEN_INTERVAL

    -- NWFloat for client visual boost
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
        self:MissileDoExplosion()
        return true
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
            local rawDistSqr = (myPos - self.TrackEnt:GetPos()):LengthSqr()
            if rawDistSqr < PROX_RADIUS * PROX_RADIUS then
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

    -- 3. 3-D OMNISCIENT PATH UPDATE
    if now >= self._nextPathTime then
        self._nextPathTime = now + PATHFIND_INTERVAL
        UpdatePath(self, myPos, aimPos, filter)
    end

    -- 4. THREE-LAYER SPATIAL AWARENESS
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

    -- Blend with 3-D path direction when one exists
    local homingDir = rawHomingDir
    if self._pathDir then
        homingDir = LerpVector(PATH_BLEND, rawHomingDir, self._pathDir)
        homingDir:Normalize()
    end

    local totalRepulsion = Vector(0, 0, 0)
    if emergHit then
        local n = emergRepulsion:Length()
        if n > 0 then totalRepulsion = totalRepulsion + (emergRepulsion / n) * EMERG_STRENGTH end
    end
    if tactHit then
        local n = tactRepulsion:Length()
        if n > 0 then totalRepulsion = totalRepulsion + (tactRepulsion / n) * TACT_STRENGTH end
    end
    if stratHit then
        local n = stratRepulsion:Length()
        if n > 0 then totalRepulsion = totalRepulsion + (stratRepulsion / n) * STRAT_STRENGTH end
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

    -- 7. APPLY TURN + VELOCITY  (time-based, FPS-independent angle-clamped slerp)
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

    -- Signal client particles: boost glow when actively pathfinding around obstacles
    self:SetNWFloat("NikitaBoost", self._pathDir and 1 or 0)

    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    -- 8. AHEAD HULL TRACE - collision resilience
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
            if shouldDetonate then
                self:MissileDoExplosion(); return true
            end
            WallKick(self, tr.HitNormal)

        elseif IsValid(tr.Entity) then
            local ent = tr.Entity
            if ent == self.NikitaOwner then
                -- ignore owner
            elseif ent:IsPlayer() or ent:IsNPC() then
                self:MissileDoExplosion(); return true
            else
                local knocked = HandlePropContact(self, ent)
                if not knocked then
                    self:MissileDoExplosion(); return true
                end
                local shouldDetonate = BumpArmor(self, now)
                if shouldDetonate then
                    self:MissileDoExplosion(); return true
                end
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
        self:MissileDoExplosion()
        return
    end

    local shouldDetonate = BumpArmor(self, CurTime())
    if shouldDetonate then
        self:MissileDoExplosion()
    end
end

function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end

    local dmg = dmginfo:GetDamage()

    if dmg >= DEBRIS_DAMAGE_THRESHOLD then
        self:MissileDoExplosion()
        return
    end

    self.HealthVal = self.HealthVal - dmg
    if self.HealthVal <= 0 then
        self:MissileDoExplosion()
    end
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
