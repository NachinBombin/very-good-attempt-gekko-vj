-- cl_init.lua  (CLIENT)
-- Render-only: model + rockettrail particle + engine dynamic light.
-- Position is driven entirely by the server Think(); no client Think needed.
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

    -- Thruster/tracer particle  (same system as orbital RPG)
   
    -- Persistent dynamic light  (warm tracer glow, smaller than RPG)
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.style      = 0
        dlight.r          = 250
        dlight.g          = 220
        dlight.b          = 70
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

    -- Keep the dynamic light anchored to current position each frame
    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end
end

-- =========================================================================
-- Cleanup
-- =========================================================================
function ENT:OnRemove()
    if IsValid(self._thrusterPart) then
        self._thrusterPart:StopEmission()
    end
end