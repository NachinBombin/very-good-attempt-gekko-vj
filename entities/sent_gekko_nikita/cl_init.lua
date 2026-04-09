include( "shared.lua" )

function ENT:Initialize()
    if not IsValid( self ) then return end

    self:SetRenderBounds(
        Vector( -120, -120, -120 ),
        Vector(  120,  120,  120 )
    )

    local ok, part = pcall( CreateParticleSystem, self, "rockettrail", PATTACH_POINT_FOLLOW, 0 )
    if ok and IsValid( part ) then
        self._thrusterPart = part
    end

    self._dynLight = DynamicLight( self:EntIndex() )
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

    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end

    local targetPos = self:GetTargetPos()
    if targetPos ~= vector_origin then
        render.DrawLine(
            self:GetPos(),
            targetPos,
            Color( 255, 40, 40, 80 ),
            true
        )
    end
end

function ENT:OnRemove()
    if IsValid( self._thrusterPart ) then
        self._thrusterPart:StopEmission()
    end
end
