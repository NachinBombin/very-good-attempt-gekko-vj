include( "shared.lua" )

-- ============================================================
--  CLIENT  -  sent_npc_trackmissile
--  Identical visuals to sent_npc_topmissile:
--    LAUNCH WINDOW : sparks (muzzleflash1) + clear white steam
--    ENGINE ON     : scud_trail prop + grey exhaust + beam/heatwave
-- ============================================================

local matHeatWave = Material( "sprites/heat_shimmer" )
local matFire     = Material( "effects/fire_cloud1" )

ENT.NozzlePos = Vector( -12, 0, 0 )

function ENT:Initialize()
    self:SetRenderMode( RENDERMODE_NORMAL )
    local pos     = self:LocalToWorld( self.NozzlePos )
    self.Emitter  = ParticleEmitter( pos, false )
    self.Seed     = math.Rand( 0, 10000 )
    self.Emittime = 0
    self.OnStart  = CurTime()
end

function ENT:Think()
    self:NextThink( CurTime() )
    return true
end

function ENT:Draw()
    self:DrawModel()

    if not self.Emitter or not self.Emitter:IsValid() then
        local pos    = self:LocalToWorld( self.NozzlePos )
        self.Emitter = ParticleEmitter( pos, false )
        self.Seed    = math.Rand( 0, 10000 )
        self.OnStart = CurTime()
    end

    if not self.Emittime then self.Emittime = 0 end
    if self.Emittime >= CurTime() then return end
    self.Emittime = CurTime()

    local engineOn = self:GetNWBool( "EngineStarted", false )
    local nozzle   = self:LocalToWorld( self.NozzlePos )
    local fwd      = self:GetForward()
    local vel      = self:GetVelocity()

    -- -------------------------------------------------------
    --  PRE-IGNITION  -  sparks + clear white steam
    -- -------------------------------------------------------
    if not engineOn then

        for i = 1, 8 do
            local sp = self.Emitter:Add( "effects/muzzleflash1", nozzle )
            if sp then
                local randDir = VectorRand():GetNormalized()
                sp:SetVelocity(
                    fwd * math.Rand( -600, -200 )
                    + randDir * math.Rand( 80, 280 )
                )
                sp:SetDieTime( math.Rand( 0.04, 0.12 ) )
                sp:SetStartAlpha( 255 )
                sp:SetEndAlpha( 0 )
                sp:SetStartSize( math.Rand( 3, 7 ) )
                sp:SetEndSize( 0 )
                sp:SetRoll( math.Rand( 0, 360 ) )
                sp:SetRollDelta( math.Rand( -8, 8 ) )
                sp:SetColor( math.random(230,255), math.random(200,245), 80 )
                sp:SetLighting( false )
                sp:SetGravity( Vector( 0, 0, -120 ) )
                sp:SetAirResistance( 20 )
            end
        end

        for i = 1, 3 do
            local sm = self.Emitter:Add(
                "particle/smokesprites_000" .. math.random(1,9),
                nozzle + Vector( math.Rand(-4,4), math.Rand(-4,4), 0 )
            )
            if sm then
                sm:SetVelocity(
                    fwd * math.Rand( -250, -80 )
                    + Vector( math.Rand(-50,50), math.Rand(-50,50), math.Rand(60,180) )
                )
                sm:SetDieTime( math.Rand( 0.45, 0.85 ) )
                sm:SetStartAlpha( math.Rand( 160, 220 ) )
                sm:SetEndAlpha( 0 )
                sm:SetStartSize( math.Rand( 20, 36 ) )
                sm:SetEndSize( math.Rand( 90, 160 ) )
                sm:SetRoll( math.Rand( 0, 360 ) )
                sm:SetRollDelta( math.Rand( -1.5, 1.5 ) )
                sm:SetColor( 255, 255, 255 )
                sm:SetLighting( false )
                sm:SetAirResistance( 45 )
                sm:SetGravity( Vector( 0, 0, 70 ) )
            end
        end

        return
    end

    -- -------------------------------------------------------
    --  ENGINE ON  -  original exhaust
    -- -------------------------------------------------------

    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.Pos        = self:GetPos()
        dlight.r          = 250 + math.random(-5,5)
        dlight.g          = 170 + math.random(-5,5)
        dlight.b          = 0
        dlight.Brightness = 1
        dlight.Decay      = 0.1
        dlight.Size       = 2048
        dlight.DieTime    = CurTime() + 0.15
    end

    for i = 1, 3 do
        local particle = self.Emitter:Add(
            "particle/smokesprites_000" .. math.random(1,9), nozzle
        )
        if particle then
            particle:SetVelocity(
                ( vel / 10 ) * -1
                + Vector( math.Rand(-2.5,2.5), math.Rand(-2.5,2.5), math.Rand(2.5,15.5) )
                + fwd * -280
            )
            particle:SetDieTime( math.Rand( 0.42, 0.725 ) )
            particle:SetStartAlpha( math.Rand( 35, 65 ) )
            particle:SetEndAlpha( 0 )
            particle:SetStartSize( math.Rand( 12, 14 ) )
            particle:SetEndSize( math.Rand( 25, 35 ) )
            particle:SetRoll( math.Rand( 0, 360 ) )
            particle:SetRollDelta( math.Rand( -1, 1 ) )
            particle:SetColor(
                math.Rand( 185, 205 ),
                math.Rand( 185, 205 ),
                math.Rand( 180, 205 )
            )
            particle:SetAirResistance( 100 )
            particle:SetGravity(
                fwd * -500
                + VectorRand():GetNormalized() * math.Rand( -140, 140 )
                + Vector( 0, 0, math.random( -15, 15 ) )
            )
        end
    end

    local vOffset = nozzle
    local vNormal = ( vOffset - self:GetPos() ):GetNormalized()
    local scroll  = self.Seed + ( CurTime() * -10 )
    local Scale   = 0.5

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                           32*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 60  * Scale,   16*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 148 * Scale,   16*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()

    scroll = scroll * 0.5
    render.UpdateRefractTexture()
    render.SetMaterial( matHeatWave )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                           45*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 16 * Scale,    16*Scale, scroll + 2, Color( 255, 255, 255, 255 ) )
        render.AddBeam( vOffset + vNormal * 64 * Scale,    24*Scale, scroll + 5, Color(   0,   0,   0,   0 ) )
    render.EndBeam()

    scroll = scroll * 1.3
    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                           8*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 32  * Scale,   8*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 108 * Scale,   8*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()
end

function ENT:OnRemove()
    if self.Emitter then
        self.Emitter:Finish()
        self.Emitter = nil
    end
end
