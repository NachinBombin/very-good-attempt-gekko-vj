include( "shared.lua" )

-- ============================================================
--  CLIENT  -  Gekko Nikita Homing Cruise Missile
--
--  Visual FX borrowed from S-24 Rammer missile:
--    - ParticleEmitter spark trail at exhaust (tail = -GetForward()*20)
--    - DynamicLight orange glow at exhaust, 0.1s die-time per Think
--  Smoke sprite trail set server-side via util.SpriteTrail.
-- ============================================================

function ENT:Initialize()
    self.Emitter = ParticleEmitter( self:GetPos() )
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:Think()
    if not IsValid( self.Emitter ) then return end

    local pos       = self:GetPos()
    local backDir   = -self:GetForward()
    local exhaustPos = pos + backDir * 20

    self.Emitter:SetPos( pos )

    -- Orange dynamic light at exhaust
    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.pos        = exhaustPos
        dlight.r          = 255
        dlight.g          = 150
        dlight.b          = 50
        dlight.brightness = 2.5
        dlight.Decay      = 1000
        dlight.Size       = 140
        dlight.DieTime    = CurTime() + 0.1
    end

    -- Exhaust spark particles
    for i = 1, 2 do
        local part = self.Emitter:Add( "effects/spark", exhaustPos )
        if part then
            part:SetVelocity( backDir * math.Rand( 120, 350 ) + VectorRand() * 25 )
            part:SetDieTime( math.Rand( 0.15, 0.35 ) )
            part:SetStartAlpha( 255 )
            part:SetEndAlpha( 0 )
            part:SetStartSize( math.Rand( 2, 5 ) )
            part:SetEndSize( 0 )
            part:SetColor( 255, 200, 100 )
            part:SetGravity( Vector( 0, 0, -200 ) )
            part:SetCollide( false )
        end
    end
end

function ENT:OnRemove()
    if IsValid( self.Emitter ) then
        self.Emitter:Finish()
    end
end
