-- ============================================================
--  sent_gekko_nikita / init.lua
--
--  Nikita cruise missile fired exclusively by the Gekko NPC.
--
--  DESIGN CONTRACT:
--    * The Gekko (init.lua::FireNikita) is the SOLE target authority.
--    * This entity receives a fixed `Target` Vector before Spawn().
--    * It performs NO autonomous enemy scan, NO nearest-entity
--      lookup, and NO re-acquisition.  It flies straight at the
--      target position it was given and detonates there.
--    * If Target is nil/zero on Spawn the missile self-destructs
--      safely after 0.2 s so no orphan persists.
--
--  Lifecycle:
--    Initialize()  -- validate target, set physics, start trail
--    Think()       -- steer toward target every tick
--    OnTouch()     -- detonate on contact
--    auto-detonate -- timer fires if travel time exceeds LIFETIME
-- ============================================================
AddCSLuaFile()

ENT.Type           = "anim"
ENT.Base           = "base_anim"
ENT.PrintName      = "Gekko Nikita Missile"
ENT.Author         = "Gekko NPC"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- ============================================================
--  Tuning constants
-- ============================================================
local SPEED_INITIAL    = 600     -- units/s at launch
local SPEED_CRUISE     = 1100    -- units/s after SPEED_RAMP_TIME
local SPEED_RAMP_TIME  = 0.6     -- seconds to reach cruise speed
local TURN_RATE        = 3.8     -- max turn speed (degrees/tick at 66 tick)
local LIFETIME         = 14      -- seconds before auto-detonate
local BLAST_RADIUS     = 380
local BLAST_DAMAGE     = 220
local COLLIDE_GRACE    = 0.45    -- seconds of owner-collision immunity
local THINK_INTERVAL   = 0       -- 0 = every tick

-- Particle / sound
local SND_LAUNCH   = "weapons/rpg/rocket1.wav"
local SND_FLY      = "weapons/rpg/rocket_fly.wav"
local SND_DETONATE = "weapons/explode5.wav"
local FX_TRAIL     = "trails/smoke"
local FX_EXPLODE   = "Explosion"
local FX_SMOKE     = "MissileExhaust"

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_closed.mdl")
    self:SetMoveType(MOVETYPE_FLY)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-4,-4,-4), Vector(4,4,4))
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)
    self:SetGravity(0)
    self._spawnTime = CurTime()

    -- Validate target assigned by Gekko
    if not self.Target or self.Target == vector_origin then
        print("[GekkoNikita] ERROR: no valid Target on Initialize -- self-destructing")
        timer.Simple(0.2, function() if IsValid(self) then self:Remove() end end)
        return
    end
    self._target = self.Target   -- fixed, never updated again

    -- Initial velocity toward target
    local dir = (self._target - self:GetPos()):GetNormalized()
    self:SetAngles(dir:Angle())
    self:SetLocalVelocity(dir * SPEED_INITIAL)
    self:PhysicsInit(SOLID_BBOX)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false)
        phys:SetVelocity(dir * SPEED_INITIAL)
        phys:SetMass(1)
    end

    -- Trail
    util.SpriteTrail(self, 0, Color(220, 200, 180, 200), false, 6, 1, 1.4, 1/6, FX_TRAIL)

    -- Sounds
    self:EmitSound(SND_LAUNCH, 80, 100, 1)
    timer.Simple(0.3, function()
        if IsValid(self) then self:EmitSound(SND_FLY, 75, 95, 1) end
    end)

    -- Lifetime auto-detonate
    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Detonate() end
    end)

    self:NextThink(CurTime())
end

-- ============================================================
--  Think  (steer toward fixed target)
-- ============================================================
function ENT:Think()
    local now = CurTime()
    local age = now - (self._spawnTime or now)

    -- Current speed ramps from SPEED_INITIAL to SPEED_CRUISE over ramp time
    local speed = math.Lerp(
        math.Clamp(age / SPEED_RAMP_TIME, 0, 1),
        SPEED_INITIAL,
        SPEED_CRUISE
    )

    local pos       = self:GetPos()
    local wantDir   = (self._target - pos):GetNormalized()
    local curDir    = self:GetForward()

    -- Angular interpolation (clamp turn rate so it can't teleport direction)
    local dot  = math.Clamp(curDir:Dot(wantDir), -1, 1)
    local lerpT = math.Clamp(TURN_RATE * FrameTime(), 0, 1)
    local newDir = LerpVector(lerpT, curDir, wantDir)
    if newDir:Length() < 0.001 then newDir = wantDir end
    newDir:Normalize()

    local newAng = newDir:Angle()
    self:SetAngles(newAng)

    local vel = newDir * speed
    self:SetLocalVelocity(vel)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:SetVelocity(vel) end

    -- Proximity detonation (within 80 units of fixed target pos)
    if pos:Distance(self._target) < 80 then
        self:Detonate()
        return
    end

    self:NextThink(CurTime() + THINK_INTERVAL)
    return true
end

-- ============================================================
--  Touch  (contact detonation)
-- ============================================================
function ENT:Touch(other)
    -- Ignore owner for grace period
    if IsValid(self:GetOwner()) and other == self:GetOwner() then
        if CurTime() - (self._spawnTime or 0) < COLLIDE_GRACE then return end
    end
    -- Ignore other missiles / projectiles to prevent chain-pops
    if IsValid(other) and other:GetCollisionGroup() == COLLISION_GROUP_PROJECTILE then return end
    self:Detonate()
end

-- ============================================================
--  Detonate
-- ============================================================
function ENT:Detonate()
    if self._detonated then return end
    self._detonated = true

    local pos      = self:GetPos()
    local attacker = IsValid(self.Owner) and self.Owner or self

    -- Blast
    util.BlastDamage(self, attacker, pos, BLAST_RADIUS, BLAST_DAMAGE)

    -- Effects
    local eff = EffectData()
    eff:SetOrigin(pos) ; eff:SetNormal(self:GetForward())
    eff:SetScale(1) ; eff:SetMagnitude(3)
    util.Effect(FX_EXPLODE, eff)

    self:EmitSound(SND_DETONATE, 120, 100, 1)

    self:Remove()
end
