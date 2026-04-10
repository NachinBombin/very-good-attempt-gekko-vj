AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  Nikita Homing Missile  –  server
--
--  MOVEMENT:  MOVETYPE_NOCLIP + SetAbsVelocity (constant 310 u/s)
--  HOMING:    self.TrackEnt (plain Lua field, set by spawner)
--  AVOIDANCE: 10-ray fan from nose tip, averaged into a safe
--             waypoint, blended with the homing target.
--
--  DETONATION FIXES (overshoot / orbit bug):
--    1. PROX_RADIUS raised 180 -> 280 (was too small for tangential passes)
--    2. Secondary proximity check against raw TrackEnt:GetPos() (no Z offset)
--       catches cases where the missile passes through the body below aimPos.
--    3. Fly-past detector: if distance to aimPos was shrinking last tick
--       but is now growing AND we are within 4*PROX_RADIUS, we just flew
--       past the closest point -> detonate immediately.
-- ============================================================

local CRUISE_SPEED  = 310       -- u/s, constant, never changes
local TURN_SPEED    = 8.0       -- lerp factor / second (lateral agility)
local AVOID_WEIGHT  = 0.72      -- how strongly avoidance overrides homing (0-1)
local RAY_LENGTH    = 1800      -- how far ahead we scan for walls
local AVOID_THRESH  = 600       -- if a ray hits within this dist, avoidance kicks in
local PROX_RADIUS   = 280       -- FIX #1: was 180, raised to catch tangential passes
local TARGET_Z_OFFS = 40        -- aim slightly above ground on tracked entity
local LIFETIME      = 45
local ENGINE_DELAY  = 0.5

-- 10-ray fan definition: { pitch, yaw } in local missile space
local RAYS = {
    { 0,    0   },   -- dead ahead (forward)
    { 0,    25  },   -- left
    { 0,   -25  },   -- right
    {-25,   0   },   -- up
    { 25,   0   },   -- down
    {-20,   50  },   -- upper-left diagonal
    {-20,  -50  },   -- upper-right diagonal
    { 20,   50  },   -- lower-left diagonal
    { 20,  -50  },   -- lower-right diagonal
    { 0,    0   },   -- duplicate forward so forward is weighted 2x
}

-- ----------------------------------------------------------------
-- helpers
-- ----------------------------------------------------------------

local function GetAimPos(trackEnt, fallback)
    if IsValid(trackEnt) then
        local p = trackEnt:GetPos()
        return Vector(p.x, p.y, p.z + TARGET_Z_OFFS)
    end
    return fallback  -- may be nil
end

local function ComputeAvoidanceTarget(originPos, missileEnt, minDist, owner)
    local filter = { missileEnt }
    if IsValid(owner) then filter[#filter+1] = owner end

    local accumulator = Vector(0, 0, 0)
    local anyClose = false

    for _, ray in ipairs(RAYS) do
        local dir = missileEnt:LocalToWorldAngles(Angle(ray[1], ray[2], 0)):Forward()
        local tr  = util.TraceLine({
            start  = originPos,
            endpos = originPos + dir * RAY_LENGTH,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = filter,
        })

        local safePoint = tr.HitPos + tr.HitNormal * minDist

        if tr.Hit and (originPos - tr.HitPos):Length() < AVOID_THRESH then
            anyClose = true
        end

        accumulator = accumulator + safePoint
    end

    return accumulator / #RAYS, anyClose
end

-- ----------------------------------------------------------------
-- entity lifecycle
-- ----------------------------------------------------------------

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

    -- FIX #3: track previous distance-squared to aimPos for fly-past detection
    self._prevDistSqr = math.huge

    -- Spawner sets these:
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

-- ----------------------------------------------------------------
-- think  –  homing + avoidance + velocity
-- ----------------------------------------------------------------

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

    -- ── 1. Homing target ────────────────────────────────────────
    local aimPos = GetAimPos(self.TrackEnt, self.FallbackTarget)

    -- ── 2. Proximity detonation ──────────────────────────────────
    if aimPos then
        local distSqr = (myPos - aimPos):LengthSqr()

        -- FIX #1: larger sphere catches tangential/glancing approaches
        if distSqr < PROX_RADIUS * PROX_RADIUS then
            self:MissileDoExplosion()
            return true
        end

        -- FIX #2: secondary check against raw entity origin (no Z offset).
        -- The +40 Z shifts aimPos above the body; the missile can pass
        -- through the torso without ever entering the aimPos sphere.
        if IsValid(self.TrackEnt) then
            local rawPos = self.TrackEnt:GetPos()
            if (myPos - rawPos):LengthSqr() < PROX_RADIUS * PROX_RADIUS then
                self:MissileDoExplosion()
                return true
            end
        end

        -- FIX #3: fly-past detector.
        -- If distance was closing last tick but is now opening AND we are
        -- within 4x the prox radius, we just crossed closest approach -> detonate.
        local FLY_PAST_GATE_SQR = (PROX_RADIUS * 4) * (PROX_RADIUS * 4)
        if distSqr > self._prevDistSqr and distSqr < FLY_PAST_GATE_SQR then
            self:MissileDoExplosion()
            return true
        end
        self._prevDistSqr = distSqr
    else
        self._prevDistSqr = math.huge
    end

    -- ── 3. Obstacle avoidance rays from nose tip ─────────────────
    local noseTip   = myPos + currentDir * 20
    local minDist   = CRUISE_SPEED * 1.5

    local avoidPoint, wallClose = ComputeAvoidanceTarget(
        noseTip, self, minDist, self.NikitaOwner
    )

    -- ── 4. Choose steering target ─────────────────────────────────
    local steerTarget

    if aimPos then
        if wallClose then
            steerTarget = LerpVector(AVOID_WEIGHT, aimPos, avoidPoint)
        else
            steerTarget = aimPos
        end
    else
        steerTarget = avoidPoint
    end

    -- ── 5. Compute desired direction and turn ─────────────────────
    local desiredDir = (steerTarget - myPos):GetNormalized()
    local moveDir    = LerpVector(FrameTime() * TURN_SPEED, currentDir, desiredDir)
    moveDir:Normalize()

    -- ── 6. Apply constant speed + orientation ────────────────────
    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    -- ── 7. Ahead-trace collision detection ───────────────────────
    local stepDist = CRUISE_SPEED * FrameTime() + 16
    local tr = util.TraceHull({
        start  = myPos,
        endpos = myPos + moveDir * stepDist,
        mins   = Vector(-8, -8, -8),
        maxs   = Vector( 8,  8,  8),
        mask   = MASK_SHOT,
        filter = { self, IsValid(self.NikitaOwner) and self.NikitaOwner or self },
    })

    if tr.Hit then
        if tr.HitWorld then
            self:MissileDoExplosion()
            return true
        end
        if IsValid(tr.Entity) and tr.Entity ~= self.NikitaOwner then
            self:MissileDoExplosion()
            return true
        end
    end

    return true
end

-- ----------------------------------------------------------------
-- Touch / damage / explosion
-- ----------------------------------------------------------------

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
