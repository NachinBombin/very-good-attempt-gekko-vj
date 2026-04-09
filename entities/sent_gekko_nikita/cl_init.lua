-- ============================================================
--  sent_gekko_nikita / cl_init.lua  (CLIENT)
--
--  Visual presentation of the Gekko Nikita missile:
--    * 10x-scaled model
--    * Vanilla rockettrail particle attached to point 0
--    * Orange dynamic light that follows the missile
--    * Faint red targeting line drawn toward the fixed target
--      position broadcast by the server via TargetPos NetworkVar
--
--  NO game logic lives here.  Target authority belongs entirely
--  to the server (npc_vj_gekko/init.lua :: FireNikita).
-- ============================================================
include("shared.lua")

function ENT:Initialize()
    if not IsValid(self) then return end

    -- Expand render bounds to match 10x scale so the model
    -- doesn't get frustum-culled while still visible.
    self:SetRenderBounds(
        Vector(-120, -120, -120),
        Vector( 120,  120,  120)
    )

    -- Vanilla rocket trail particle
    local ok, part = pcall(CreateParticleSystem, self, "rockettrail", PATTACH_POINT_FOLLOW, 0)
    if ok and IsValid(part) then
        self._thrusterPart = part
    end

    -- Orange dynamic light sized for the 10x model
    self._dynLight = DynamicLight(self:EntIndex())
    if self._dynLight then
        self._dynLight.style      = 0
        self._dynLight.r          = 255
        self._dynLight.g          = 100
        self._dynLight.b          = 10
        self._dynLight.brightness = 4
        self._dynLight.size       = 280
        self._dynLight.decay      = 0
        self._dynLight.dietime    = CurTime() + 9999
    end
end

function ENT:Draw()
    self:DrawModel()

    -- Keep dynamic light glued to missile position
    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end

    -- Faint red line toward the fixed target position.
    -- TargetPos is a Vector NetworkVar set once on server Initialize().
    -- It points to where the Gekko told the missile to go -- never changes.
    local targetPos = self:GetTargetPos()
    if targetPos ~= vector_origin then
        render.DrawLine(
            self:GetPos(),
            targetPos,
            Color(255, 40, 40, 80),
            true
        )
    end
end

function ENT:OnRemove()
    -- Clean up particle system so it doesn't linger after detonation
    if IsValid(self._thrusterPart) then
        self._thrusterPart:StopEmission()
    end
end
