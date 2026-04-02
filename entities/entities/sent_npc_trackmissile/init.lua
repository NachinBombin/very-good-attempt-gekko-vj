AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Tracking Missile  (sent_npc_trackmissile)
--  6th weapon for npc_vj_gekko.
--
--  FLIGHT PHASES:
--
--    [0] PRE-IGNITION  (0 -> 0.75 s)
--        Missile coasts on its initial kick (straight up).
--        No guidance, no engine.  Sparks + steam visuals only.
--
--    [1] ACTIVE TRACKING  (0.75 s -> engine lit, while Z < TRACK_CEILING)
--        Engine ignites.  Missile steers hard toward the live
--        enemy position every PhysicsUpdate tick.
--        Lerp rate is aggressive (0.12) so it can curve.
--        This continues until the missile's Z rises above
--        TRACK_CEILING units above the SPAWN point Z.
--
--    [2] BALLISTIC  (Z >= TRACK_CEILING  OR  engine not yet lit)
--        Guidance is cut entirely.  No SetAngles, no ApplyForce
--        steering.  Only engine thrust along the current forward
--        vector keeps speed up; gravity + drag arc it naturally.
--        This prevents any looping/circling near the ground.
--
--    [3] DETONATE
--        Proximity trigger (<180 u to target), PhysicsCollide,
--        or lifetime timeout.
--
--  SAFETY:
--    - COLLISION_IMMUNE_TIME = 0.5 s: ignores PhysicsCollide
--      during the launch kick window.
--    - MinDist check in FireTrackMissile(): re-rolls if too close.
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local FORCE_PER_TICK       = 120000
local SPEED_CAP            = game.SinglePlayer() and 1800 or 2300
local LIFETIME             = 45
local COLLISION_IMMUNE_TIME = 0.5

-- Height above spawn Z at which active tracking is cut off
-- and the missile becomes purely ballistic.
-- 600 units ~ one storey above the NPC launch point.
local TRACK_CEILING = 600

-- How aggressively the missile steers toward the target
-- while in active-tracking phase.  0.12 = snappy but not instant.
local TRACK_LERP = 0.12

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

    self.SpeedValue        = 0
    self.Destroyed         = false
    self.ActivatedAlmonds  = false   -- true once FireEngine() runs
    self.Ballistic         = false   -- true once ceiling is breached
    self.SpawnTime         = CurTime()
    self.SpawnZ            = nil     -- set after first PhysicsUpdate tick
    self.HealthVal         = 50
    self.Damage            = 0
    self.Radius            = 0
    -- Target is a Vector set by the NPC before Spawn()
    -- TrackEnt is the live entity to follow during active tracking
    -- (set by the NPC; falls back to Target vector if invalid)

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[TrackMissile] WARNING: no Target set before Spawn -- using fallback" )
    end

    -- Initial kick straight up (same as topmissile)
    if IsValid( self.PhysObj ) then
        self.PhysObj:SetVelocityInstantaneous( self:GetForward() * 108450 )
        self.PhysObj:SetVelocity( self:GetForward() * 108450 )
    end

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

    -- Latch spawn Z now that we're flying (physobj has settled)
    self.SpawnZ = self:GetPos().z

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

    print( string.format( "[TrackMissile] Engine lit | SpawnZ=%.0f  ceiling at Z=%.0f",
        self.SpawnZ, self.SpawnZ + TRACK_CEILING ) )
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
--  PhysicsUpdate  -  guidance + thrust
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    -- Ramp thrust while below speed cap
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = math.min( self.SpeedValue + FORCE_PER_TICK, FORCE_PER_TICK * 10 )
    end

    local mp = self:GetPos()

    -- Check ceiling to decide if we should switch to ballistic
    if not self.Ballistic and self.SpawnZ then
        if mp.z >= self.SpawnZ + TRACK_CEILING then
            self.Ballistic = true
            self:SetNWBool( "Ballistic", true )
            print( string.format(
                "[TrackMissile] Ceiling reached Z=%.0f -> BALLISTIC", mp.z
            ))
        end
    end

    if self.Ballistic then
        -- Pure ballistic: thrust only along current forward, no steering
        phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
        return
    end

    -- ---- ACTIVE TRACKING ----
    -- Resolve live target position
    local aimPos
    if IsValid( self.TrackEnt ) then
        aimPos = self.TrackEnt:GetPos() + Vector( 0, 0, 40 )
    elseif self.Target then
        aimPos = self.Target
    else
        phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
        return
    end

    -- Steer toward live target
    local wantAngle = ( aimPos - mp ):GetNormalized():Angle()
    self:SetAngles( LerpAngle( TRACK_LERP, self:GetAngles(), wantAngle ) )

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
        -- Proximity: use live entity pos if available, else stored vector
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
