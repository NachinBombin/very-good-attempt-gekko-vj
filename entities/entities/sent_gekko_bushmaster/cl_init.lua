-- cl_init.lua  (CLIENT)
-- Rendering only: model + dynamic light glow.
-- Server drives the position via MOVETYPE_NOCLIP; client just draws.

include("shared.lua")

function ENT:Initialize()
    if not IsValid(self) then return end
    self:SetRenderBounds(
        Vector(-32, -32, -32),
        Vector( 32,  32,  32)
    )

    -- Small orange/yellow muzzle glow to suggest a hot round in flight
    self._dynLight = DynamicLight(self:EntIndex())
    if self._dynLight then
        self._dynLight.style      = 0
        self._dynLight.r          = 255
        self._dynLight.g          = 200
        self._dynLight.b          = 80
        self._dynLight.brightness = 1.5
        self._dynLight.size       = 48
        self._dynLight.decay      = 0
        self._dynLight.dietime    = CurTime() + 9999
    end
end

function ENT:Draw()
    self:DrawModel()
    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end
end

function ENT:OnRemove()
end
