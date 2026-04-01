include( "shared.lua" )

-- ============================================================
--  CLIENT  -  sent_npc_topmissile
--
--  LAUNCH WINDOW (0 → 0.75 s, before FireEngine):
--    - ManhackSparks burst every frame at nozzle
--    - Dense clear-white steam cloud (SmokeEffect, white tint,
--      large scale) so the coasting phase is clearly visible
--    - NO dark smoke at all in this phase
--
--  ENGINE ON (after FireEngine):
--    - Original scud_trail particle attachment on the prop
--    - Thin grey exhaust smoke trail (unchanged)
--    - Beam/heatwave exhaust (unchanged)
-- ============================================================

local matHeatWave = Material( "sprites/heat_shimmer" )
local matFire     = Material( "effects/fire_cloud1" )

ENT.NozzlePos = Vector( -12, 0, 0 )

-- -------------------------------------------------------
--  Spark helper  -  ManhackSparks burst at a world pos
-- -------------------------------------------------------
local function EmitLaunchSparks( pos, fwd )
    local e = EffectData()
    e:SetOrigin( pos )
    e:SetNormal( fwd )
    e:SetMagnitude( 6 )    -- spark count
    e:SetScale( 0.8 )      -- sprite scale
    e:SetRadius( 18 )      -- spread radius
    util.Effect( "ManhackSparks", e )
end

-- -------------------------------------------------------
--  Steam helper  -  one clear white SmokeEffect puff
--  Uses SmokeEffect (thin, white-grey wisp) at large
--  scale so it's clearly visible but never dark.
-- -------------------------------------------------------
local function EmitLaunchSteam( emitter, pos, fwd )
    -- Large, opaque-start, fast-fade white puff
    local p = emitter:Add( "effects/smokesprite0001", pos )
    if p then
        p:SetVelocity( fwd * -320
            + Vector( math.Rand(-40,40), math.Rand(-40,40), math.Rand(60,160) ) )
        p:SetDieTime( math.Rand( 0.5, 0.9 ) )
        p:SetStartAlpha( math.Rand( 180, 230 ) )
        p:SetEndAlpha( 0 )
        p:SetStartSize( math.Rand( 28, 42 ) )
        p:SetEndSize( math.Rand( 110, 180 ) )
        p:SetRoll( math.Rand( 0, 360 ) )
        p:SetRollDelta( math.Rand( -1.5, 1.5 ) )
        -- Pure white - absolutely no dark tint
        p:SetColor( 255, 255, 255 )
        p:SetAirResistance( 40 )
        p:SetGravity( Vector( 0, 0, 80 ) )
        p:SetLighting( false )
    end

    -- Second smaller wisp for volume
    local p2 = emitter:Add( "effects/smokesprite0001", pos
        + Vector( math.Rand(-8,8), math.Rand(-8,8), 0 ) )
    if p2 then
        p2:SetVelocity( fwd * -180
            + Vector( math.Rand(-60,60), math.Rand(-60,60), math.Rand(80,200) ) )
        p2:SetDieTime( math.Rand( 0.35, 0.65 ) )
        p2:SetStartAlpha( math.Rand( 120, 170 ) )
        p2:SetEndAlpha( 0 )
        p2:SetStartSize( math.Rand( 18, 30 ) )
        p2:SetEndSize( math.Rand( 70, 110 ) )
        p2:SetRoll( math.Rand( 0, 360 ) )
        p2:SetRollDelta( math.Rand( -2, 2 ) )
        p2:SetColor( 255, 255, 255 )
        p2:SetAirResistance( 55 )
        p2:SetGravity( Vector( 0, 0, 60 ) )
        p2:SetLighting( false )
    end
end

function ENT:Initialize()
    self:SetRenderMode( RENDERMODE_NORMAL )
    local pos    = self:LocalToWorld( self.NozzlePos )
    self.Emitter = ParticleEmitter( pos, false )
    self.Seed    = math.Rand( 0, 10000 )
    self.Emittime = 0
    self.OnStart  = CurTime()
end

function ENT:Think()
    self:NextThink( CurTime() )
    return true
end

-- ============================================================
--  Draw
-- ============================================================
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

    -- -------------------------------------------------------
    --  PRE-IGNITION  (launch window, engine not yet lit)
    --  → sparks + clear white steam ONLY, zero dark smoke
    -- -------------------------------------------------------
    if not engineOn then
        -- ManhackSparks every frame
        EmitLaunchSparks( nozzle, fwd )

        -- 2 white steam puffs per frame for a dense cloud
        EmitLaunchSteam( self.Emitter, nozzle, fwd )
        EmitLaunchSteam( self.Emitter,
            nozzle + Vector( math.Rand(-6,6), math.Rand(-6,6), math.Rand(0,12) ),
            fwd )
        return
    end

    -- -------------------------------------------------------
    --  ENGINE ON  -  original exhaust (unchanged)
    -- -------------------------------------------------------

    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        local c = Color( 250 + math.random(-5,5), 170 + math.random(-5,5), 0, 100 )
        dlight.Pos        = self:GetPos()
        dlight.r          = c.r
        dlight.g          = c.g
        dlight.b          = c.b
        dlight.Brightness = 1
        dlight.Decay      = 0.1
        dlight.Size       = 2048
        dlight.DieTime    = CurTime() + 0.15
    end

    for i = 1, 3 do
        local particle = self.Emitter:Add(
            "particle/smokesprites_000" .. math.random( 1, 9 ), nozzle
        )
        if particle then
            particle:SetVelocity(
                ( self:GetVelocity() / 10 ) * -1
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

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    if self.Emitter then
        self.Emitter:Finish()
        self.Emitter = nil
    end
end
