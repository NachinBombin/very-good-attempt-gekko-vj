-- ============================================================
--  sent_gekko_nikita / cl_init.lua
--  Client-side rendering only -- no game logic lives here.
--  The entity is invisible (model handles visuals); we only
--  ensure it draws when it needs to.
-- ============================================================
include("shared.lua")

function ENT:Draw()
    self:DrawModel()
end
