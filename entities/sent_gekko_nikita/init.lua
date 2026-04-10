AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  Nikita Homing Missile  -  server
--  v4.1 - syntax fix: GetVelocity method guard
-- ============================================================

-- ---------------------------------------------------------
--  TUNING CONSTANTS
-- ---------------------------------------------------------

local CRUISE_SPEED  = 310
local TURN_SPEED    = 9.0
local TARGET_Z_OFFS = 40
local LIFETIME      = 45
local ENGINE_DELAY  = 0.5
local PROX_RADIUS   = 280

local MISSILE_HP              = 50
local DEBRIS_DAMAGE_THRESHOLD = 8

local EMERG_DIST    = 200
local TACT_DIST     = 600
local STRAT_DIST    = 1800

local EMERG_STRENGTH  = 1.0
local TACT_STRENGTH   = 0.82
local STRAT_STRENGTH  = 0.30

local TACT_CLOSE_BOOST_DIST = 180
local CORRIDOR_TURN_MULT    = 1.6
local BODY_HALF             = 14

local LEAD_TIME          = 0.55
local LAST_KNOWN_TIMEOUT = 4.0

-- ---------------------------------------------------------
--  PATHFINDING CONSTANTS
-- ---------------------------------------------------------

local PATHFIND_INTERVAL  = 0.5

local SCOUT_RAY_DIST     = 2000
local PATH_BLEND_NORMAL  = 0.70
local PATH_BLEND_LOCKED  = 0.96
local SCORE_ANGLE_WEIGHT = 1.5
local SCORE_DIST_WEIGHT  = 1.0
local SCORE_APT_BONUS    = 4.0

local SLAB_COARSE_HALF = 1000
local SLAB_COARSE_STEP = 100
local SLAB_FINE_HALF   = 80
local SLAB_FINE_STEP   = 36
local SLAB_PROBE_LEN   = 160
local SLAB_EXIT_FRAC   = 0.6

local APERTURE_REACHED_DIST = 120
local WAYPOINT_MAX          = 2

local SCOUT_RAYS = {
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
    { 90,   0 }, {-90,   0 },
    { 45,   0 }, {-45,   0 }, { 45, 180 }, {-45, 180 },
    { 45,  90 }, { 45, -90 }, {-45,  90 }, {-45, -90 },
}

-- ---------------------------------------------------------
--  COLLISION RESILIENCE CONSTANTS
-- ---------------------------------------------------------

local ARMOR_MAX            = 8
local BUMP_COOLDOWN        = 0.15
local ARMOR_REGEN_AMOUNT   = 1
local ARMOR_REGEN_INTERVAL = 2.0
local STREAK_MAX           = 7
local STREAK_WINDOW        = 1.5
local WALL_KICK_STRENGTH   = 0.6
local PROP_MASS_LIMIT      = 80
local PROP_KNOCKBACK       = 28000

-- ---------------------------------------------------------
--  REACTIVE RAY FANS
-- ---------------------------------------------------------

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

-- ---------------------------------------------------------
--  HELPERS
-- ---------------------------------------------------------

-- Safe velocity fetch: works for players, NPCs, props, anything
local function GetEntVelocity(ent)
    if ent.GetVelocity then
        return ent:GetVelocity()
    end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        return phys:GetVelocity()
    end
    return Vector(0, 0, 0)
end

-- Predictive aim position with last-known-pos fallback
local function GetAimPos(self)
    local trackEnt = self.TrackEnt
    if IsValid(trackEnt) then
        local p   = trackEnt:GetPos()
        local vel = GetEntVelocity(trackEnt)
        self._lastKnownPos  = Vector(p.x, p.y, p.z + TARGET_Z_OFFS)
        self._lastKnownVel  = vel
        self._lastKnownTime = CurTime()
        return Vector(
            p.x + vel.x * LEAD_TIME,
            p.y + vel.y * LEAD_TIME,
            p.z + TARGET_Z_OFFS + vel.z * LEAD_TIME
        )
    end
    -- Extrapolate from last known position
    if self._lastKnownPos and self._lastKnownTime then
        local age = CurTime() - self._lastKnownTime
        if age < LAST_KNOWN_TIMEOUT then
            local lkv = self._lastKnownVel or Vector(0, 0, 0)
            return self._lastKnownPos + lkv * age
        end
    end
    return self.FallbackTarget
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

