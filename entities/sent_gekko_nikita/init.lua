AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  Nikita Homing Missile  -  server
--
--  MOVEMENT:   MOVETYPE_NOCLIP + SetAbsVelocity (310 u/s constant)
--  HOMING:     self.TrackEnt (set by spawner)
--
--  SPATIAL AWARENESS SYSTEM:
--
--    Layer 1 - EMERGENCY (< 200 u): dense 26-ray sphere, full deflection.
--              Missile brakes sideways to avoid immediate collision.
--
--    Layer 2 - TACTICAL  (200-600 u): 18-ray forward hemisphere with
--              per-ray repulsion weights.  Closest rays push hardest.
--              Tight corridors are navigated here.
--
--    Layer 3 - STRATEGIC (600-1800 u): 5-ray long-range scout reads the
--              macro geometry; nudges the homing vector before any
--              obstacle becomes Layer 2.
--
--    NavMesh path assist: when the straight line to the target is
--    geometrically blocked (ray hits solid within NAVMESH_SCAN_DIST)
--    the missile samples the nearest NavMesh node toward the target
--    and uses that as a temporary waypoint, giving it natural
--    corridor/doorway routing without a full pathfinder.
--
--    Clearance probe: one perpendicular hull-sweep each tick confirms
--    the missile body fits through the gap it is steering into.
--    If not, it slides along the wall normal instead.
--
--  DETONATION:
--    - Primary sphere (280 u) around aimPos
--    - Secondary sphere (280 u) around raw TrackEnt origin
--    - Fly-past detector: distance growing inside 4x sphere -> detonate
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  TUNING CONSTANTS
-- ─────────────────────────────────────────────────────────────

local CRUISE_SPEED  = 310       -- u/s
local TURN_SPEED    = 9.0       -- base lerp factor /s  (agility)
local TARGET_Z_OFFS = 40
local LIFETIME      = 45
local ENGINE_DELAY  = 0.5
local PROX_RADIUS   = 280

-- Avoidance layer thresholds
local EMERG_DIST    = 200       -- Layer 1 inner boundary
local TACT_DIST     = 600       -- Layer 2 inner boundary / Layer 1 outer
local STRAT_DIST    = 1800      -- Layer 3 outer boundary

-- Repulsion strength per layer (fraction of full deflection)
local EMERG_STRENGTH  = 1.0
local TACT_STRENGTH   = 0.82
local STRAT_STRENGTH  = 0.30

-- When a tactical ray hits closer than this, its weight is doubled
local TACT_CLOSE_BOOST_DIST = 180

-- NavMesh assist
local NAVMESH_SCAN_DIST = 900   -- if forward ray blocked < this, sample navmesh
local NAVMESH_WEIGHT    = 0.55  -- blend between homing dir and navmesh waypoint
local NAVMESH_INTERVAL  = 0.20  -- seconds between navmesh samples (cheap)

-- Corridor mode: entered when both lateral rays (L+R) hit within TACT_DIST.
-- Raises TURN_SPEED and disables strat layer to allow tight threading.
local CORRIDOR_TURN_MULT = 1.6  -- TURN_SPEED multiplier in corridor mode

-- Missile body half-width for clearance probe
local BODY_HALF = 14

-- ─────────────────────────────────────────────────────────────
--  RAY FANS
--  Each entry: { pitch, yaw, layer, weight }
--    pitch/yaw: local missile-space angles (degrees)
--    layer: "emerg", "tact", "strat"
--    weight: relative contribution (1.0 = normal)
-- ─────────────────────────────────────────────────────────────

