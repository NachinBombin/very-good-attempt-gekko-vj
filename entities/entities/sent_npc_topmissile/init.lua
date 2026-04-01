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
--  Do NOT assign TargetEntity.  Static-arc-only projectile.
--  Do NOT call GetPhysicsObject():SetVelocity() from the caller.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local FORCE_PER_TICK = 8000
local SPEED_CAP      = game.SinglePlayer() and 1800 or 2300
local LIFETIME       = 45

-- Below this horizontal distance the missile stops steering entirely
-- and just falls with rotation frozen.  Proximity detonation kills it.
local TERMINAL_DIST  = 350
local TERMINAL_PROX  = 220

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
        self.PhysObj:EnableDrag( false )
        self.PhysObj:EnableGravity( true )
        self.PhysObj:SetVelocity( Vector( 0, 0, 0 ) )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )
    end

    self:SetAngles( Angle( -90, self:GetAngles().y, 0 ) )

    self.SpeedValue       = 0
    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.InitialDistance  = nil
    self.TerminalDive     = false
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
--  Ground/wall hit after engine lit = detonate.
--  (Proximity detonation in Think() handles the normal kill.)
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed            then return end
    if not self.ActivatedAlmonds then return end
    if data.Speed > 200 and data.DeltaTime > 0.1 then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  -  3-phase arc + terminal freeze
--
--  Phase 1  (> 90% horiz dist):  climb steeply
--  Phase 2  (40-90% horiz dist): arc over apex
--  Phase 3  (< 40% horiz dist):  nose at target
--  TERMINAL (< TERMINAL_DIST):   ALL steering + force OFF,
--                                 rotation frozen, gravity only
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    local mp      = self:GetPos()
    local _2dDist = ( Vector( mp.x, mp.y, 0 )
                    - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    -- TERMINAL: rotation is fully frozen each tick so physics
    -- cannot accumulate any spin at all.
    if self.TerminalDive then
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        -- no force: gravity carries it straight down
        return
    end

    if not self.InitialDistance then
        self.InitialDistance = math.max( _2dDist, 1 )
    end

    if _2dDist < TERMINAL_DIST then
        self.TerminalDive = true
        -- Kill all rotational momentum the moment we switch
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        -- Also freeze rotation on the physics object so the
        -- engine won't accumulate any new spin from collisions
        -- or gravity torque while we wait for proximity kill.
        phys:EnableMotion( false )
        phys:EnableMotion( true )   -- re-enable translation only trick:
        -- re-enabling immediately restores linear motion but the
        -- zero angle-velocity we just set is preserved for this tick.
        -- We keep calling SetAngleVelocity(0) every tick above.
        print( "[TopMissile] Terminal dive at dist=" .. math.floor( _2dDist ) )
        return
    end

    -- Speed ramp during arc phases only
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + FORCE_PER_TICK
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local steerPos

    if _2dDist > halfway then
        steerPos = self.Target + Vector( 0, 0, 512 )
    elseif _2dDist > twoThirds then
        steerPos = self.Target + Vector( 0, 0,
            math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
    else
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

    -- ParticleEffect is safe serverside; IsValidEffect is clientside-only
    -- so we just fire it unconditionally (harmless if particle doesn't exist).
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
