AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile
--
--  MOVETYPE_FLY + Think()-based steering.
--  Turn rate is CLAMPED (degrees/sec), not LerpAngle.
--  LerpAngle overshoots 180deg in a single tick at low lerp
--  values -> velocity explodes.  A clamped rate is stable.
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED     = 280     -- u/s, constant
local MAX_TURN_RATE    = 55      -- degrees per second max turn
local LIFETIME         = 45
local PROXIMITY_RADIUS = 180
local ENGINE_DELAY     = 0.5

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

    -- TrackEnt / Target / Owner are set by FireNikita AFTER Spawn()
    -- via timer.Simple(0) to survive the engine's post-Spawn table reset.
    -- Initialize() reads them as nil here -- that is expected and safe.

    self:SetEngineStarted( false )
    self:SetVelocity( self:GetForward() * 120 )

    sound.Play( SND_LAUNCH, self:GetPos(), 511, 60 )

    local selfRef = self
    timer.Simple( ENGINE_DELAY, function()
        if not IsValid( selfRef ) or selfRef.Destroyed then return end
        selfRef.Damage = math.random( 2500, 4500 )
        selfRef.Radius = math.random( 700,  1024 )
        selfRef.EngineActive = true
        selfRef:SetEngineStarted( true )
        print( "[NikitaDBG] Engine ACTIVE | TrackEnt=" .. tostring( selfRef.TrackEnt )
            .. " Target=" .. tostring( selfRef.Target ) )
    end )

    self:NextThink( CurTime() )
end

function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion() ; return true
    end

    if not self.EngineActive then return true end

    -- Resolve aim position
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    elseif self.Target then
        aimPos = self.Target
    end

    if aimPos then
        -- Proximity det
        if ( self:GetPos() - aimPos ):Length() < PROXIMITY_RADIUS then
            self:MissileDoExplosion() ; return true
        end

        -- Clamped turn rate: never rotate more than MAX_TURN_RATE deg/sec.
        -- This is stable regardless of angle difference, unlike LerpAngle
        -- which can overshoot 180deg in one tick and flip the missile.
        local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
        local curAngle  = self:GetAngles()
        local dt        = FrameTime()
        local maxDelta  = MAX_TURN_RATE * dt

        local function ClampAngle( cur, want )
            local diff = math.NormalizeAngle( want - cur )
            return cur + math.Clamp( diff, -maxDelta, maxDelta )
        end

        self:SetAngles( Angle(
            ClampAngle( curAngle.p, wantAngle.p ),
            ClampAngle( curAngle.y, wantAngle.y ),
            0
        ))
    end

    -- Thrust always along current facing at constant speed
    self:SetVelocity( self:GetForward() * CRUISE_SPEED )

    -- Debug every 0.5s
    if CurTime() > self._nextDebug then
        self._nextDebug = CurTime() + 0.5
        print( string.format(
            "[NikitaDBG] aimPos=%s trackValid=%s ang=%s spd=%.0f",
            tostring( aimPos ), tostring( IsValid( self.TrackEnt ) ),
            tostring( self:GetAngles() ), self:GetVelocity():Length()
        ))
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
    self:StopParticles()
    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 700
    local owner = IsValid( self.Owner ) and self.Owner or self
    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )
    local ed = EffectData() ; ed:SetOrigin( pos ) ; util.Effect( "Explosion", ed )
    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",     tostring( rad ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() ; pe:Activate()
        pe:Fire( "Explode", "", 0 ) ; pe:Fire( "Kill", "", 0.5 )
    end
    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )
    self:Remove()
end

function ENT:OnRemove()
    self.Destroyed = true
    self:StopParticles()
end
