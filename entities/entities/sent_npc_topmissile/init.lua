AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile  (npc_vj_gekko)
--
--  Lifecycle (caller in npc_vj_gekko/init.lua must follow this):
--    1.  missile = ents.Create( "sent_npc_topmissile" )
--    2.  missile.Owner  = npcEnt        -- BEFORE Spawn()
--    3.  missile.Target = targetPos     -- BEFORE Spawn()  (Vector)
--    4.  missile:SetPos( launchPos )    -- BEFORE Spawn()
--    5.  missile:Spawn()
--    6.  missile:Activate()
--
--  Do NOT assign TargetEntity.  This is a static-arc-only projectile.
--  Do NOT call GetPhysicsObject():SetVelocity() from the caller.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- Speed ramp: added to physics force every PhysicsUpdate tick.
-- 8 000 makes it feel snappy but still steer-able during the arc.
local FORCE_PER_TICK = 8000
local SPEED_CAP      = game.SinglePlayer() and 1800 or 2300
local LIFETIME       = 45

-- When horizontal distance to target drops below this, we enter
-- TERMINAL mode: steering stops completely, the missile just falls
-- straight down driven only by gravity + whatever forward momentum
-- it already has.  Proximity detonation then handles the kill.
local TERMINAL_DIST  = 350   -- world units
local TERMINAL_PROX  = 220   -- explode when closer than this to target

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
        self.PhysObj:EnableDrag( false )   -- no drag; we control speed ourselves
        self.PhysObj:EnableGravity( true )
        self.PhysObj:SetVelocity( Vector( 0, 0, 0 ) )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )
    end

    -- Nose straight up for clean vertical kick
    self:SetAngles( Angle( -90, self:GetAngles().y, 0 ) )

    self.SpeedValue       = 0
    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.InitialDistance  = nil
    self.TerminalDive     = false   -- true = steering OFF, gravity takes over
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
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 512,  760  )
    self.EngineSound:PlayEx( 511, 100 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:SetVelocityInstantaneous( self:GetForward() * 108450 )
        phys:SetVelocity( self:GetForward() * 108450 )
    end

    -- Invisible trail prop
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
--  Only trigger after engine has lit.  In TerminalDive we let
--  the proximity check in Think() handle detonation; a ground
--  collision is still a valid kill.
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed            then return end
    if not self.ActivatedAlmonds then return end
    if data.Speed > 200 and data.DeltaTime > 0.1 then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  -  3-phase arc steering
--
--  Phase 1  (> 90% of horizontal dist remains):  nose up, climb
--  Phase 2  (40-90% remains):                    track apex above target
--  Phase 3  (< 40% remains):                     point straight at target
--  TERMINAL (< TERMINAL_DIST horizontal):        steering OFF entirely
--
--  In TERMINAL mode we zero the angle velocity so physics can't
--  spin the model, then let gravity pull it down.  We do NOT
--  apply a forward force so there is no steering torque at all.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys )        then return end

    -- Measure horizontal distance to target
    local mp         = self:GetPos()
    local _2dDist    = ( Vector( mp.x, mp.y, 0 )
                       - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    -- --- TERMINAL DIVE: stop steering, freeze rotation, fall ---
    if self.TerminalDive then
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        -- no force applied; gravity does the work
        return
    end

    -- Cache initial horizontal distance once
    if not self.InitialDistance then
        self.InitialDistance = math.max( _2dDist, 1 )
    end

    -- Enter terminal dive when close enough
    if _2dDist < TERMINAL_DIST then
        self.TerminalDive = true
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        print( "[TopMissile] Terminal dive engaged at dist=" .. math.floor( _2dDist ) )
        return
    end

    -- Speed ramp (only during arc phases)
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + FORCE_PER_TICK
    end

    -- Compute steering target based on phase
    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local steerPos

    if _2dDist > halfway then
        -- Phase 1: climb steeply
        steerPos = self.Target + Vector( 0, 0, 512 )
    elseif _2dDist > twoThirds then
        -- Phase 2: aim at apex
        steerPos = self.Target + Vector( 0, 0,
            math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
    else
        -- Phase 3: nose toward target, transition to terminal
        steerPos = self.Target
    end

    local lerpVal = _2dDist < 1000 and 0.1 or 0.01
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

    -- Proximity check active once engine is lit
    if self.ActivatedAlmonds then
        local dist3d = ( self:GetPos() - self.Target ):Length()
        if dist3d < TERMINAL_PROX then
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

    if util.IsValidEffect( "vj_explosion3" ) then
        ParticleEffect( "vj_explosion3", pos, Angle( 0, 0, 0 ) )
    end

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
