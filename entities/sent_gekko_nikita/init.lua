-- ============================================================
--  sent_gekko_nikita / init.lua
--
--  Nikita cruise missile fired exclusively by the Gekko NPC.
--
--  DESIGN CONTRACT:
--    * The Gekko (npc_vj_gekko/init.lua :: FireNikita) is the
--      SOLE target authority.
--    * Receives a fixed  self.Target  Vector before Spawn().
--    * NO enemy scan, NO nearest-entity lookup, NO re-acquisition.
--    * Flies to given position and detonates.
-- ============================================================
AddCSLuaFile()
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")   -- registers SetTargetPos / GetTargetPos

-- ============================================================
--  Tuning
-- ============================================================
local SPEED_INITIAL   = 600
local SPEED_CRUISE    = 1100
local SPEED_RAMP_TIME = 0.6
local TURN_RATE       = 0.12    -- 0-1 lerp fraction per tick toward wanted dir
local LIFETIME        = 14
local BLAST_RADIUS    = 380
local BLAST_DAMAGE    = 220
local COLLIDE_GRACE   = 0.45
local PROX_DETONATE   = 80

local SND_LAUNCH   = "weapons/rpg/rocket1.wav"
local SND_FLY      = "weapons/rpg/rocket_fly.wav"
local SND_DETONATE = "weapons/explode5.wav"
local FX_EXPLODE   = "Explosion"

-- Inline lerp -- avoids math.Lerp which is absent in some GMod builds
local function lerp(t, a, b)  return a + (b - a) * t  end
local function clamp(v, lo, hi)  return v < lo and lo or v > hi and hi or v  end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile_closed.mdl")
    self:SetModelScale(10)

    -- Pure kinematic flight: MOVETYPE_FLY + SetLocalVelocity
    -- NO PhysicsInit -- physics objects fight kinematic velocity
    self:SetMoveType(MOVETYPE_FLY)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-4,-4,-4), Vector(4,4,4))
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)
    self:SetGravity(0)
    self._spawnTime = CurTime()
    self._detonated = false

    if not self.Target or self.Target == vector_origin then
        print("[GekkoNikita] ERROR: no Target -- self-destructing")
        timer.Simple(0.2, function() if IsValid(self) then self:Remove() end end)
        return
    end

    self._target = self.Target
    self:SetTargetPos(self._target)

    local dir = (self._target - self:GetPos()):GetNormalized()
    self:SetAngles(dir:Angle())
    self:SetLocalVelocity(dir * SPEED_INITIAL)

    self:EmitSound(SND_LAUNCH, 80, 100, 1)
    timer.Simple(0.3, function()
        if IsValid(self) then self:EmitSound(SND_FLY, 75, 95, 1) end
    end)
    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Detonate() end
    end)

    self:NextThink(CurTime())
end

-- ============================================================
--  Think
-- ============================================================
function ENT:Think()
    if not self._target then
        self:NextThink(CurTime() + 0.1)
        return true
    end

    local age   = CurTime() - (self._spawnTime or CurTime())
    local t     = clamp(age / SPEED_RAMP_TIME, 0, 1)
    local speed = lerp(t, SPEED_INITIAL, SPEED_CRUISE)

    local pos  = self:GetPos()
    local want = (self._target - pos):GetNormalized()
    local cur  = self:GetForward()

    -- Steer: inline per-component lerp, fully server-safe
    local f   = clamp(TURN_RATE, 0, 1)
    local nx  = cur.x + (want.x - cur.x) * f
    local ny  = cur.y + (want.y - cur.y) * f
    local nz  = cur.z + (want.z - cur.z) * f
    local len = math.sqrt(nx*nx + ny*ny + nz*nz)
    if len < 0.0001 then
        nx, ny, nz = want.x, want.y, want.z
    else
        nx = nx/len ; ny = ny/len ; nz = nz/len
    end

    local newDir = Vector(nx, ny, nz)
    self:SetAngles(newDir:Angle())
    self:SetLocalVelocity(newDir * speed)

    if pos:Distance(self._target) < PROX_DETONATE then
        self:Detonate()
        return
    end

    self:NextThink(CurTime())
    return true
end

-- ============================================================
--  Touch
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
    eff:SetScale(1) ; eff:SetMagnitude(3)
    util.Effect(FX_EXPLODE, eff)
    self:EmitSound(SND_DETONATE, 120, 100, 1)
    self:Remove()
end