-- ---------------------------------------------------------
--  TWO-PASS WIDE SLAB APERTURE SCANNER
-- ---------------------------------------------------------
local function WideSlabScan(hitPos, hitNormal, missilePos, aimPos, filter)
    local right, tang = BuildTangents(hitNormal)
    local wallOrigin  = hitPos + hitNormal * (BODY_HALF + 8)
    local probeDir    = -hitNormal
    local toTarget    = (aimPos - hitPos):GetNormalized()

    -- Pass 1: coarse quick-line scan
    local bestCoarseScore = -math.huge
    local bestCoarsePt    = nil

    for row = -SLAB_COARSE_HALF, SLAB_COARSE_HALF, SLAB_COARSE_STEP do
        for col = -SLAB_COARSE_HALF, SLAB_COARSE_HALF, SLAB_COARSE_STEP do
            local pt  = wallOrigin + right * col + tang * row
            local qTr = util.TraceLine({
                start  = pt,
                endpos = pt + probeDir * SLAB_PROBE_LEN,
                mask   = MASK_SOLID_BRUSHONLY,
                filter = filter,
            })
            if not qTr.Hit then
                local aptToTarget = (aimPos - pt):GetNormalized()
                local progressDot = aptToTarget:Dot(-hitNormal)
                local missileToPt = (pt - missilePos):GetNormalized()
                local approachDot = math.max(0, missileToPt:Dot(toTarget))
                local zScore      = 1.0 - math.Clamp(math.abs(pt.z - missilePos.z) / 500, 0, 1)
                local score = progressDot * 2.0 + approachDot * 1.5 + zScore * 0.8
                if score > bestCoarseScore then
                    bestCoarseScore = score
                    bestCoarsePt    = pt
                end
            end
        end
    end

    if not bestCoarsePt then return nil, nil end

    -- Pass 2: fine hull-sweep around best coarse point
    local bestFineScore = -math.huge
    local bestFinePoint = nil

    for row = -SLAB_FINE_HALF, SLAB_FINE_HALF, SLAB_FINE_STEP do
        for col = -SLAB_FINE_HALF, SLAB_FINE_HALF, SLAB_FINE_STEP do
            local pt      = bestCoarsePt + right * col + tang * row
            local _, fits = BodyFits(pt, probeDir, SLAB_PROBE_LEN, filter)
            if fits then
                local aptToTarget = (aimPos - pt):GetNormalized()
                local progressDot = aptToTarget:Dot(-hitNormal)
                local missileToPt = (pt - missilePos):GetNormalized()
                local approachDot = math.max(0, missileToPt:Dot(toTarget))
                local zScore      = 1.0 - math.Clamp(math.abs(pt.z - missilePos.z) / 500, 0, 1)
                local score = progressDot * 2.0 + approachDot * 1.5 + zScore * 0.8
                if score > bestFineScore then
                    bestFineScore = score
                    bestFinePoint = pt
                end
            end
        end
    end

    local finalPt = bestFinePoint or bestCoarsePt
    local exitPt  = finalPt + probeDir * (SLAB_PROBE_LEN * SLAB_EXIT_FRAC)
    return exitPt, hitNormal
end

