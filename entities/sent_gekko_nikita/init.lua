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
--    Layer 1 - EMERGENCY (< 200 u): dense 26-ray sphere, full deflection.
--    Layer 2 - TACTICAL  (200-600 u): 18-ray forward hemisphere.
--    Layer 3 - STRATEGIC (600-1800 u): 5-ray long-range scout.
--    NavMesh path assist: 1-hop waypoint when direct path blocked.
--    Clearance probe: hull-sweep to fit through gaps.
--
--  COLLISION RESILIENCE SYSTEM:
--    self.ArmorHP       = separate hit pool for world/brush collisions.
--    Wall-kick          = on brush hit, reflect off normal and continue.
--    BumpCooldown       = min 0.15s between armor drains (scrape protection).
--    ArmorHP regen      = +1 every ARMOR_REGEN_INTERVAL seconds.
--    BumpStreak         = consecutive bumps within STREAK_WINDOW seconds.
--                         > STREAK_MAX bumps → detonate (grinding prevention).
--    Debris/props       = light props (mass < PROP_MASS_LIMIT) get knocked aside.
--                         heavy props/NPCs → detonate on contact.
--    OnTakeDamage       = damage > DEBRIS_DAMAGE_THRESHOLD → detonate
--                         (player fire, explosions, interactive debris).
--                         lighter hits are absorbed by HealthVal only.
--
--  DETONATION:
--    - Primary sphere (280 u) around aimPos
--    - Secondary sphere (280 u) around raw TrackEnt origin
--    - Fly-past detector: distance growing inside 4x sphere -> detonate
--    - ArmorHP <= 0 (sustained grinding)
--    - BumpStreak > STREAK_MAX (corner-hugging)
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

-- Avoidance layer thresholds
local EMERG_DIST    = 200
local TACT_DIST     = 600
local STRAT_DIST    = 1800

-- Repulsion strength per layer
local EMERG_STRENGTH  = 1.0
local TACT_STRENGTH   = 0.82
local STRAT_STRENGTH  = 0.30

local TACT_CLOSE_BOOST_DIST = 180

-- NavMesh assist
local NAVMESH_SCAN_DIST = 900
local NAVMESH_WEIGHT    = 0.55
local NAVMESH_INTERVAL  = 0.20

-- Corridor mode
local CORRIDOR_TURN_MULT = 1.6

-- Missile body half-width for clearance probe
local BODY_HALF = 14

-- ─────────────────────────────────────────────────────────────
--  COLLISION RESILIENCE CONSTANTS
-- ─────────────────────────────────────────────────────────────

-- Armor pool: how many world-brush bumps Nikita can survive
local ARMOR_MAX           = 8

-- Minimum seconds between armor drain events (scrape guard)
local BUMP_COOLDOWN       = 0.15

-- ArmorHP regenerates this many points per interval
local ARMOR_REGEN_AMOUNT  = 1
local ARMOR_REGEN_INTERVAL= 2.0

-- BumpStreak: if Nikita bumps world geometry more than this many times
-- within STREAK_WINDOW seconds, it has been grinding and detonates.
local STREAK_MAX          = 5
local STREAK_WINDOW       = 1.5

-- Wall-kick reflection strength (0 = no bounce, 1 = full mirror reflect)
local WALL_KICK_STRENGTH  = 0.6

-- Props lighter than this (kg) get knocked aside instead of detonating Nikita
local PROP_MASS_LIMIT     = 80

-- Force applied to light props when Nikita grazes them
local PROP_KNOCKBACK      = 28000

-- OnTakeDamage: hits above this threshold detonate immediately
-- (explosions, bullets, interactive debris).  Smaller hits absorbed by HealthVal.
local DEBRIS_DAMAGE_THRESHOLD = 15

-- ─────────────────────────────────────────────────────────────
--  RAY FANS
-- ─────────────────────────────────────────────────────────────

-- LAYER 1 - EMERGENCY: dense sphere, 26 rays
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

-- LAYER 2 - TACTICAL: forward hemisphere, 18 rays
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

