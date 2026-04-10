include( "shared.lua" )

-- ============================================================
--  CLIENT  -  Gekko Nikita particle exhaust + boost swell
--
--  Boost value (0..1) is read from NWFloat "NikitaBoost" each tick.
--  At boost = 1:
--    * Fuchsia flame StartSize grows +10 units (35-45 -> 45-55)
--    * Dynamic light Size swells from 180 -> 260
-- ============================================================

function ENT:Initialize()
    self.Emitter = ParticleEmitter( self:GetPos(), false )
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:Think()
    if not IsValid( self.Emitter ) then return end

    local pos     = self:GetPos()
    local backDir = -self:GetForward()
    local exhaustPos = pos + backDir * 55

    -- Read boost from server (0 = cruise, 1 = full boost)
    local boost = self:GetNWFloat( "NikitaBoost", 0 )

    self.Emitter:SetPos( pos )

    -- --------------------------------------------------------
    --  Dynamic light: orange core, swells during boost
    -- --------------------------------------------------------
    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.pos        = exhaustPos
        dlight.r          = 255
        dlight.g          = 120
        dlight.b          = 20
        dlight.brightness = 3
        dlight.Decay      = 1200
        dlight.Size       = Lerp( boost, 180, 260 )   -- swell during boost
        dlight.DieTime    = CurTime() + 0.05
    end

    -- --------------------------------------------------------
    --  Orange flame core  (unchanged)
    -- --------------------------------------------------------
    for i = 1, 4 do
        local part = self.Emitter:Add( "particles/flamelet" .. math.random( 1, 5 ), exhaustPos + VectorRand() * 6 )
        if part then
            part:SetVelocity( backDir * math.Rand( 80, 200 ) + VectorRand() * 18 )
            part:SetDieTime( math.Rand( 0.08, 0.18 ) )
            part:SetStartAlpha( 220 )
            part:SetEndAlpha( 0 )
            part:SetStartSize( math.Rand( 18, 32 ) )
            part:SetEndSize( math.Rand( 4, 10 ) )
            part:SetColor( 255, math.random( 100, 180 ), 0 )
            part:SetRoll( math.Rand( 0, 360 ) )
            part:SetRollDelta( math.Rand( -2, 2 ) )
            part:SetGravity( Vector( 0, 0, 12 ) )
            part:SetCollide( false )
        end
    end

    -- --------------------------------------------------------
    --  Fuchsia flame layer  (swells +10 units at full boost)
    -- --------------------------------------------------------
    -- Base range: [35, 45].  At boost=1 range becomes [45, 55].
    local fuchsiaMin = Lerp( boost, 35, 45 )
    local fuchsiaMax = Lerp( boost, 45, 55 )

    for i = 1, 3 do
        local part = self.Emitter:Add( "particles/flamelet" .. math.random( 1, 5 ), exhaustPos + VectorRand() * 8 )
        if part then
            part:SetVelocity( backDir * math.Rand( 60, 160 ) + VectorRand() * 22 )
            part:SetDieTime( math.Rand( 0.10, 0.22 ) )
            part:SetStartAlpha( 180 )
            part:SetEndAlpha( 0 )
            part:SetStartSize( math.Rand( fuchsiaMin, fuchsiaMax ) )
            part:SetEndSize( math.Rand( 2, 8 ) )
            part:SetColor( 220, 0, 200 )   -- fuchsia
            part:SetRoll( math.Rand( 0, 360 ) )
            part:SetRollDelta( math.Rand( -3, 3 ) )
            part:SetGravity( Vector( 0, 0, 8 ) )
            part:SetCollide( false )
        end
    end

    -- --------------------------------------------------------
    --  Sparks  (unchanged)
    -- --------------------------------------------------------
    for i = 1, 3 do
        local part = self.Emitter:Add( "effects/spark", exhaustPos + VectorRand() * 4 )
        if part then
            part:SetVelocity( backDir * math.Rand( 200, 500 ) + VectorRand() * 40 )
            part:SetDieTime( math.Rand( 0.12, 0.30 ) )
            part:SetStartAlpha( 255 )
            part:SetEndAlpha( 0 )
            part:SetStartSize( math.Rand( 1, 3 ) )
            part:SetEndSize( 0 )
            part:SetColor( 255, 230, 180 )
            part:SetGravity( Vector( 0, 0, -280 ) )
            part:SetCollide( true )
            part:SetBounce( 0.2 )
        end
    end

    -- --------------------------------------------------------
    --  Light smoke wisp  (unchanged)
    -- --------------------------------------------------------
    if math.random( 1, 3 ) == 1 then
        local part = self.Emitter:Add( "particle/particle_smokegrenade", exhaustPos + backDir * math.Rand( 5, 20 ) )
        if part then
            part:SetVelocity( backDir * math.Rand( 20, 60 ) + VectorRand() * 10 )
            part:SetDieTime( math.Rand( 0.4, 0.8 ) )
            part:SetStartAlpha( 40 )
            part:SetEndAlpha( 0 )
            part:SetStartSize( math.Rand( 8, 16 ) )
            part:SetEndSize( math.Rand( 20, 40 ) )
            part:SetColor( 180, 180, 180 )
            part:SetRoll( math.Rand( 0, 360 ) )
            part:SetRollDelta( math.Rand( -1, 1 ) )
            part:SetGravity( Vector( 0, 0, 20 ) )
            part:SetCollide( false )
        end
    end
end

function ENT:OnRemove()
    if IsValid( self.Emitter ) then
        self.Emitter:Finish()
    end
end