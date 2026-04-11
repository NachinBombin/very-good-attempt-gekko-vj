-- cl_init.lua  (CLIENT)
-- Handles rendering: the missile model + vanilla RPG thruster trail + smoke.

include("shared.lua")

-- =========================================================================
-- Initialise
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end

    self:SetRenderBounds(
        Vector(-32, -32, -32),
        Vector( 32,  32,  32)
    )

    -- ----------------------------------------------------------------
    -- Thruster / glow particle  (matches vanilla RPG)
    -- SetOwner is a server-only concept on base_entity; the particle
    -- system does not need an owner on the client side.
    -- ----------------------------------------------------------------
    local ok, part = pcall(CreateParticleSystem, self, "rockettrail", PATTACH_POINT_FOLLOW, 0)
    if ok and IsValid(part) then
        self._thrusterPart = part
    end

    -- ----------------------------------------------------------------
    -- Dynamic light (orange engine glow)
    -- ----------------------------------------------------------------
    self._dynLight = DynamicLight(self:EntIndex())
    if self._dynLight then
        self._dynLight.style      = 0
        self._dynLight.r          = 255
        self._dynLight.g          = 160
        self._dynLight.b          = 30
        self._dynLight.brightness = 2
        self._dynLight.size       = 80
        self._dynLight.decay      = 0
        self._dynLight.dietime    = CurTime() + 9999
    end
end

-- =========================================================================
-- Draw
-- =========================================================================
function ENT:Draw()
    self:DrawModel()

    if self._dynLight then
        local pos = self:GetPos()
        self._dynLight.pos     = pos
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
