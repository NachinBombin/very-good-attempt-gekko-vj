-- cl_init.lua  (CLIENT)
-- Render-only client file for sent_gekko_bushmaster.
-- The server drives position entirely via Think().
-- The client just draws the model + a small dynamic light.
include("shared.lua")

function ENT:Initialize()
    -- nothing needed; server sets pos/ang
end

function ENT:Draw()
    self:DrawModel()

    -- Small tracer-style glow so the round is visible in flight
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.Pos        = self:GetPos()
        dlight.r          = 255
        dlight.g          = 200
        dlight.b          = 80
        dlight.Brightness = 1.5
        dlight.Size       = 48
        dlight.Decay      = 800
        dlight.DieTime    = CurTime() + 0.05
    end
end
