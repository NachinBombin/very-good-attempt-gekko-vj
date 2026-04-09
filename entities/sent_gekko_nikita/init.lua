AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile  (sent_gekko_nikita)
--
--  MOVETYPE_FLY: no VPhysics object at all.
--  Steering and thrust run in Think() every tick.
--  This mirrors exactly how the reference Nikita weapon works
--  (SetVelocity on a non-VPhysics entity = instant, reliable).
--
--  Decoupled knobs:
--    CRUISE_SPEED = forward speed in u/s  (never changes)
--    TRACK_LERP   = per-tick angle blend   (controls turn radius)
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED     = 280    -- u/s forward at all times
local TRACK_LERP       = 0.05   -- per-tick angle blend (bigger = tighter turns)
local LIFETIME         = 45     -- seconds until self-destruct
local PROXIMITY_RADIUS = 180    -- u to target for proximity detonation
local ENGINE_DELAY     = 0.5    -- seconds before homing + full speed engage

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )

    -- MOVETYPE_FLY: pure kinematic movement, no VPhysics object.
    -- Entity:SetVelocity() works every Think() tick with zero overhead.
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

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        self.Target = self:GetPos() + fwd * 2000
        print( "[GekkoNikita] WARNING: no Target set -- using fallback" )
    end
    self:SetTargetPos( self.Target )
    self:SetEngineStarted( false )

    -- Gentle nudge so it moves immediately even before engine fires
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
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  Think  --  steering + thrust + lifetime + proximity det
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    -- Lifetime check
    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if self.EngineActive then
        -- Resolve aim position
        local aimPos
        if IsValid( self.TrackEnt ) then
            aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
        elseif self.Target then
            aimPos = self.Target
        end

        if aimPos then
            -- Proximity detonation
            if ( self:GetPos() - aimPos ):Length() < PROXIMITY_RADIUS then
                self:MissileDoExplosion()
                return true
            end

            -- Steering: blend current facing toward target
            -- Only changes angle, never touches speed
            local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
            self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )
        end

        -- Thrust: always exactly CRUISE_SPEED along current facing
        -- SetVelocity on MOVETYPE_FLY is applied instantly, no accumulation
        self:SetVelocity( self:GetForward() * CRUISE_SPEED )
    end

    return true
end

-- ============================================================
--  Touch  --  collision detection (replaces PhysicsCollide)
-- ============================================================
function ENT:Touch( ent )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end   -- brief spawn immunity
    if ent == self.Owner then return end
    self:MissileDoExplosion()
end

-- ============================================================
--  OnTakeDamage  --  can be shot down
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

-- ============================================================
--  MissileDoExplosion
-- ============================================================
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

-- ============================================================
--  OnRemove
-- ============================================================
function ENT:OnRemove()
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
end
