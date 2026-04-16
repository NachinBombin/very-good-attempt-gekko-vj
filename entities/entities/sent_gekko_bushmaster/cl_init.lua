-- cl_init.lua  (CLIENT)
-- Render-only: model + engine dynamic light.
-- Trail is attached server-side in FireBushmaster (init.lua) via util.SpriteTrail,
-- matching the same pattern as AttachGrenadeTrail.
include("shared.lua")

-- =========================================================================
-- Initialise
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end

    self:SetRenderBounds(
        Vector(-24, -24, -24),
        Vector( 24,  24,  24)
    )

    -- Acid-lime tracer light: r=180 g=255 b=40
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.style      = 0
        dlight.r          = 180
        dlight.g          = 255
        dlight.b          = 40
        dlight.brightness = 9.5
        dlight.size       = 30
        dlight.decay      = 0
        dlight.dietime    = CurTime() + 9999
    end
    self._dynLight = dlight
end

-- =========================================================================
-- Draw
-- =========================================================================
function ENT:Draw()
    self:DrawModel()

    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end
end

function ENT:OnRemove()
end
