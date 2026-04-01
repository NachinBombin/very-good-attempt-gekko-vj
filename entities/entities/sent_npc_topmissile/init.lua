AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile  (npc_vj_gekko)
--
--  Based on sent_neuro_javelin by Hoffa & Smithy285.
--  Lifecycle (the caller in npc_vj_gekko/init.lua must follow this):
--
--    1.  missile = ents.Create( "sent_npc_topmissile" )
--    2.  missile.Owner        = npcEnt        -- BEFORE Spawn()
--    3.  missile.Target       = targetPos     -- BEFORE Spawn()  (Vector)
--    4.  missile.TargetEntity = targetEnt     -- BEFORE Spawn()  (Entity, optional)
--    5.  missile:SetPos( launchPos )          -- BEFORE Spawn()
--    6.  missile:SetAngles( launchAng )       -- BEFORE Spawn()  (any angle; Initialize overrides)
--    7.  missile:Spawn()
--    8.  missile:Activate()
--
--  Do NOT call GetPhysicsObject():SetVelocity() from the caller.
--  FireEngine() applies the 108 450 u/s upward kick after 0.75 s.
--
--  Speed values match sent_neuro_javelin exactly:
--    initial kick  108 450 u/s
--    ramp          +250 per PhysicsUpdate tick
--    cap           2 300 u/s (1 800 in singleplayer)
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local SPEED_CAP = game.SinglePlayer() and 1800 or 2300
local LIFETIME  = 45   -- auto-detonate after this many seconds

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
        self.PhysObj:SetVelocity( Vector( 0, 0, 0 ) )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )
    end

    -- Nose straight up so the kick goes cleanly upward
    self:SetAngles( Angle( -90, self:GetAngles().y, 0 ) )

    -- State
    self.SpeedValue            = 0
    self.Speed                 = 0
    self.Destroyed             = false
    self.ActivatedAlmonds      = false   -- engine ignited flag (guard for PhysicsCollide)
    self.InitialDistance       = nil
    self.Tracking              = false
    self.UseMovingTargetAiming = false
    self.SpawnTime             = CurTime()
    self.HealthVal             = 50
    self.Damage                = 0       -- set in FireEngine()
    self.Radius                = 0       -- set in FireEngine()

    -- Validate Target
    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[TopMissile] WARNING: no Target set before Spawn — using fallback" )
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

    -- Invisible prop to carry the scud_trail particle
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
--  Guard: only explode after ActivatedAlmonds == true.
--  Without this, the missile detonates on the ground during the
--  0.75 s pre-ignition drift.
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if self.ActivatedAlmonds
       and data.Speed     > 450
       and data.DeltaTime > 0.2 then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  -  Javelin steering (Hoffa & Smithy285)
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    -- Speed ramp
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + 250
    end

    -- Moving-target lead
    if IsValid( self.TargetEntity ) and not self.UseMovingTargetAiming then
        local zdiff  = self:GetPos().z - self.TargetEntity:GetPos().z
        local tspeed = self.TargetEntity:GetVelocity():Length()
        if zdiff < -200 and tspeed > 200 then
            self.UseMovingTargetAiming = true
        end
    end

    -- Steering
    if self.UseMovingTargetAiming and IsValid( self.TargetEntity ) then
        local dist = ( self.TargetEntity:GetPos() - self:GetPos() ):Length()
        local pos  = self.TargetEntity:GetPos() + Vector( 0, 0, math.Clamp( dist / 5, 0, 2500 ) )
        self:SetAngles( LerpAngle( 0.125, self:GetAngles(),
            ( pos - self:GetPos() ):GetNormalized():Angle() ) )
    else
        -- Static 3-phase top-attack arc
        local mp          = self:GetPos()
        local _2dDistance = ( Vector( mp.x, mp.y, 0 )
                            - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

        if not self.InitialDistance then
            self.InitialDistance = _2dDistance
        end

        local halfway   = self.InitialDistance * 0.9
        local twoThirds = self.InitialDistance * 0.4
        local pos       = self.Target

        if not self.Tracking then
            if _2dDistance > halfway then
                -- Phase 1: climb
                pos = self.Target + Vector( 0, 0, 512 )
            elseif _2dDistance < halfway and _2dDistance > twoThirds then
                -- Phase 2: apex
                pos = self.Target + Vector( 0, 0,
                    math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
            elseif _2dDistance < twoThirds then
                -- Phase 3: terminal dive
                pos = self.Target
                if IsValid( self.TargetEntity ) then
                    pos = self.TargetEntity:GetPos()
                    self.Tracking = true
                end
            end
        else
            if IsValid( self.TargetEntity ) then
                pos = self.TargetEntity:GetPos()
            end
        end

        local lerpVal = _2dDistance < 1000 and 0.1 or 0.01
        self:SetAngles( LerpAngle( lerpVal, self:GetAngles(),
            ( pos - self:GetPos() ):GetNormalized():Angle() ) )
    end

    self:GetPhysicsObject():ApplyForceCenter( self:GetForward() * self.SpeedValue )
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

    if self.UseMovingTargetAiming and IsValid( self.TargetEntity ) then
        if ( self:GetPos() - self.TargetEntity:GetPos() ):Length() < self.Radius * 0.65 then
            self:MissileDoExplosion()
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
