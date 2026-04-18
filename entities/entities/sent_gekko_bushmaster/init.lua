-- init.lua  (SERVER)
-- M242 Bushmaster 25mm round.
-- Position is set entirely by the Gekko's FireBushmaster logic.
-- No position manipulation here.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GekkoBulletImpact")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 2900
local ORBIT_RADIUS_A = 4
local ORBIT_RADIUS_B = 3
local ORBIT_SPEED    = 4.5
local LIFETIME       = 12
local DAMAGE         = 40
local BLAST_RADIUS   = 10

-- =========================================================================
-- Helper: broadcast the bullet impact projected light
-- =========================================================================
local function SendBulletImpact(pos, normal, presetID)
    net.Start("GekkoBulletImpact")
        net.WriteVector(pos)
        net.WriteVector(normal)
        net.WriteUInt(presetID, 3)   -- 3 bits: matches ReadUInt(3) in bullet_impact_system.lua
    net.Broadcast()
end

-- =========================================================================
-- Initialize
-- =========================================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile.mdl")
    self:SetModelScale(0.40, 0)
    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-4, -4, -4), Vector(4, 4, 4))
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)

    local now = CurTime()
    self:SetBirthTime(now)
    self:SetSpawnPos(self:GetPos())
    self:SetSpawnDir(self:GetForward())

    self._birthTime  = now
    self._origin     = self:GetPos()
    self._forward    = self:GetForward()

    local fwd   = self._forward
    local right = fwd:Cross(Vector(0, 0, 1))
    if right:LengthSqr() < 0.001 then
        right = fwd:Cross(Vector(0, 1, 0))
    end
    right:Normalize()
    local up = right:Cross(fwd)
    up:Normalize()
    self._right      = right
    self._up         = up
    self._fixedAngle = self:GetAngles()

    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- Think
-- =========================================================================
function ENT:Think()
    local t     = CurTime() - self._birthTime
    local phase = t * ORBIT_SPEED

    local centre = self._origin + self._forward * (SPEED * t)
    local offset = self._right * (ORBIT_RADIUS_A * math.cos(phase))
                 + self._up    * (ORBIT_RADIUS_B * math.sin(phase))
    local newPos = centre + offset

    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = newPos,
        filter = { self, self:GetOwner() },
        mask   = MASK_SHOT,
    })

    if tr.Hit then
        self:Explode(tr.HitPos, tr.HitNormal, tr.Entity)
        return
    end

    self:SetPos(newPos)
    self:SetAngles(self._fixedAngle)
    self:NextThink(CurTime())
    return true
end

-- =========================================================================
-- Touch
-- =========================================================================
function ENT:Touch(other)
    if other == self:GetOwner() then return end
    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = self:GetPos() + self:GetForward() * 8,
        filter = { self, self:GetOwner() },
        mask   = MASK_SHOT,
    })
    self:Explode(tr.HitPos, tr.HitNormal, other)
end

-- =========================================================================
-- Explode
-- =========================================================================
function ENT:Explode(hitPos, hitNormal, hitEnt)
    if self._exploded then return end
    self._exploded = true

    -- Bullet impact projected light — presetID 2 = BUSHMASTER
    SendBulletImpact(hitPos, hitNormal, 2)

    local dmg = DamageInfo()
    dmg:SetDamage(DAMAGE)
    dmg:SetAttacker(IsValid(self:GetOwner()) and self:GetOwner() or self)
    dmg:SetInflictor(self)
    dmg:SetDamageType(DMG_BLAST)
    dmg:SetDamagePosition(hitPos)
    dmg:SetDamageForce(hitNormal * -DAMAGE * 50)

    util.BlastDamage(self, IsValid(self:GetOwner()) and self:GetOwner() or self,
        hitPos, BLAST_RADIUS, DAMAGE)

    local eff = EffectData()
    eff:SetOrigin(hitPos)
    eff:SetNormal(hitNormal)
    eff:SetScale(1)
    util.Effect("Explosion", eff)

    self:Remove()
end