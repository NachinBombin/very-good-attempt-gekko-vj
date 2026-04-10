include("shared.lua")

-- ============================================================
--  CLIENT  -  Nikita Guide debug visualiser
--  Set NikitaGuideDebug NWBool true on the entity (server side)
--  to draw a beam from the guide to its current waypoint / target.
-- ============================================================

function ENT:Draw()
    -- Keep the guide invisible during normal play.
    -- Uncomment the next line to see the model while debugging:
    -- self:DrawModel()

    if not self:GetNWBool("NikitaGuideDebug", false) then return end

    local targetPos = self:GetNWVector("NikitaGuideTarget", self:GetPos())
    local myPos     = self:GetPos()

    render.SetColorMaterial()
    render.DrawLine(myPos, targetPos, Color(0, 255, 128), true)
end
