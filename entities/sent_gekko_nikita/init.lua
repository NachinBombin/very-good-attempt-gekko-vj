-- ============================================================
--  sent_gekko_nikita / init.lua
--
--  Nikita cruise missile fired exclusively by the Gekko NPC.
--
--  DESIGN CONTRACT:
--    * The Gekko (npc_vj_gekko/init.lua :: FireNikita) is the
--      SOLE target authority.
--    * Receives a fixed  self.Target  Vector before Spawn().
--    * Performs NO autonomous enemy scan, NO nearest-entity
--      lookup, and NO re-acquisition mid-flight.
--    * Flies to the given position and detonates.
--    * If Target is nil/zero on Spawn the missile self-destructs
--      safely after 0.2 s so no orphan entity persists.
--
--  Lifecycle:
--    Initialize()  -- validate target, set physics, broadcast TargetPos
--    Think()       -- steer toward target every tick
--    Touch()       -- detonate on contact
--    timer         -- auto-detonate after LIFETIME seconds
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
local SPEED_INITIAL   = 600     -- units/s at launch
local SPEED_CRUISE    = 1100    -- units/s at full throttle
local SPEED_RAMP_TIME = 0.6     -- seconds to reach cruise speed
local TURN_RATE       = 3.8     -- lerp weight per tick (higher = tighter turns)
local LIFETIME        = 14      -- seconds before auto-detonate
local BLAST_RADIUS    = 380
local BLAST_DAMAGE    = 220
local COLLIDE_GRACE   = 0.45   -- seconds of owner-collision immunity after spawn
local PROX_DETONATE   = 80     -- units from target pos to detonate
local THINK_INTERVAL  = 0      -- 0 = every server tick

local SND_LAUNCH   = "weapons/rpg/rocket1.wav"
local SND_FLY      = "weapons/rpg/rocket_fly.wav"
local SND_DETONATE = "weapons/explode5.wav"
local FX_EXPLODE   = "Explosion"

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_closed.mdl")
    self:SetModelScale(10)  -- match the 10x visual scale referenced in cl_init
    self:SetMoveType(MOVETYPE_FLY)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-4,-4,-4), Vector(4,4,4))
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)
    self:SetGravity(0)
    self._spawnTime = CurTime()

    -- Validate target assigned by Gekko before Spawn()
    if not self.Target or self.Target == vector_origin then
        print("[GekkoNikita] ERROR: no Target on Initialize -- self-destructing")
        timer.Simple(0.2, function() if IsValid(self) then self:Remove() end end)
        return
    end
    self._target = self.Target  -- fixed forever; never re-assigned

    -- Broadcast target position to clients (for targeting line in cl_init)
    self:SetTargetPos(self._target)

    -- Initial velocity
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

    -- Sounds
    self:EmitSound(SND_LAUNCH, 80, 100, 1)
    timer.Simple(0.3, function()
        if IsValid(self) then self:EmitSound(SND_FLY, 75, 95, 1) end
    end)

    -- Safety auto-detonate
    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Detonate() end
    end)

    self:NextThink(CurTime())
end

-- ============================================================
--  Think  (steer toward fixed target position)
-- ============================================================
function ENT:Think()
    local now = CurTime()
    local age = now - (self._spawnTime or now)

    -- Speed ramp
    local speed = math.Lerp(
        math.Clamp(age / SPEED_RAMP_TIME, 0, 1),
        SPEED_INITIAL, SPEED_CRUISE
    )

    local pos    = self:GetPos()
    local want   = (self._target - pos):GetNormalized()
    local cur    = self:GetForward()
    local lerpT  = math.Clamp(TURN_RATE * FrameTime(), 0, 1)
    local newDir = LerpVector(lerpT, cur, want)
    if newDir:Length() < 0.001 then newDir = want end
    newDir:Normalize()

    self:SetAngles(newDir:Angle())
    local vel = newDir * speed
    self:SetLocalVelocity(vel)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:SetVelocity(vel) end

    -- Proximity detonation
    if pos:Distance(self._target) < PROX_DETONATE then
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
    if IsValid(self:GetOwner()) and other == self:GetOwner() then
        if CurTime() - (self._spawnTime or 0) < COLLIDE_GRACE then return end
    end
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
    util.BlastDamage(self, attacker, pos, BLAST_RADIUS, BLAST_DAMAGE)
    local eff = EffectData()
    eff:SetOrigin(pos) ; eff:SetNormal(self:GetForward())
    eff:SetScale(1)    ; eff:SetMagnitude(3)
    util.Effect(FX_EXPLODE, eff)
    self:EmitSound(SND_DETONATE, 120, 100, 1)
    self:Remove()
end
