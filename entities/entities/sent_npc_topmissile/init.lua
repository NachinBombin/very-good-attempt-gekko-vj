AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile  (npc_vj_gekko)
--
--  CHANGE LOG:
--    - SND_WARN changed to buttons/button17.wav (loud electronic
--      alarm beep) at max volume 511 from npc init caller
--    - Velocity kick fires in Initialize() so missile is moving
--      before FireEngine() fires at +0.75s
--    - 22-degree tilt REMOVED
--    - FORCE_PER_TICK = 120000 N sustains ~2000 u/s
--    - PhysicsCollide 0.5 s immunity window (self-collision fix)
--    - Drag ON
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"   -- loud electronic beep
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local FORCE_PER_TICK = 120000
local SPEED_CAP  = game.SinglePlayer() and 1800 or 2300
local LIFETIME   = 45
local COLLISION_IMMUNE_TIME = 0.5

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
    self.InitialDistance  = nil
    self.Tracking         = false
    self.SpawnTime        = CurTime()
    self.HealthVal        = 50
    self.Damage           = 0
    self.Radius           = 0

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[TopMissile] WARNING: no Target set before Spawn -- using fallback" )
    end

    if IsValid( self.PhysObj ) then
        self.PhysObj:SetVelocityInstantaneous( self:GetForward() * 108450 )
        self.PhysObj:SetVelocity( self:GetForward() * 108450 )
    end

    -- Max-volume electronic beep on launch
    sound.Play( SND_LAUNCH, self:GetPos(), 511, 60 )

    self.EngineSound = CreateSound( self, SND_ENGINE )

    local selfRef = self
    timer.Simple( 0.75, function()
        if IsValid( selfRef ) and not selfRef.Destroyed then
            selfRef:FireEngine()
        end
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  FireEngine  (+0.75 s)
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
--  PhysicsUpdate  -  3-phase top-attack arc
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = math.min( self.SpeedValue + FORCE_PER_TICK, FORCE_PER_TICK * 10 )
    end

    local mp      = self:GetPos()
    local _2dDist = ( Vector( mp.x, mp.y, 0 )
                   - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    if not self.InitialDistance then
        self.InitialDistance = math.max( _2dDist, 1 )
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local steerPos  = self.Target

    if not self.Tracking then
        if _2dDist > halfway then
            steerPos = self.Target + Vector( 0, 0, 512 )
        elseif _2dDist > twoThirds then
            steerPos = self.Target + Vector( 0, 0,
                math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
        else
            steerPos = self.Target
            self.Tracking = true
        end
    end

    local lerpVal = _2dDist < 1000 and 0.15 or 0.02
    self:SetAngles( LerpAngle( lerpVal, self:GetAngles(),
        ( steerPos - mp ):GetNormalized():Angle() ) )

    phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
end

-- ============================================================
--  Think  -  proximity detonation + lifetime timeout
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
        return true
    end

    if self.ActivatedAlmonds then
        local dist3d = ( self:GetPos() - self.Target ):Length()
        if dist3d < 180 then
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