-- ---------------------------------------------------------
--  WAYPOINT-CHAIN PATHFINDER
-- ---------------------------------------------------------
local function ScanAhead(myPos, aimPos, filter)
    local directTr = util.TraceHull({
        start  = myPos,
        endpos = aimPos,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if not directTr.Hit then return nil, nil end
    return WideSlabScan(directTr.HitPos, directTr.HitNormal, myPos, aimPos, filter)
end

local function RebuildWaypoints(self, myPos, aimPos, filter)
    self._waypoints = {}
    self._wpIndex   = 1
    self._aptLocked = false
    self._pathDir   = nil

    local wp1Pos, wp1Normal = ScanAhead(myPos, aimPos, filter)
    if not wp1Pos then return end

    local tr1 = util.TraceLine({
        start  = myPos,
        endpos = wp1Pos,
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if tr1.Hit then return end

    self._waypoints[1] = { pos = wp1Pos, normal = wp1Normal }

    if WAYPOINT_MAX < 2 then return end

    local wp2Pos, wp2Normal = ScanAhead(wp1Pos, aimPos, filter)
    if not wp2Pos then return end

    local tr2 = util.TraceLine({
        start  = wp1Pos,
        endpos = wp2Pos,
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if not tr2.Hit then
        self._waypoints[2] = { pos = wp2Pos, normal = wp2Normal }
    end
end

local function UpdatePath(self, myPos, aimPos, filter)
    if not aimPos then
        self._waypoints = {}
        self._wpIndex   = 1
        self._aptLocked = false
        self._pathDir   = nil
        return
    end

    -- Advance through existing waypoints
    if self._waypoints and #self._waypoints > 0 then
        local wp = self._waypoints[self._wpIndex]
        if wp then
            if (myPos - wp.pos):Length() < APERTURE_REACHED_DIST then
                self._wpIndex = self._wpIndex + 1
                wp = self._waypoints[self._wpIndex]
                if not wp then
                    self._waypoints = {}
                    self._aptLocked = false
                    self._pathDir   = nil
                    return
                end
            end
            local verTr = util.TraceLine({
                start  = myPos,
                endpos = wp.pos,
                mask   = MASK_SOLID_BRUSHONLY,
                filter = filter,
            })
            if not verTr.Hit then
                local toWp    = (wp.pos - myPos):GetNormalized()
                local aligned = LerpVector(0.35, toWp, -wp.normal)
                aligned:Normalize()
                self._pathDir   = aligned
                self._aptLocked = true
                return
            end
            -- Waypoint occluded, fall through to rebuild
        end
    end

    -- Check direct path
    local directTr = util.TraceHull({
        start  = myPos,
        endpos = aimPos,
        mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
        maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = filter,
    })
    if not directTr.Hit then
        self._waypoints = {}
        self._aptLocked = false
        self._pathDir   = nil
        return
    end

    RebuildWaypoints(self, myPos, aimPos, filter)

    if self._waypoints and self._waypoints[1] then
        local wp      = self._waypoints[1]
        local toWp    = (wp.pos - myPos):GetNormalized()
        local aligned = LerpVector(0.35, toWp, -wp.normal)
        aligned:Normalize()
        self._pathDir   = aligned
        self._aptLocked = true
        return
    end

    -- Fallback: best scout ray
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

-- ---------------------------------------------------------
--  CLEARANCE PROBE
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
--  COLLISION RESILIENCE HELPERS
-- ---------------------------------------------------------

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

-- ---------------------------------------------------------
--  ENTITY LIFECYCLE
-- ---------------------------------------------------------

function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_launch.mdl")
    self:SetModelScale(7, 0)
    self:SetMoveType(MOVETYPE_NOCLIP)

    self:SetSolid(SOLID_BBOX)
    self:PhysicsInit(SOLID_BBOX)
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:SetHealth(MISSILE_HP)
    self:SetMaxHealth(MISSILE_HP)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:EnableGravity(false)
        phys:Sleep()
    end

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = MISSILE_HP
    self.Damage       = 0
    self.Radius       = 0

    self._prevDistSqr = math.huge

    self._lastKnownPos  = nil
    self._lastKnownVel  = nil
    self._lastKnownTime = nil

    self._waypoints    = {}
    self._wpIndex      = 1
    self._pathDir      = nil
    self._aptLocked    = false
    self._nextPathTime = 0

    self.ArmorHP        = ARMOR_MAX
    self._lastBumpTime  = -999
    self._bumpStreak    = 0
    self._streakStart   = CurTime()
    self._nextArmorRegen= CurTime() + ARMOR_REGEN_INTERVAL

    self:SetNWFloat("NikitaBoost", 0)
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

-- ---------------------------------------------------------
--  THINK
-- ---------------------------------------------------------

function ENT:Think()
    self:NextThink(CurTime())
    if self.Destroyed then return true end

    local now = CurTime()
    local dt  = math.max(FrameTime(), 0.001)

    if now - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion(); return true
    end

    if not self.EngineActive then return true end

    if now >= self._nextArmorRegen then
        self._nextArmorRegen = now + ARMOR_REGEN_INTERVAL
        self.ArmorHP = math.min(self.ArmorHP + ARMOR_REGEN_AMOUNT, ARMOR_MAX)
    end

    local myPos      = self:GetPos()
    local currentDir = self:GetForward()
    local filter     = { self, IsValid(self.NikitaOwner) and self.NikitaOwner or self }

    local aimPos = GetAimPos(self)

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

    if now >= self._nextPathTime then
        self._nextPathTime = now + PATHFIND_INTERVAL
        UpdatePath(self, myPos, aimPos, filter)
    end

    local noseTip = myPos + currentDir * 20

    local emergRepulsion, emergHit, emergMin =
        ComputeRepulsion(self, noseTip, RAYS_EMERG, EMERG_DIST, EMERG_DIST * 0.5, filter)
    local tactRepulsion, tactHit, tactMin =
        ComputeRepulsion(self, noseTip, RAYS_TACT, TACT_DIST, TACT_DIST * 0.5, filter)

    local stratRepulsion, stratHit = Vector(0, 0, 0), false

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

    local rawHomingDir = aimPos and (aimPos - myPos):GetNormalized() or currentDir
    local pathBlend    = self._aptLocked and PATH_BLEND_LOCKED or PATH_BLEND_NORMAL
    local homingDir    = rawHomingDir
    if self._pathDir then
        homingDir = LerpVector(pathBlend, rawHomingDir, self._pathDir)
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
        if self._aptLocked and not (emergHit and emergMin < EMERG_DIST) then
            blendFactor = blendFactor * 0.4
        end
        desiredDir = LerpVector(blendFactor, homingDir, totalRepulsion:GetNormalized())
        desiredDir:Normalize()
    else
        desiredDir = homingDir
    end

    local fits, slideDir = ClearanceProbe(myPos, desiredDir, filter)
    if not fits and slideDir then
        desiredDir = LerpVector(0.7, desiredDir, slideDir)
        desiredDir:Normalize()
    end

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
                -- ignore owner
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

-- ---------------------------------------------------------
--  TOUCH / DAMAGE / EXPLOSION
-- ---------------------------------------------------------

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

    util.BlastDamage(self, owner, pos + Vector(0, 0, 50), rad, dmg)
    self:Remove()
end

function ENT:OnRemove()
    self.Destroyed = true
    self:StopParticles()
end
