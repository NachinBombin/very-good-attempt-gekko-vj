AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  SERVER  -  Gekko Nikita Autonomous Homing Missile
--
--  DESIGN:
--    * Purely autonomous: chases self.TrackEnt (enemy) every tick.
--      FireNikita sets:
--          nikita.TrackEnt = enemy
--          nikita.NikitaOwner = ent
--    * NO joystick, NO TargetPos, NO static ground fallback.
--    * Constant forward speed (210 u/s) with strong lateral turn.
--    * Destroyable: SOLID_BBOX with collision bounds.
-- ============================================================

local SND_EXPLODE   = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED  = 210    -- units / second, constant
local TURN_SPEED    = 10.0   -- Lerp factor per second

local LIFETIME      = 45
local PROX_RADIUS   = 180
local ENGINE_DELAY  = 0.5
local TARGET_Z_OFFS = 40     -- aim a bit above feet

local HULL_MINS = Vector(-8, -8, -8)
local HULL_MAXS = Vector( 8,  8,  8)

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

    -- Make it actually hittable
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

    -- FireNikita sets:
    --   self.TrackEnt    = enemy
    --   self.NikitaOwner = ent
    --   self:SetOwner(ent)

    -- Launch nudge
    self:SetAbsVelocity(self:GetForward() * 80)

    local selfRef = self
    timer.Simple(ENGINE_DELAY, function()
        if not IsValid(selfRef) or selfRef.Destroyed then return end

        selfRef.Damage       = math.random(25 , 45)
        selfRef.Radius       = math.random(180 ,500)
        selfRef.EngineActive = true

        print(string.format(
            "[NikitaDBG] Engine ACTIVE | track=%s",
            tostring(selfRef.TrackEnt)
        ))
    end)

    self:NextThink(CurTime())
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

    local aimPos = GetAimPos(self.TrackEnt)
    local currentDir = self:GetForward()
    local moveDir

    if aimPos then
        -- Proximity detonation
        if (self:GetPos() - aimPos):LengthSqr() < PROX_RADIUS * PROX_RADIUS then
            self:MissileDoExplosion()
            return true
        end

        local desiredDir = (aimPos - self:GetPos()):GetNormalized()
        moveDir = LerpVector(FrameTime() * TURN_SPEED, currentDir, desiredDir)
        moveDir:Normalize()
    else
        -- No valid target: keep last heading
        moveDir = currentDir
    end

    self:SetAngles(moveDir:Angle())
    self:SetAbsVelocity(moveDir * CRUISE_SPEED)

    -- Collision sweep ahead
    local stepDist = CRUISE_SPEED * FrameTime() + 16
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
            "[NikitaDBG] trackValid=%s spd=%.0f ang=%s",
            tostring(IsValid(self.TrackEnt)),
            self:GetAbsVelocity():Length(),
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