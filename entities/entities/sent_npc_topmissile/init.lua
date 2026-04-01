AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile  (npc_vj_gekko)
--
--  Based on sent_neuro_javelin (Hoffa & Smithy285 / NeuroTec).
--
--  Lifecycle:
--    1.  missile = ents.Create( "sent_npc_topmissile" )
--    2.  missile.Owner  = npcEnt        -- BEFORE Spawn()
--    3.  missile.Target = targetPos     -- BEFORE Spawn()  (Vector)
--    4.  missile:SetPos( launchPos )    -- BEFORE Spawn()
--    5.  missile:Spawn()
--    6.  missile:Activate()
--
--  KEY DESIGN NOTE (matches original Javelin exactly):
--    The 108 450 u/s velocity kick is applied in Initialize(),
--    NOT in FireEngine().  This means the missile is already
--    moving when FireEngine() fires at +0.75 s.  Applying the
--    kick after a 0.75 s stationary wait causes the body to
--    drift onto geometry and then explode with massive spin
--    torque when the impulse hits a resting body -- that is
--    what caused the rolling / lost-missile bug.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local SPEED_CAP = game.SinglePlayer() and 1800 or 2300
local LIFETIME  = 45

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
        self.PhysObj:EnableDrag( true )   -- drag ON, matches Javelin exactly
        self.PhysObj:EnableGravity( true )
    end

    -- Tilt nose up slightly (matches Javelin's 22-degree tilt)
    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetRight(), 22 )
    self:SetAngles( a )

    self.SpeedValue       = 0
    self.Speed            = 0
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

    -- *** Fire the kick IMMEDIATELY, same as the original Javelin ***
    -- The missile is already travelling when FireEngine() runs at +0.75 s.
    -- A stationary wait causes drift-onto-geometry then catastrophic spin.
    if IsValid( self.PhysObj ) then
        self.PhysObj:SetVelocityInstantaneous( self:GetForward() * 108450 )
        self.PhysObj:SetVelocity( self:GetForward() * 108450 )
    end

    self.EngineSound = CreateSound( self, SND_ENGINE )
    sound.Play( SND_LAUNCH, self:GetPos(), 85, 100 )

    local selfRef = self
    timer.Simple( 0.75, function()
        if IsValid( selfRef ) and not selfRef.Destroyed then
            selfRef:FireEngine()
        end
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  FireEngine  (0.75 s after spawn)
--  At this point the missile is already in flight.
--  We just start the engine sound, set damage/radius, and
--  spawn the trail prop -- no velocity change needed.
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
--  PhysicsCollide  -  detonate on any hit after engine lights
--  (matches original Javelin: no speed/DeltaTime guard)
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed            then return end
    if not self.ActivatedAlmonds then return end
    self:MissileDoExplosion()
end

-- ============================================================
--  PhysicsUpdate  -  3-phase top-attack arc
--  Matches original Javelin steering logic exactly.
--  No TerminalDive -- the missile is fast enough to impact
--  before physics can destabilise it.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    -- Speed ramp (identical to Javelin: +250 while below cap)
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + 250
    end

    local mp         = self:GetPos()
    local _2dDist    = ( Vector( mp.x, mp.y, 0 )
                       - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    if not self.InitialDistance then
        self.InitialDistance = _2dDist
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local steerPos  = self.Target

    if not self.Tracking then
        if _2dDist > halfway then
            -- Phase 1: climb
            steerPos = self.Target + Vector( 0, 0, 512 )
        elseif _2dDist < halfway and _2dDist > twoThirds then
            -- Phase 2: apex
            steerPos = self.Target + Vector( 0, 0,
                math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
        elseif _2dDist < twoThirds then
            -- Phase 3: nose at target, lock tracking
            steerPos = self.Target
            self.Tracking = true
        end
    end
    -- Once Tracking, steerPos stays as self.Target (static Vector)

    local lerpVal = _2dDist < 1000 and 0.1 or 0.01
    self:SetAngles( LerpAngle( lerpVal, self:GetAngles(),
        ( steerPos - mp ):GetNormalized():Angle() ) )

    self:GetPhysicsObject():ApplyForceCenter( self:GetForward() * self.SpeedValue )
end

-- ============================================================
--  Think  -  lifetime timeout only
--  (Proximity kill is handled by PhysicsCollide impact)
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
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
