AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile  (sent_gekko_nikita)
--
--  Movement: StartMotionController + PhysicsSimulate
--   Steering = LerpAngle toward target every sim tick
--   Thrust   = SetVelocity along current forward  (never accumulates)
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED          = 280      -- u/s forward at all times
local TRACK_LERP            = 0.05     -- per-tick angle blend  (bigger = tighter)
local LIFETIME              = 45       -- seconds until self-destruct
local PROXIMITY_RADIUS      = 180      -- u to target for proximity det
local COLLISION_IMMUNE_TIME = 0.6      -- seconds after spawn, ignore collisions
local ENGINE_DELAY          = 0.5      -- seconds before engine + tracking start

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    -- Use a compact model with a tiny VPhysics hull so it never
    -- clips through the floor on spawn.  No SetModelScale -- that
    -- resizes the visual only, NOT the VPhysics collision hull.
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    -- Ignore ALL entities for the first COLLISION_IMMUNE_TIME seconds.
    -- This prevents the missile from immediately detonating against
    -- the Gekko or the ground it spawned near.
    self:SetOwner( self.Owner )
    self:CollisionRulesChanged()
    local selfRef = self
    timer.Simple( COLLISION_IMMUNE_TIME, function()
        if not IsValid( selfRef ) then return end
        selfRef:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )
        selfRef:CollisionRulesChanged()
    end )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 60 )
        phys:EnableDrag( false )
        phys:EnableGravity( false )
        -- Give it a gentle initial nudge in the forward direction so it
        -- doesn't sit motionless for ENGINE_DELAY seconds.
        phys:SetVelocity( self:GetForward() * 120 )
        -- StartMotionController registers PhysicsSimulate.
        -- PhysicsSimulate is called every tick by the controller and is
        -- NEVER skipped due to physics sleep (unlike PhysicsUpdate).
        self:StartMotionController()
    end

    self.Destroyed       = false
    self.EngineActive    = false
    self.SpawnTime       = CurTime()
    self.HealthVal       = 50
    self.Damage          = 0
    self.Radius          = 0

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        self.Target = self:GetPos() + fwd * 2000
        print( "[GekkoNikita] WARNING: no Target set -- using fallback" )
    end

    self:SetTargetPos( self.Target )

    sound.Play( SND_LAUNCH, self:GetPos(), 511, 60 )
    self.EngineSound = CreateSound( self, SND_ENGINE )

    -- Delay homing + full speed until missile has cleared the spawn area
    timer.Simple( ENGINE_DELAY, function()
        if not IsValid( selfRef ) or selfRef.Destroyed then return end
        selfRef.Damage = math.random( 2500, 4500 )
        selfRef.Radius = math.random( 700,  1024 )
        selfRef.EngineSound:PlayEx( 1.0, 100 )
        selfRef.EngineActive = true
        selfRef:SetNWBool( "EngineStarted", true )
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  PhysicsSimulate  (motion controller tick -- never sleeps)
-- ============================================================
function ENT:PhysicsSimulate( phys, deltaTime )
    phys:Wake()

    if not self.EngineActive then
        -- Engine not started yet: coast on initial nudge velocity, no steering
        return SIM_NOTHING
    end

    -- Resolve aim position (live entity takes priority over static vector)
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    elseif self.Target then
        aimPos = self.Target
    end

    -- Steering: rotate facing toward target, leave speed untouched
    if aimPos then
        local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
        self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )
    end

    -- Thrust: always exactly CRUISE_SPEED along current facing
    phys:SetVelocity( self:GetForward() * CRUISE_SPEED )

    return SIM_NOTHING
end

-- ============================================================
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < COLLISION_IMMUNE_TIME then return end
    self:MissileDoExplosion()
end

-- ============================================================
--  Think  --  proximity detonation + lifetime
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if self.EngineActive then
        local checkPos
        if IsValid( self.TrackEnt ) then
            checkPos = self.TrackEnt:GetPos()
        elseif self.Target then
            checkPos = self.Target
        end
        if checkPos and ( self:GetPos() - checkPos ):Length() < PROXIMITY_RADIUS then
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