-- LAYER 3 - STRATEGIC: long-range 5-ray scout
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

local function NavMeshWaypoint(fromPos, toPos)
    local fromArea = navmesh.GetNearestNavArea(fromPos, false, 300, false, false)
    if not fromArea then return nil end

    local toArea = navmesh.GetNearestNavArea(toPos, false, 300, false, false)
    if not toArea then return nil end

    if fromArea == toArea then return nil end

    local neighbors = fromArea:GetAdjacentAreas()
    if not neighbors or #neighbors == 0 then return nil end

    local bestDist = math.huge
    local bestPos  = nil
    for _, area in ipairs(neighbors) do
        local center = area:GetCenter()
        local d = (center - toPos):LengthSqr()
        if d < bestDist then
            bestDist = d
            bestPos  = center + Vector(0, 0, 40)
        end
    end

    return bestPos
end

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
        slide = moveDir:Angle():Up()
    end
    slide:Normalize()
    return false, slide
end

-- ─────────────────────────────────────────────────────────────
--  COLLISION RESILIENCE HELPERS
-- ─────────────────────────────────────────────────────────────

-- Drain one ArmorHP with cooldown and streak tracking.
-- Returns true if the missile should detonate (armor depleted or streak exceeded).
local function BumpArmor(self, now)
    -- Enforce cooldown between drains (scrape guard)
    if now - self._lastBumpTime < BUMP_COOLDOWN then
        return false
    end

    self._lastBumpTime = now
    self.ArmorHP = self.ArmorHP - 1

    -- Streak tracking: reset if too much time has passed
    if now - self._streakStart > STREAK_WINDOW then
        self._bumpStreak = 0
        self._streakStart = now
    end
    self._bumpStreak = self._bumpStreak + 1

    -- Detonation conditions
    if self.ArmorHP <= 0 then
        return true   -- armor exhausted
    end
    if self._bumpStreak > STREAK_MAX then
        return true   -- sustained grinding
    end

    return false
end

-- Reflect the missile off a surface normal (wall-kick).
-- Blends between current direction and mirror-reflect by WALL_KICK_STRENGTH.
local function WallKick(self, hitNormal)
    local cur     = self:GetForward()
    local reflect = cur - hitNormal * (2 * cur:Dot(hitNormal))
    local kicked  = LerpVector(WALL_KICK_STRENGTH, cur, reflect)
    kicked:Normalize()
    self:SetAngles(kicked:Angle())
    self:SetAbsVelocity(kicked * CRUISE_SPEED)
end

