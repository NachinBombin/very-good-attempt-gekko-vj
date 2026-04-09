AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  sent_gekko_nikita / init.lua
--
--  NPC-only Nikita missile for npc_vj_gekko.
--
--  DESIGN RULES:
--    - Target is a FIXED VECTOR set by the Gekko before Spawn().
--      The missile never queries for a closest enemy, never scans
--      for players, never re-acquires anything on its own.
--    - Flight profile: low-altitude guided cruise (Nikita-style).
--      No top-attack arc.  The missile climbs 320 u above the
--      target Z then pushes forward and dives onto it.
--    - If no Target vector is set before Spawn() a 2000 u
--      fallback is used and a warning is printed.
--    - Collision-immune for 0.5 s after spawn so it clears
--      the Gekko hull without self-detonating.
--    - Detonates on PhysicsCollide, proximity (< 160 u),
--      or lifetime timeout (30 s).
--    - Can be shot down (health = 35).
-- ============================================================

local SND_LAUNCH  = "buttons/button17.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local FORCE_PER_TICK        = 110000
local SPEED_CAP             = game.SinglePlayer() and 1600 or 2000
local LIFETIME              = 30
local COLLISION_IMMUNE_TIME = 0.5

-- Height the missile climbs above the target Z before diving.
-- Keeps it from hugging the ground and clipping terrain.
local CRUISE_HEIGHT_ABOVE   = 320

-- Lateral lerp aggressiveness: higher = tighter turns.
-- 0.04 keeps it feeling like a real cruise missile (lazy arcs).
local STEER_LERP_CLOSE      = 0.12   -- inside 600 u of target
local STEER_LERP_FAR        = 0.04   -- outside 600 u of target

-- Proximity threshold for detonation.
local DETONATE_DIST         = 160

local HEALTH                = 35
local DMG_MIN               = 2200
local DMG_MAX               = 3800
local BLAST_RADIUS_MIN      = 480
local BLAST_RADIUS_MAX      = 680

-- Initial upward speed applied 1 tick after spawn.
-- The engine ignites at +0.75 s and takes over.
local KICK_UP_SPEED         = 700

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
        self.PhysObj:EnableGravity( false )  -- engine counteracts gravity
    end

    self.SpeedValue       = 0
    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.SpawnTime        = CurTime()
    self.HealthVal        = HEALTH
    self.Damage           = 0
    self.Radius           = 0
    self.InitialDist      = nil

    -- Validate Target: must be a Vector set by the Gekko.
    -- NEVER scan for enemies here.  If missing, use a straight
    -- forward fallback so at least nothing explodes on the Gekko.
    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0 ; fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[GekkoNikita] WARNING: Target not set before Spawn() -- using fallback" )
    end

    -- Upward kick one tick after spawn so physobj has settled.
    local selfRef = self
    timer.Simple( 0, function()
        if not IsValid( selfRef ) then return end
        local phys = selfRef:GetPhysicsObject()
        if IsValid( phys ) then
            phys:SetVelocity( Vector( 0, 0, 1 ) * KICK_UP_SPEED )
        end
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
function ENT:FireEngine()
    if self.Destroyed then return end
    self.Damage = math.random( DMG_MIN, DMG_MAX )
    self.Radius = math.random( BLAST_RADIUS_MIN, BLAST_RADIUS_MAX )
    self.EngineSound:PlayEx( 511, 100 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )

    -- Attach scud trail prop (invisible, trail particle only).
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
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < COLLISION_IMMUNE_TIME then return end
    if not self.ActivatedAlmonds then return end
    self:NikitaExplode()
end

-- ============================================================
--  PhysicsUpdate  -  cruise flight toward fixed Target vector
--
--  Phase 1 (far):  fly at CRUISE_HEIGHT_ABOVE the target Z,
--                  steer XY toward the target.
--  Phase 2 (close): dive straight onto the target.
--
--  The missile NEVER looks for any entity.  All steering is
--  pure Vector math against self.Target.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    -- Throttle up toward speed cap.
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = math.min(
            self.SpeedValue + FORCE_PER_TICK,
            FORCE_PER_TICK * 10
        )
    end

    local mp = self:GetPos()
    local dist3d = ( mp - self.Target ):Length()
    local dist2d = ( Vector( mp.x, mp.y, 0 )
                  - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    if not self.InitialDist then
        self.InitialDist = math.max( dist2d, 1 )
    end

    -- Choose steer target based on distance to impact.
    local steerTarget
    if dist2d > 600 then
        -- Cruise phase: fly at elevated Z, home XY.
        steerTarget = Vector(
            self.Target.x,
            self.Target.y,
            self.Target.z + CRUISE_HEIGHT_ABOVE
        )
    else
        -- Terminal phase: dive straight onto target.
        steerTarget = self.Target
    end

    local lerpVal = ( dist2d < 600 ) and STEER_LERP_CLOSE or STEER_LERP_FAR
    self:SetAngles(
        LerpAngle(
            lerpVal,
            self:GetAngles(),
            ( steerTarget - mp ):GetNormalized():Angle()
        )
    )
    phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
end

-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    -- Lifetime timeout.
    if CurTime() - self.SpawnTime > LIFETIME then
        self:NikitaExplode()
        return true
    end

    -- Proximity detonation.
    if self.ActivatedAlmonds and self.Target then
        if ( self:GetPos() - self.Target ):Length() < DETONATE_DIST then
            self:NikitaExplode()
            return true
        end
    end

    return true
end

-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:NikitaExplode() end
end

-- ============================================================
function ENT:NikitaExplode()
    if self.Destroyed then return end
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()

    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 512
    local owner = IsValid( self.Owner ) and self.Owner or self

    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 14, 180, 1, 3000 )
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
        pe:Spawn() ; pe:Activate()
        pe:Fire( "Explode", "", 0 )
        pe:Fire( "Kill",    "", 0.5 )
    end

    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )
    self:Remove()
end

-- ============================================================
function ENT:OnRemove()
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
end
