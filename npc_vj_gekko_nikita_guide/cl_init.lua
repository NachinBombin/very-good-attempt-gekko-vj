include("shared.lua")

-- Client-side stub for potential future HUD / debug drawing.

function ENT:Draw()
    -- By default we do not draw anything client-side so the guide stays
    -- effectively invisible during normal play.  Uncomment for debugging:
    -- self:DrawModel()
end
