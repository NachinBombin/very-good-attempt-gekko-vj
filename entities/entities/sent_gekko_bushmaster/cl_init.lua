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
    local ok, part = pcall(CreateParticleSystem, self, "rockettrail", PATTACH_POINT_FOLLOW, 0)
    if ok and IsValid(part) then
        self._thrusterPart = part
    end

    -- Persistent dynamic light  (warm tracer glow, smaller than RPG)
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.style      = 0
        dlight.r          = 255
        dlight.g          = 200
        dlight.b          = 80
        dlight.brightness = 1.5
        dlight.size       = 48
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
