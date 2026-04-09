AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Tracking Missile  (sent_npc_trackmissile)
--
--  Arc phase:   IDENTICAL to sent_npc_topmissile.
--               Same FORCE_PER_TICK, SPEED_CAP, KICK_UP_SPEED,
--               same distance-based phase thresholds, same
--               LerpAngle rates.  Visual climb is identical.
--
--  Chase phase: Once the arc reaches its apex (Tracking = true)
--               the missile switches from the fixed Target vector
--               to the live TrackEnt entity position.
--               If TrackEnt has died it falls back to Target.
--
--  Differences from topmissile:
--    * Live homing after apex (topmissile stays on fixed Target)
--    * Fires sonar-lock net message on the client
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- Identical to topmissile
local FORCE_PER_TICK        = 120000
local SPEED_CAP             = game.SinglePlayer() and 1800 or 2300
local LIFETIME              = 45
local COLLISION_IMMUNE_TIME = 0.5
local SPAWN_FORWARD_OFFSET  = 600
local KICK_UP_SPEED         = 900

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    self.PhysObj = self:GetPhysicsObject()
    if IsValid( self.PhysObj ) then
        self.PhysObj:Wake()
        self.PhysObj:SetMass( 500 )
        self.PhysObj:EnableDrag( true )
        self.PhysObj:EnableGravity( true )
    end

    self.SpeedValue       = 0
    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.InitialDistance  = nil     -- latched first PhysicsUpdate tick
    self.Tracking         = false   -- false = arc phase, true = chase phase
    self.SpawnTime        = CurTime()
    self.HealthVal        = 50
    self.Damage           = 0
    self.Radius           = 0

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[TrackMissile] WARNING: no Target set before Spawn -- using fallback" )
    end

    -- Identical deferred kick to topmissile
    local selfRef = self
    timer.Simple( 0, function()
        if not IsValid( selfRef ) then return end
        local phys = selfRef:GetPhysicsObject()
        if not IsValid( phys ) then return end
        phys:SetVelocity( Vector( 0, 0, 1 ) * KICK_UP_SPEED )
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
--  FireEngine  (+0.75 s)  -- identical to topmissile
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 512,  760  )
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

    print( "[TrackMissile] Engine lit | arc phase active" )
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
--  PhysicsUpdate
--
--  ARC PHASE  (self.Tracking == false)
--    Copied verbatim from topmissile.
--    Uses horizontal distance remaining to the original Target
--    to decide which height offset to steer toward.
--    Thresholds: >90% dist -> low arc, >40% -> high arc, <=40% -> dive.
--
--  CHASE PHASE  (self.Tracking == true)
--    Steers toward live TrackEnt (or Target fallback).
--    LerpAngle 0.15 -- same aggressive rate as topmissile final dive.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = math.min( self.SpeedValue + FORCE_PER_TICK, FORCE_PER_TICK * 10 )
    end

    local mp = self:GetPos()

    -- Always measure arc progress against the ORIGINAL fixed Target
    local _2dDist = ( Vector( mp.x, mp.y, 0 )
                   - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    -- Latch initial horizontal distance once, on the first active tick
    if not self.InitialDistance then
        self.InitialDistance = math.max( _2dDist, 1 )
        print( string.format( "[TrackMissile] InitialDistance latched = %.0f", self.InitialDistance ) )
    end

    -- ---- ARC PHASE (identical to topmissile) ----
    if not self.Tracking then
        local halfway   = self.InitialDistance * 0.9
        local twoThirds = self.InitialDistance * 0.4
        local steerPos

        if _2dDist > halfway then
            -- Early climb: aim just slightly above target
            steerPos = self.Target + Vector( 0, 0, 512 )
        elseif _2dDist > twoThirds then
            -- Mid arc: aim high above target (the visible peak)
            steerPos = self.Target + Vector( 0, 0,
                math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
        else
            -- Apex reached: transition to chase phase
            self.Tracking = true
            self:SetNWBool( "Ballistic", false )  -- keep NW compat
            print( "[TrackMissile] Apex reached -> CHASE phase" )
        end

        if not self.Tracking then
            local lerpVal = _2dDist < 1000 and 0.15 or 0.02
            self:SetAngles( LerpAngle( lerpVal, self:GetAngles(),
                ( steerPos - mp ):GetNormalized():Angle() ) )
            phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
            return
        end
    end

    -- ---- CHASE PHASE ----
    -- Live-track the enemy; fall back to fixed Target if dead.
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    else
        aimPos = self.Target
    end

    self:SetAngles( LerpAngle( 0.15, self:GetAngles(),
        ( aimPos - mp ):GetNormalized():Angle() ) )

    phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
end

-- ============================================================
--  Think  -  proximity detonation + lifetime
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if self.ActivatedAlmonds then
        -- During arc: proximity to fixed Target
        -- During chase: proximity to live enemy
        local checkPos
        if self.Tracking and IsValid( self.TrackEnt ) then
            checkPos = self.TrackEnt:GetPos()
        else
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
--  Damage
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

-- ============================================================
--  Explosion
-- ============================================================
function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true

    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()

    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 512
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
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
end
