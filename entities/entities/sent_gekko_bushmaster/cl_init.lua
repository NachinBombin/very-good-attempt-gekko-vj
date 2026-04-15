-- cl_init.lua (CLIENT)
include("shared.lua")

function ENT:Initialize()
    self._birthTime = self:GetBirthTime()
    self._origin    = self:GetSpawnPos()
    self._forward   = self:GetSpawnDir()

    local fwd   = self._forward
    local right = fwd:Cross(Vector(0, 0, 1))
    if right:LengthSqr() < 0.001 then right = fwd:Cross(Vector(0, 1, 0)) end
    right:Normalize()
    local up = right:Cross(fwd)
    up:Normalize()
    self._right = right
    self._up    = up
    self._fixedAngle = self:GetAngles()
end

local SPEED          = 2900
local ORBIT_RADIUS_A = 5
local ORBIT_RADIUS_B = 3
local ORBIT_SPEED    = 4.5

function ENT:Think()
    local t      = CurTime() - (self._birthTime or self:GetBirthTime())
    local phase  = t * ORBIT_SPEED
    local centre = (self._origin or self:GetSpawnPos()) + (self._forward or self:GetSpawnDir()) * (SPEED * t)
    local right  = self._right or Vector(1,0,0)
    local up     = self._up    or Vector(0,0,1)
    local offset = right * (ORBIT_RADIUS_A * math.cos(phase))
                 + up    * (ORBIT_RADIUS_B * math.sin(phase))
    self:SetPos(centre + offset)
    self:SetAngles(self._fixedAngle or self:GetAngles())
    self:NextClientThink(CurTime())
    return true
end

function ENT:Draw()
    self:DrawModel()
    -- Tracer-style glow
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.Pos     = self:GetPos()
        dlight.r       = 255
        dlight.g       = 200
        dlight.b       = 80
        dlight.Brightness = 1.5
        dlight.Size    = 48
        dlight.Decay   = 800
        dlight.DieTime = CurTime() + 0.05
    end
end