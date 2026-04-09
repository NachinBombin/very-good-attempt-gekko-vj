-- ============================================================
--  sent_gekko_nikita / init.lua
--
--  Slow homing cruise missile fired by the Gekko NPC.
--  Mirrors sent_npc_trackmissile flight model WITHOUT the
--  top-attack ceiling / ballistic phase.
--
--  DESIGN CONTRACT:
--    * Gekko sets  self.TrackEnt (entity)  AND  self.Target (Vector)
--      before Spawn().  TrackEnt is followed live while alive;
--      Target is the fallback position when TrackEnt dies.
--    * Speed hard-capped at 600 u/s (slow, dodgeable cruise).
--    * Health 50 HP -- can be shot down.
--    * No ballistic / ceiling phase.
--    * No autonomous target scan.
-- ============================================================
AddCSLuaFile()
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")   -- registers SetTargetPos / GetTargetPos

-- ============================================================
--  Tuning
-- ============================================================
local FORCE_PER_TICK        = 48000
local SPEED_CAP             = 600
local TURN_RATE             = 0.06    -- 0-1 fraction toward wanted angle per physics tick
local LIFETIME              = 20
local COLLISION_IMMUNE_TIME = 0.5
local KICK_UP_SPEED         = 400
local ENGINE_DELAY          = 0.6
local PROX_DETONATE         = 180
local HEALTH                = 50
local BLAST_DAMAGE          = 1800
local BLAST_RADIUS          = 512

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- Inline angle lerp: server-safe replacement for LerpAngle (client-only global)
local function AngleLerp(t, a, b)
    local function lerpAngleDeg(from, to, frac)
        local delta = (to - from + 540) % 360 - 180
        return from + delta * frac
    end
    return Angle(
        lerpAngleDeg(a.p, b.p, t),
        lerpAngleDeg(a.y, b.y, t),
        lerpAngleDeg(a.r, b.r, t)
    )
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_launch.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:SetMass(500)
        self.PhysObj:EnableDrag(true)
        self.PhysObj:EnableGravity(true)
    end

    self.SpeedValue   = 0
    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = HEALTH
    self.Damage       = 0
    self.Radius       = 0

    if not self.Target or type(self.Target) ~= "Vector" then
        local fwd = self:GetForward() ; fwd.z = 0 ; fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print("[GekkoNikita] WARNING: no Target set -- using fallback")
    end

    self:SetTargetPos(self.Target)

    local selfRef = self
    timer.Simple(0, function()
        if not IsValid(selfRef) then return end
        local phys = selfRef:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(Vector(0, 0, 1) * KICK_UP_SPEED)
        end
    end)

    sound.Play(SND_LAUNCH, self:GetPos(), 511, 60)
    self.EngineSound = CreateSound(self, SND_ENGINE)

    timer.Simple(ENGINE_DELAY, function()
        if IsValid(selfRef) and not selfRef.Destroyed then
            selfRef:FireEngine()
        end
    end)

    timer.Simple(LIFETIME, function()
        if IsValid(selfRef) and not selfRef.Destroyed then
            selfRef:MissileDoExplosion()
        end
    end)

    self:NextThink(CurTime())
end

-- ============================================================
--  FireEngine
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end
    self.Damage       = math.random(2000, BLAST_DAMAGE)
    self.Radius       = math.random(480, BLAST_RADIUS)
    self.EngineActive = true
    self:SetNWBool("EngineStarted", true)
    self.EngineSound:PlayEx(511, 100)

    local a = self:GetAngles()
    a:RotateAroundAxis(self:GetUp(), 180)
    local prop = ents.Create("prop_physics")
    if IsValid(prop) then
        prop:SetPos(self:LocalToWorld(Vector(-15, 0, 0)))
        prop:SetAngles(a)
        prop:SetParent(self)
        prop:SetModel("models/items/ar2_grenade.mdl")
        prop:Spawn()
        prop:SetRenderMode(RENDERMODE_TRANSALPHA)
        prop:SetColor(Color(0, 0, 0, 0))
        ParticleEffectAttach("scud_trail", PATTACH_ABSORIGIN_FOLLOW, prop, 0)
    end
end

-- ============================================================
--  PhysicsUpdate  --  guidance + thrust (every physics tick)
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.EngineActive then return end
    local phys = self:GetPhysicsObject()
    if not IsValid(phys) then return end

    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = math.min(self.SpeedValue + FORCE_PER_TICK, FORCE_PER_TICK * 10)
    end

    -- Resolve live aim position
    local aimPos
    if IsValid(self.TrackEnt) then
        aimPos = self.TrackEnt:GetPos() + Vector(0, 0, 40)
    elseif self.Target then
        aimPos = self.Target
    else
        phys:ApplyForceCenter(self:GetForward() * self.SpeedValue)
        return
    end

    local wantAngle = (aimPos - self:GetPos()):GetNormalized():Angle()
    -- AngleLerp is our inline server-safe replacement for LerpAngle
    self:SetAngles(AngleLerp(TURN_RATE, self:GetAngles(), wantAngle))

    phys:ApplyForceCenter(self:GetForward() * self.SpeedValue)
end

-- ============================================================
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide(data, physobj)
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < COLLISION_IMMUNE_TIME then return end
    if not self.EngineActive then return end
    self:MissileDoExplosion()
end

-- ============================================================
--  Think  --  proximity detonation
-- ============================================================
function ENT:Think()
    self:NextThink(CurTime())
    if self.Destroyed then return true end

    if self.EngineActive then
        local checkPos
        if IsValid(self.TrackEnt) then
            checkPos = self.TrackEnt:GetPos()
        elseif self.Target then
            checkPos = self.Target
        end
        if checkPos and (self:GetPos() - checkPos):Length() < PROX_DETONATE then
            self:MissileDoExplosion()
            return true
        end
    end

    return true
end

-- ============================================================
--  OnTakeDamage  --  can be shot down
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

-- ============================================================
--  MissileDoExplosion
-- ============================================================
function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()

    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or BLAST_DAMAGE
    local rad   = self.Radius > 0 and self.Radius or BLAST_RADIUS
    local owner = IsValid(self.Owner) and self.Owner or self

    sound.Play(SND_EXPLODE, pos, 100, 100)
    util.ScreenShake(pos, 16, 200, 1, 3000)
    ParticleEffect("vj_explosion3", pos, Angle(0, 0, 0))

    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed)

    local pe = ents.Create("env_physexplosion")
    if IsValid(pe) then
        pe:SetPos(pos)
        pe:SetKeyValue("Magnitude",  tostring(math.floor(dmg * 5)))
        pe:SetKeyValue("radius",     tostring(rad))
        pe:SetKeyValue("spawnflags", "19")
        pe:Spawn() ; pe:Activate()
        pe:Fire("Explode", "", 0)
        pe:Fire("Kill",    "", 0.5)
    end

    util.BlastDamage(self, owner, pos + Vector(0, 0, 50), rad, dmg)
    self:Remove()
end

-- ============================================================
--  OnRemove
-- ============================================================
function ENT:OnRemove()
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
end
