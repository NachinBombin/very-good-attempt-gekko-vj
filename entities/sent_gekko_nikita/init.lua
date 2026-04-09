AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  SERVER  -  Gekko Nikita Autonomous Homing Missile
--
--  DESIGN:
--    * Purely autonomous: chases self.TrackEnt (enemy) every tick.
--      FireNikita sets:
--          nikita.TrackEnt    = enemy
--          nikita.NikitaOwner = ent
--    * Constant cruise speed with random fuel-burst pulses:
--        Every 3 s: 50% chance -> ramp speed up +100 u/s over 1 s,
--                                 then ramp back to cruise over 1 s.
--    * NWFloat "NikitaBoost" (0..1) tells the client how "boosted"
--      the missile currently is, so particles can swell.
-- ============================================================

local SND_EXPLODE   = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED  = 310    -- units / second, constant baseline
local BOOST_EXTRA   = 100    -- extra u/s at peak boost
local TURN_SPEED    = 10.0   -- Lerp factor per second

local BOOST_RAMP_UP   = 1.0  -- seconds to reach full boost
local BOOST_RAMP_DOWN = 1.0  -- seconds to return to cruise
local BOOST_INTERVAL  = 3.0  -- seconds between roll attempts
local BOOST_CHANCE    = 0.50 -- probability per interval

local LIFETIME    = 45
local PROX_RADIUS = 180
local ENGINE_DELAY = 0.5
local TARGET_Z_OFFS = 40

local HULL_MINS = Vector(-8, -8, -8)
local HULL_MAXS = Vector( 8,  8,  8)

-- Boost FSM states
local BOOST_IDLE  = 0
local BOOST_UP    = 1
local BOOST_DOWN  = 2

local function GetAimPos(trackEnt)
    if IsValid(trackEnt) then
        local p = trackEnt:GetPos()
        return Vector(p.x, p.y, p.z + TARGET_Z_OFFS)
    end
    return nil
end

function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_launch.mdl")
    self:SetModelScale(7, 0)

    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(HULL_MINS, HULL_MAXS)
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = 50
    self.Damage       = 0
    self.Radius       = 0
    self._nextDebug   = 0

    -- Boost system state
    self._boostState     = BOOST_IDLE
    self._boostPhaseT    = 0      -- CurTime() when current phase started
    self._nextBoostRoll  = CurTime() + ENGINE_DELAY + BOOST_INTERVAL
    self._boostValue     = 0      -- 0..1, replicated to client

    self:SetNWFloat("NikitaBoost", 0)

    -- FireNikita sets:
    --   self.TrackEnt    = enemy
    --   self.NikitaOwner = ent

    self:SetAbsVelocity(self:GetForward() * 80)

    local selfRef = self
    timer.Simple(ENGINE_DELAY, function()
        if not IsValid(selfRef) or selfRef.Destroyed then return end
        selfRef.Damage       = math.random(25, 45)
        selfRef.Radius       = math.random(180, 500)
        selfRef.EngineActive = true
        print(string.format(
            "[NikitaDBG] Engine ACTIVE | track=%s",
            tostring(selfRef.TrackEnt)
        ))
    end)

    self:NextThink(CurTime())
end

-- ============================================================
--  Boost pulse update  (called every Think tick)
--  Returns the current effective speed (units/s).
-- ============================================================
function ENT:UpdateBoost()
    local now = CurTime()

    -- Roll for new burst when idle and timer has elapsed
    if self._boostState == BOOST_IDLE and now >= self._nextBoostRoll then
        self._nextBoostRoll = now + BOOST_INTERVAL
        if math.random() < BOOST_CHANCE then
            -- Start ramp-up phase
            self._boostState  = BOOST_UP
            self._boostPhaseT = now
        end
    end

    -- Advance boost state machine
    if self._boostState == BOOST_UP then
        local t = math.Clamp((now - self._boostPhaseT) / BOOST_RAMP_UP, 0, 1)
        self._boostValue = t
        if t >= 1 then
            -- Peak reached -> start ramp-down
            self._boostState  = BOOST_DOWN
            self._boostPhaseT = now
        end

    elseif self._boostState == BOOST_DOWN then
        local t = math.Clamp((now - self._boostPhaseT) / BOOST_RAMP_DOWN, 0, 1)
        self._boostValue = 1 - t
        if t >= 1 then
            -- Fully back to cruise
            self._boostState = BOOST_IDLE
            self._boostValue = 0
        end
    end

    -- Replicate to client (cheap NWFloat update each tick)
    self:SetNWFloat("NikitaBoost", self._boostValue)

    return CRUISE_SPEED + self._boostValue * BOOST_EXTRA
end

function ENT:Think()
    self:NextThink(CurTime())
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if not self.EngineActive then
        return true
    end

    -- Resolve current speed (includes boost pulse)
    local currentSpeed = self:UpdateBoost()

    local aimPos = GetAimPos(self.TrackEnt)
    local currentDir = self:GetForward()
    local moveDir

    if aimPos then
        if (self:GetPos() - aimPos):LengthSqr() < PROX_RADIUS * PROX_RADIUS then
            self:MissileDoExplosion()
            return true
        end

        local desiredDir = (aimPos - self:GetPos()):GetNormalized()
        moveDir = LerpVector(FrameTime() * TURN_SPEED, currentDir, desiredDir)
        moveDir:Normalize()
    else
        moveDir = currentDir
    end

    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * currentSpeed)

    -- Collision sweep ahead
    local stepDist = currentSpeed * FrameTime() + 16
    local tr = util.TraceHull({
        start  = self:GetPos(),
        endpos = self:GetPos() + moveDir * stepDist,
        mins   = HULL_MINS,
        maxs   = HULL_MAXS,
        mask   = MASK_SHOT,
        filter = {
            self,
            IsValid(self.NikitaOwner) and self.NikitaOwner or self
        },
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

    if CurTime() > self._nextDebug then
        self._nextDebug = CurTime() + 0.5
        print(string.format(
            "[NikitaDBG] trackValid=%s spd=%.0f boost=%.2f ang=%s",
            tostring(IsValid(self.TrackEnt)),
            currentSpeed,
            self._boostValue,
            tostring(self:GetAngles())
        ))
    end

    return true
end

function ENT:Touch(ent)
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.NikitaOwner then return end
    self:MissileDoExplosion()
end

function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
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

    sound.Play(SND_EXPLODE, pos, 100, 100)
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
        pe:Spawn()
        pe:Activate()
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
