AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile  (sent_gekko_nikita)
--
--  Uses ENTITY:PhysicsSimulate via StartMotionController.
--  PhysicsSimulate is called by the motion controller every
--  tick and is NEVER skipped due to the physobj sleeping.
--  (PhysicsUpdate was silently skipped because SetVelocity +
--  no gravity caused the physobj to sleep between ticks.)
--
--  Thrust and steering are fully decoupled:
--    * Steering: SetAngles via LerpAngle only
--    * Thrust:   return angular/linear velocity from PhysicsSimulate
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- Forward speed in u/s. Player sprint ~340. 220 = nearly outrunnable.
local CRUISE_SPEED = 220

-- Turning rate per tick. 0.04 = lazy wide arcs.
local TRACK_LERP   = 0.04

local LIFETIME              = 45
local COLLISION_IMMUNE_TIME = 0.5
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
        phys:EnableDrag( false )
        phys:EnableGravity( false )
        -- StartMotionController registers PhysicsSimulate.
        -- Unlike PhysicsUpdate, PhysicsSimulate is driven by the
        -- motion controller and is NEVER skipped due to sleep.
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
--  PhysicsSimulate
--
--  Called by the motion controller every tick -- never skipped
--  due to physobj sleep.  This is the correct hook to use with
--  StartMotionController.
--
--  Returns SIM_GLOBAL_ACCELERATION to let the engine apply our
--  requested velocity each tick.
-- ============================================================
function ENT:PhysicsSimulate( phys, deltaTime )
    -- Always keep physobj awake
    phys:Wake()

    if not self.ActivatedAlmonds then
        return
    end

    -- Resolve aim position
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    elseif self.Target then
        aimPos = self.Target
    end

    -- Steer: only changes facing angle, never affects speed
    if aimPos then
        local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
        self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )
    end

    -- Thrust: lock velocity to exactly CRUISE_SPEED along current forward
    phys:SetVelocity( self:GetForward() * CRUISE_SPEED )

    return SIM_NOTHING  -- we set velocity directly, no further sim needed
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