-- LAYER 1 - EMERGENCY: dense sphere, 26 rays
-- Covers forward hemisphere + full lateral ring + up/down
local RAYS_EMERG = {
    -- Forward
    { 0,    0,    1.2 },
    -- Horizontal ring (every 45 deg)
    { 0,    45,   1.0 }, { 0,   -45,  1.0 },
    { 0,    90,   1.0 }, { 0,   -90,  1.0 },
    { 0,   135,   0.8 }, { 0,  -135,  0.8 },
    { 0,   180,   0.6 },
    -- Vertical
    {-90,   0,    1.0 }, { 90,   0,   1.0 },
    -- Upper ring (pitch -45)
    {-45,   0,    1.0 }, {-45,  90,   0.9 }, {-45, -90,  0.9 },
    {-45,  45,    0.9 }, {-45, -45,   0.9 },
    -- Lower ring (pitch +45)
    { 45,   0,    1.0 }, { 45,  90,   0.9 }, { 45, -90,  0.9 },
    { 45,  45,    0.9 }, { 45, -45,   0.9 },
    -- Tight diagonal spokes
    {-20,  22,    1.0 }, {-20, -22,   1.0 },
    { 20,  22,    1.0 }, { 20, -22,   1.0 },
    -- Straight sides (pure lateral)
    { 0,   22,    1.1 }, { 0,  -22,   1.1 },
}

-- LAYER 2 - TACTICAL: forward hemisphere, 18 rays
-- Tightly spaced; used for corridor threading and doorway entry
local RAYS_TACT = {
    -- Forward center + close flanks (most important for aperture reads)
    { 0,    0,    1.4 },
    { 0,    15,   1.2 }, { 0,  -15,   1.2 },
    { 0,    30,   1.1 }, { 0,  -30,   1.1 },
    { 0,    50,   1.0 }, { 0,  -50,   1.0 },
    { 0,    70,   0.8 }, { 0,  -70,   0.8 },
    -- Vertical spread
    {-15,   0,    1.1 }, { 15,   0,   1.1 },
    {-30,   0,    1.0 }, { 30,   0,   1.0 },
    -- Diagonal quadrant
    {-20,  30,    1.0 }, {-20, -30,   1.0 },
    { 20,  30,    1.0 }, { 20, -30,   1.0 },
    -- Pure lateral (corridor side walls)
    { 0,   90,    0.7 }, { 0,  -90,   0.7 },
}