-- Try to knock a light physics prop aside.
-- Returns true if the prop was knocked (missile should NOT detonate),
-- false if the prop is too heavy (missile should detonate).
local function HandlePropContact(self, ent)
    if not IsValid(ent) then return false end
    if not ent:IsValid() then return false end

    -- Only physics objects can be knocked
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return false end

    local mass = phys:GetMass()
    if mass < PROP_MASS_LIMIT then
        -- Light prop: knock it away, missile survives
        local pushDir = (ent:GetPos() - self:GetPos()):GetNormalized()
        phys:ApplyForceCenter(pushDir * PROP_KNOCKBACK)
        return true
    end

    -- Heavy prop or NPC: detonate
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

    -- Fly-past detector
    self._prevDistSqr  = math.huge

    -- NavMesh assist state
    self._navWaypoint   = nil
    self._nextNavSample = 0

    -- ── Collision resilience state ──────────────────────────
    self.ArmorHP        = ARMOR_MAX
    self._lastBumpTime  = -999
    self._bumpStreak    = 0
    self._streakStart   = CurTime()
    self._nextArmorRegen= CurTime() + ARMOR_REGEN_INTERVAL

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

    local now = CurTime()

    if now - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if not self.EngineActive then return true end

    -- ── Armor HP regen ────────────────────────────────────────
    if now >= self._nextArmorRegen then
        self._nextArmorRegen = now + ARMOR_REGEN_INTERVAL
        self.ArmorHP = math.min(self.ArmorHP + ARMOR_REGEN_AMOUNT, ARMOR_MAX)
    end

    local myPos      = self:GetPos()
    local currentDir = self:GetForward()
    local filter     = { self, IsValid(self.NikitaOwner) and self.NikitaOwner or self }

    -- ═══ 1. HOMING TARGET ════════════════════════════════════
    local aimPos = GetAimPos(self.TrackEnt, self.FallbackTarget)

    -- ═══ 2. PROXIMITY DETONATION ═════════════════════════════
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

    -- ═══ 3. THREE-LAYER SPATIAL AWARENESS ════════════════════

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

    -- ═══ 4. NAVMESH PATH ASSIST ══════════════════════════════
    if aimPos and now >= self._nextNavSample then
        self._nextNavSample = now + NAVMESH_INTERVAL

        local fwdToTarget = (aimPos - myPos):GetNormalized()
        local navCheck = util.TraceLine({
            start  = myPos,
            endpos = myPos + fwdToTarget * NAVMESH_SCAN_DIST,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })

        if navCheck.Hit then
            local wp = NavMeshWaypoint(myPos, aimPos)
            self._navWaypoint = wp
        else
            self._navWaypoint = nil
        end
    end

    -- ═══ 5. COMPOSE STEERING DIRECTION ═══════════════════════

    local homingDir = aimPos and (aimPos - myPos):GetNormalized() or currentDir

    if aimPos and self._navWaypoint then
        local navDir = (self._navWaypoint - myPos):GetNormalized()
        homingDir = LerpVector(NAVMESH_WEIGHT, homingDir, navDir)
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

    -- ═══ 6. CLEARANCE PROBE ══════════════════════════════════
    local fits, slideDir = ClearanceProbe(myPos, desiredDir, filter)
    if not fits and slideDir then
        desiredDir = LerpVector(0.7, desiredDir, slideDir)
        desiredDir:Normalize()
    end

    -- ═══ 7. APPLY TURN + VELOCITY ════════════════════════════
    local moveDir = LerpVector(FrameTime() * activeTurnSpeed, currentDir, desiredDir)
    moveDir:Normalize()

    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    -- ═══ 8. AHEAD HULL TRACE - collision resilience ═══════════
    -- Uses MASK_SHOT so we catch both world AND entities.
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
            -- ── World / brush hit ─────────────────────────────
            -- Drain armor, apply wall-kick, survive if armor remains.
            local shouldDetonate = BumpArmor(self, now)
            if shouldDetonate then
                self:MissileDoExplosion(); return true
            end
            -- Bounce off the wall and keep flying
            WallKick(self, tr.HitNormal)

        elseif IsValid(tr.Entity) then
            local ent = tr.Entity
            if ent == self.NikitaOwner then
                -- Ignore owner
            elseif ent:IsPlayer() or ent:IsNPC() then
                -- Direct hit on a living target: always detonate
                self:MissileDoExplosion(); return true
            else
                -- Physics prop: try to knock it aside
                local knocked = HandlePropContact(self, ent)
                if not knocked then
                    -- Heavy / non-physics entity: detonate
                    self:MissileDoExplosion(); return true
                end
                -- Light prop knocked: drain a small armor tick and continue
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
    -- Short arm delay so we do not detonate on the muzzle / owner
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.NikitaOwner then return end

    -- Touch() fires for overlapping solids.
    -- Players and NPCs always detonate.
    if IsValid(ent) and (ent:IsPlayer() or ent:IsNPC()) then
        self:MissileDoExplosion()
        return
    end

    -- Physics props: handled by the hull trace above.
    -- Anything else (func_brush, doors, etc.) → treat as world, drain armor.
    local shouldDetonate = BumpArmor(self, CurTime())
    if shouldDetonate then
        self:MissileDoExplosion()
    end
end

function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end

    local dmg = dmginfo:GetDamage()

    -- Sensitive to significant hits (bullets, explosions, interactive debris)
    if dmg >= DEBRIS_DAMAGE_THRESHOLD then
        self:MissileDoExplosion()
        return
    end

    -- Light hits (grazing, small debris) only chip HealthVal
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
