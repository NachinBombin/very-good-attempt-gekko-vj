-- init.lua (SERVER)
-- Gekko M242 Bushmaster 25mm Round
-- Orbits the centreline at 2900 u/s with a very tight ellipse.
-- On contact: small explosive burst (radius 25, damage 40, falloff with distance).

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 2900   -- units/s
local ORBIT_RADIUS_A = 5      -- ellipse semi-major (side)  [very small]
local ORBIT_RADIUS_B = 3      -- ellipse semi-minor (up)    [very small]
local ORBIT_SPEED    = 4.5    -- radians/s
local LIFETIME       = 6      -- seconds before self-removal
local DAMAGE         = 40     -- base damage at epicentre
local BLAST_RADIUS   = 25     -- explosion radius (units)

-- =========================================================================
-- Initialize
-- =========================================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile.mdl")
    self:SetModelScale(0.35, 0)   -- small round
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
    if right:LengthSqr() < 0.001 then right = fwd:Cross(Vector(0, 1, 0)) end
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
    if IsValid(other) and other ~= self:GetOwner() then
        self:Explode(self:GetPos(), Vector(0, 0, 1), other)
    end
end

-- =========================================================================
-- Explode  (distance-falloff damage)
-- =========================================================================
function ENT:Explode(pos, normal, hitEnt)
    local owner = IsValid(self:GetOwner()) and self:GetOwner() or self

    -- Small 25mm detonation effect
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(normal)
    ed:SetScale(0.25)
    util.Effect("Explosion", ed, true, true)

    -- Distance-falloff blast using util.BlastDamage (Source engine handles falloff natively)
    util.BlastDamage(self, owner, pos, BLAST_RADIUS, DAMAGE)

    -- Scorch
    util.Decal("Scorch", pos + normal, pos - normal)

    sound.Play("weapons/rpg/rocketfire1.wav", pos, 85, math.random(130, 150))

    self:Remove()
end

function ENT:OnRemove() end