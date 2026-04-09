AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Missile  (sent_gekko_nikita)
--
--  Direct copy of sent_npc_trackmissile flight model with:
--    * No ballistic / ceiling phase  (tracks forever)
--    * Speed capped at 600 u/s       (slow, dodgeable)
--    * Scale 2x model
--    * Health 50 HP -- can be shot down
--    * Larger explosion radius
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local FORCE_PER_TICK        = 120000
local SPEED_CAP             = 600        -- slow cruise missile
local LIFETIME              = 45
local COLLISION_IMMUNE_TIME = 0.5
local TRACK_LERP            = 0.12       -- same as trackmissile
local KICK_UP_SPEED         = 900        -- same as trackmissile

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:SetModelScale( 2, 0 )           -- bigger than trackmissile
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 500 )
        phys:EnableDrag( true )
        phys:EnableGravity( true )
        -- CRITICAL: registers PhysicsUpdate callback with the physics engine
        self:StartMotionController()
    end

    self.SpeedValue       = 0
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

    -- Deferred upward kick identical to trackmissile
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
--  FireEngine  (+0.75 s)  -- identical to trackmissile
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 700,  1024 )  -- bigger than trackmissile
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
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < COLLISION_IMMUNE_TIME then return end
    if not self.ActivatedAlmonds then return end
    self:MissileDoExplosion()
end

-- ============================================================
--  PhysicsUpdate  -- guidance + thrust (no ballistic phase)
-- ============================================================
function ENT:PhysicsUpdate( phys, deltatime )
    if not self.ActivatedAlmonds then return end
    if not IsValid( phys ) then return end

    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = math.min( self.SpeedValue + FORCE_PER_TICK, FORCE_PER_TICK * 10 )
    end

    -- Resolve live aim position
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    elseif self.Target then
        aimPos = self.Target
    else
        phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
        return
    end

    local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
    self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )

    phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
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
