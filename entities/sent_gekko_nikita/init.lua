AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED     = 280
local TRACK_LERP       = 0.05
local LIFETIME         = 45
local PROXIMITY_RADIUS = 180
local ENGINE_DELAY     = 0.5

-- How often to print debug (seconds)
local DEBUG_INTERVAL   = 0.5

function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:SetMoveType( MOVETYPE_FLY )
    self:SetSolid( SOLID_BBOX )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )
    self:SetCollisionBounds( Vector( -8, -8, -8 ), Vector( 8, 8, 8 ) )

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = 50
    self.Damage       = 0
    self.Radius       = 0
    self._nextDebug   = 0

    -- ---- DEBUG: dump what was set before Spawn() ----
    print( "[NikitaDBG] Initialize()" )
    print( "  self.TrackEnt = " .. tostring( self.TrackEnt ) )
    print( "  self.Target   = " .. tostring( self.Target ) )
    print( "  self.Owner    = " .. tostring( self.Owner ) )
    -- --------------------------------------------------

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        self.Target = self:GetPos() + fwd * 2000
        print( "[NikitaDBG] WARNING: no Target on init -- fallback set" )
    end

    self:SetTargetPos( self.Target )
    self:SetEngineStarted( false )
    self:SetVelocity( self:GetForward() * 120 )

    sound.Play( SND_LAUNCH, self:GetPos(), 511, 60 )
    self.EngineSound = CreateSound( self, SND_ENGINE )

    local selfRef = self
    timer.Simple( ENGINE_DELAY, function()
        if not IsValid( selfRef ) or selfRef.Destroyed then return end
        selfRef.Damage = math.random( 2500, 4500 )
        selfRef.Radius = math.random( 700,  1024 )
        selfRef.EngineSound:PlayEx( 1.0, 100 )
        selfRef.EngineActive = true
        selfRef:SetEngineStarted( true )
        -- ---- DEBUG: dump state at engine start ----
        print( "[NikitaDBG] Engine ACTIVE" )
        print( "  TrackEnt valid = " .. tostring( IsValid( selfRef.TrackEnt ) ) )
        print( "  TrackEnt       = " .. tostring( selfRef.TrackEnt ) )
        print( "  Target         = " .. tostring( selfRef.Target ) )
        -- -------------------------------------------
    end )

    self:NextThink( CurTime() )
end

function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if self.EngineActive then
        local aimPos
        if IsValid( self.TrackEnt ) then
            aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
        elseif self.Target then
            aimPos = self.Target
        end

        -- ---- DEBUG every DEBUG_INTERVAL seconds ----
        if CurTime() > self._nextDebug then
            self._nextDebug = CurTime() + DEBUG_INTERVAL
            print( string.format(
                "[NikitaDBG] Think | aimPos=%s | trackValid=%s | angles=%s | vel=%s",
                tostring( aimPos ),
                tostring( IsValid( self.TrackEnt ) ),
                tostring( self:GetAngles() ),
                tostring( self:GetVelocity() )
            ))
        end
        -- ---------------------------------------------

        if aimPos then
            if ( self:GetPos() - aimPos ):Length() < PROXIMITY_RADIUS then
                self:MissileDoExplosion()
                return true
            end

            local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
            self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )
        end

        self:SetVelocity( self:GetForward() * CRUISE_SPEED )
    end

    return true
end

function ENT:Touch( ent )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.Owner then return end
    self:MissileDoExplosion()
end

function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 700
    local owner = IsValid( self.Owner ) and self.Owner or self
    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )
    local ed = EffectData()
    ed:SetOrigin( pos )
    util.Effect( "Explosion", ed )
    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",     tostring( rad ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() ; pe:Activate()
        pe:Fire( "Explode", "", 0 )
        pe:Fire( "Kill",    "", 0.5 )
    end
    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )
    self:Remove()
end

function ENT:OnRemove()
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
end