-- LAYER 3 - STRATEGIC: long-range 5-ray scout
local RAYS_STRAT = {
    { 0,    0,    1.0 },  -- forward
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

-- Cast a single ray in local missile space, return hit distance (or maxDist)
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

-- Weighted repulsion vector from a ray table.
-- Each hit contributes a push-off vector weighted by (1 - dist/maxDist) * rayWeight.
-- Returns: repulsion world vector (not normalised), anyHit bool, minHitDist
local function ComputeRepulsion(ent, origin, rayTable, maxDist, pushDist, filter)
    local repulsion = Vector(0, 0, 0)
    local anyHit    = false
    local minDist   = math.huge

    for _, ray in ipairs(rayTable) do
        local tr, dir = CastLocalRay(ent, origin, ray[1], ray[2], maxDist, filter)
        if tr.Hit then
            local d = (origin - tr.HitPos):Length()
            if d < minDist then minDist = d end

            -- Proximity weight: rays that hit closer push harder
            local proxW = 1.0 - math.Clamp(d / maxDist, 0, 1)
            -- Boost if very close
            if d < TACT_CLOSE_BOOST_DIST then proxW = proxW * 2.0 end

            local totalW = proxW * ray[3]

            -- Push = hit normal + reflected back along ray direction
            local pushDir = tr.HitNormal
            repulsion = repulsion + pushDir * totalW

            anyHit = true
        end
    end

    return repulsion, anyHit, minDist
end

-- Sample the NavMesh for a path-assist waypoint.
-- Returns a world Vector, or nil if navmesh unavailable.
local function NavMeshWaypoint(fromPos, toPos)
    -- Find nearest navmesh area to missile
    local fromArea = navmesh.GetNearestNavArea(fromPos, false, 300, false, false)
    if not fromArea then return nil end

    -- Find nearest navmesh area to target
    local toArea = navmesh.GetNearestNavArea(toPos, false, 300, false, false)
    if not toArea then return nil end

    if fromArea == toArea then
        -- Same area, direct path is fine
        return nil
    end

    -- Get the adjacent area closest to the target direction
    -- navmesh.GetNavAreaByID isn't pathfinding; we use a simple 1-hop heuristic:
    -- pick the neighbor of fromArea whose center is closest to toPos.
    local neighbors = fromArea:GetAdjacentAreas()
    if not neighbors or #neighbors == 0 then return nil end

    local bestDist = math.huge
    local bestPos  = nil
    for _, area in ipairs(neighbors) do
        local center = area:GetCenter()
        -- Only consider areas roughly toward the target
        local d = (center - toPos):LengthSqr()
        if d < bestDist then
            bestDist = d
            bestPos  = center + Vector(0, 0, 40) -- eye height
        end
    end

    return bestPos
end

-- Clearance probe: sweeps a hull perpendicular to moveDir to see if the
-- missile BODY (not just the center ray) fits in the gap ahead.
-- Returns: fits (bool), slide vector (if not fits, direction to slide along wall)
local function ClearanceProbe(origin, moveDir, filter)
    -- Build two perpendicular probe offsets (up and right relative to moveDir)
    local ang   = moveDir:Angle()
    local right = ang:Right()
    local up    = ang:Up()

    local probeLen = 80  -- distance ahead to check
    local probeEnd = origin + moveDir * probeLen

    local function sweep(offset)
        return util.TraceHull({
            start  = origin + offset,
            endpos = probeEnd + offset,
            mins   = Vector(-BODY_HALF, -BODY_HALF, -BODY_HALF),
            maxs   = Vector( BODY_HALF,  BODY_HALF,  BODY_HALF),
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })
    end

    local trC = sweep(Vector(0,0,0))
    if not trC.Hit then return true, nil end

    -- Blocked - try to find a slide direction along the hit normal
    local normal = trC.HitNormal
    local slide  = moveDir - normal * moveDir:Dot(normal)
    if slide:LengthSqr() < 0.001 then slide = up end  -- fallback: go up
    slide:Normalize()
    return false, slide
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

    -- Fly-past detector
    self._prevDistSqr  = math.huge

    -- NavMesh assist state
    self._navWaypoint  = nil
    self._nextNavSample = 0

    -- Spawner sets:
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

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if not self.EngineActive then return true end

    local myPos      = self:GetPos()
    local currentDir = self:GetForward()
    local filter     = { self, IsValid(self.NikitaOwner) and self.NikitaOwner or self }

    -- ═══ 1. HOMING TARGET ═══════════════════════════════════════
    local aimPos = GetAimPos(self.TrackEnt, self.FallbackTarget)

    -- ═══ 2. PROXIMITY DETONATION ════════════════════════════════
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

        -- Fly-past: distance growing inside 4x prox gate
        local gate = (PROX_RADIUS * 4) * (PROX_RADIUS * 4)
        if distSqr > self._prevDistSqr and distSqr < gate then
            self:MissileDoExplosion(); return true
        end
        self._prevDistSqr = distSqr
    else
        self._prevDistSqr = math.huge
    end

    -- ═══ 3. THREE-LAYER SPATIAL AWARENESS ═══════════════════════

    local noseTip = myPos + currentDir * 20

    -- Layer 1 - Emergency (< EMERG_DIST)
    local emergRepulsion, emergHit, emergMin =
        ComputeRepulsion(self, noseTip, RAYS_EMERG, EMERG_DIST, EMERG_DIST * 0.5, filter)

    -- Layer 2 - Tactical (< TACT_DIST)
    local tactRepulsion, tactHit, tactMin =
        ComputeRepulsion(self, noseTip, RAYS_TACT, TACT_DIST, TACT_DIST * 0.5, filter)

    -- Layer 3 - Strategic (< STRAT_DIST) - skip in corridor mode (see below)
    local stratRepulsion, stratHit = Vector(0,0,0), false

    -- Corridor detection: both pure-lateral tact rays hit close
    local trL, _ = CastLocalRay(self, noseTip,  0,  90, TACT_DIST, filter)
    local trR, _ = CastLocalRay(self, noseTip,  0, -90, TACT_DIST, filter)
    local inCorridor = trL.Hit and trR.Hit
        and (noseTip - trL.HitPos):Length() < TACT_DIST
        and (noseTip - trR.HitPos):Length() < TACT_DIST

    local activeTurnSpeed = TURN_SPEED
    if inCorridor then
        -- Tighter turns, no long-range distraction
        activeTurnSpeed = TURN_SPEED * CORRIDOR_TURN_MULT
    else
        stratRepulsion, stratHit =
            ComputeRepulsion(self, noseTip, RAYS_STRAT, STRAT_DIST, STRAT_DIST * 0.3, filter)
    end

    -- ═══ 4. NAVMESH PATH ASSIST ══════════════════════════════════
    -- Periodically sample navmesh when the direct path is obstructed
    local useNavWaypoint = false
    if aimPos and CurTime() >= self._nextNavSample then
        self._nextNavSample = CurTime() + NAVMESH_INTERVAL

        -- Quick forward ray to see if the line to target is blocked
        local fwdToTarget = (aimPos - myPos):GetNormalized()
        local navCheck = util.TraceLine({
            start  = myPos,
            endpos = myPos + fwdToTarget * NAVMESH_SCAN_DIST,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })

        if navCheck.Hit then
            -- Direct path blocked - ask navmesh for a detour waypoint
            local wp = NavMeshWaypoint(myPos, aimPos)
            self._navWaypoint = wp  -- may be nil if navmesh absent
        else
            -- Clear path - discard any stale waypoint
            self._navWaypoint = nil
        end
    end

    -- ═══ 5. COMPOSE STEERING DIRECTION ══════════════════════════

    -- Start with pure homing direction
    local homingDir = aimPos and (aimPos - myPos):GetNormalized() or currentDir

    -- If navmesh gave us a waypoint, blend homing toward it
    if aimPos and self._navWaypoint then
        local navDir = (self._navWaypoint - myPos):GetNormalized()
        homingDir = LerpVector(NAVMESH_WEIGHT, homingDir, navDir)
        homingDir:Normalize()
        useNavWaypoint = true
    end

    -- Accumulate repulsion vectors scaled by layer strength
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

    -- Final desired direction: homing deflected by repulsion
    local desiredDir
    local repLen = totalRepulsion:Length()
    if repLen > 0.01 then
        -- Emergency overrides completely; others blend
        local blendFactor
        if emergHit and emergMin < EMERG_DIST then
            -- Full emergency deflection - missile survival over homing
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

    -- ═══ 6. CLEARANCE PROBE - fit check ══════════════════════════
    local fits, slideDir = ClearanceProbe(myPos, desiredDir, filter)
    if not fits and slideDir then
        -- Slide along wall rather than punch through it
        desiredDir = LerpVector(0.7, desiredDir, slideDir)
        desiredDir:Normalize()
    end

    -- ═══ 7. APPLY TURN + VELOCITY ════════════════════════════════
    local moveDir = LerpVector(FrameTime() * activeTurnSpeed, currentDir, desiredDir)
    moveDir:Normalize()

    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    -- ═══ 8. AHEAD HULL TRACE (instant collision) ═════════════════
    local stepDist = CRUISE_SPEED * FrameTime() + 16
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
            self:MissileDoExplosion(); return true
        end
        if IsValid(tr.Entity) and tr.Entity ~= self.NikitaOwner then
            self:MissileDoExplosion(); return true
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
    self:MissileDoExplosion()
end

function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
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
