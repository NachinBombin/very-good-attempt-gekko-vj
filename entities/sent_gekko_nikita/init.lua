AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile  (sent_gekko_nikita)
--
--  Flight model based on the reference player-controlled Nikita:
--    phys:SetVelocity( self:GetForward() * CRUISE_SPEED )
--
--  This fully decouples thrust from steering:
--    * Forward speed is ALWAYS exactly CRUISE_SPEED, every tick.
--    * Steering is ONLY SetAngles() via LerpAngle.
--    * No ApplyForceCenter, no accumulation, no momentum bleed.
--    * Gravity disabled so speed stays constant on any heading.
--
--  Result: missile turns effortlessly at any TRACK_LERP value
--  without the speed changing at all.  Tune only two values:
--    CRUISE_SPEED  -- how fast it moves forward
--    TRACK_LERP    -- how tightly it turns per tick (0=never, 1=instant)
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- Forward speed in u/s, locked every tick. Player sprint ~340.
-- 220 = slower than a sprinting player, very dodgeable.
local CRUISE_SPEED          = 220

-- Turning rate per physics tick. 0.04 = lazy wide arcs.
-- Completely independent of speed now -- changing this only
-- affects how tightly it curves, never how fast it goes.
local TRACK_LERP            = 0.04

local LIFETIME              = 45
local COLLISION_IMMUNE_TIME = 0.5

-- Brief upward kick before engine ignites (no gravity during kick
-- either, so this just sets initial direction cleanly).
local KICK_UP_SPEED         = 180

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:SetModelScale( 2, 0 )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 500 )
        phys:EnableDrag( false )    -- no drag: speed is set directly
        phys:EnableGravity( false ) -- no gravity: speed is set directly
        self:StartMotionController()
    end

    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.SpawnTime        = CurTime()
    self.HealthVal        = 50
    self.Damage           = 0
    self.Radius           = 0

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[GekkoNikita] WARNING: no Target set -- using fallback" )
    end

    self:SetTargetPos( self.Target )

    -- Initial upward kick so missile visually lofts before engine
    local selfRef = self
    timer.Simple( 0, function()
        if not IsValid( selfRef ) then return end
        local phys2 = selfRef:GetPhysicsObject()
        if not IsValid( phys2 ) then return end
        phys2:SetVelocity( Vector( 0, 0, 1 ) * KICK_UP_SPEED )
    end )

    sound.Play( SND_LAUNCH, self:GetPos(), 511, 60 )
    self.EngineSound = CreateSound( self, SND_ENGINE )

    timer.Simple( 0.75, function()
        if IsValid( selfRef ) and not selfRef.Destroyed then
            selfRef:FireEngine()
        end
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  FireEngine
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 700,  1024 )
    self.EngineSound:PlayEx( 511, 100 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )

    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetUp(), 180 )

    local prop = ents.Create( "prop_physics" )
    if IsValid( prop ) then
        prop:SetPos( self:LocalToWorld( Vector( -15, 0, 0 ) ) )
        prop:SetAngles( a )
        prop:SetParent( self )
        prop:SetModel( "models/items/ar2_grenade.mdl" )
        prop:Spawn()
        prop:SetRenderMode( RENDERMODE_TRANSALPHA )
        prop:SetColor( Color( 0, 0, 0, 0 ) )
        ParticleEffectAttach( "scud_trail", PATTACH_ABSORIGIN_FOLLOW, prop, 0 )
    end
end

-- ============================================================
--  PhysicsUpdate
--
--  KEY PATTERN (from reference player-nikita):
--    phys:SetVelocity( self:GetForward() * CRUISE_SPEED )
--
--  SetVelocity replaces the velocity entirely each tick.
--  The missile always moves at exactly CRUISE_SPEED in whatever
--  direction it is currently facing.  Steering (SetAngles) and
--  thrust (SetVelocity) are 100% independent.
-- ============================================================
function ENT:PhysicsUpdate( phys, deltatime )
    if not self.ActivatedAlmonds then return end
    if not IsValid( phys ) then return end

    -- Resolve aim position
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    elseif self.Target then
        aimPos = self.Target
    end

    -- Steer toward aim: only changes facing angle, never speed
    if aimPos then
        local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
        self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )
    end

    -- Lock forward speed exactly: no accumulation, no momentum, no gravity bleed
    phys:SetVelocity( self:GetForward() * CRUISE_SPEED )
end

-- ============================================================
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < COLLISION_IMMUNE_TIME then return end
    if not self.ActivatedAlmonds then return end
    self:MissileDoExplosion()
end

-- ============================================================
--  Think  -- proximity detonation + lifetime
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if self.ActivatedAlmonds then
        local checkPos
        if IsValid( self.TrackEnt ) then
            checkPos = self.TrackEnt:GetPos()
        elseif self.Target then
            checkPos = self.Target
        end
        if checkPos and ( self:GetPos() - checkPos ):Length() < 180 then
            self:MissileDoExplosion()
            return true
        end
    end

    return true
end

-- ============================================================
--  OnTakeDamage  -- can be shot down
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
    ParticleEffect( "vj_explosion3", pos, Angle( 0, 0, 0 ) )

    local ed = EffectData()
    ed:SetOrigin( pos )
    util.Effect( "Explosion", ed )

    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",     tostring( rad ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() pe:Activate()
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
