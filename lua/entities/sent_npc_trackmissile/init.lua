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

-- =========================================================================
-- Gib configuration (always spawns 3 ignited concrete debris on explosion)
-- =========================================================================
local GIB_LIFETIME = 3.5
local GIB_MODELS = {
    "models/props_junk/CinderBlock01a.mdl",
    "models/props_mining/rock_caves01a.mdl",
    "models/props_mining/rock_caves01b.mdl",
    "models/props_mining/rock_caves01c.mdl",
    "models/props_debris/concrete_spawnchunk001b.mdl",
    "models/props_debris/concrete_spawnchunk001d.mdl",
    "models/props_debris/concrete_spawnchunk001g.mdl",
    "models/props_debris/concrete_spawnchunk001i.mdl",
    "models/props_debris/concrete_spawnchunk001k.mdl",
    "models/props_debris/concrete_spawnchunk001j.mdl",
    "models/props_debris/prison_wallchunk001f.mdl",
    "models/props_debris/concrete_chunk09a.mdl",
    "models/props_debris/concrete_chunk03a.mdl",
    "models/props_debris/concrete_chunk04a.mdl",
    "models/props_debris/concrete_chunk05g.mdl",
    "models/props_debris/concrete_chunk02a.mdl",
    "models/props_debris/tile_wall001a_chunk02.mdl",
    "models/props_debris/tile_wall001a_chunk09.mdl",
    "models/props_debris/tile_wall001a_chunk06.mdl",
    "models/props_debris/tile_wall001a_chunk05.mdl",
    "models/props_debris/rebar001a_32.mdl",
    "models/props_debris/rebar003a_32.mdl",
}

local function SpawnIgnitedGib( missile, hitPos, hitNormal )
    local mdl = GIB_MODELS[ math.random( #GIB_MODELS ) ]
    local gib = ents.Create( "prop_physics" )
    if not IsValid( gib ) then return end
    gib:SetModel( mdl )
    gib:SetPos( hitPos + hitNormal * 4 )
    gib:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
    gib:Spawn()
    gib:Activate()
    gib:DrawShadow( false )

    -- ── APS WHITELIST (triple guard, same pattern as Nikita tip-cap) ──
    -- Guard 7: checked before every pillar in aps_system.lua
    gib._gekkoOwnedGib = true
    -- Guard 11: engine owner chain resolves back to Gekko
    gib:SetOwner( missile )
    -- Guard 12: raw .Owner field belt-and-suspenders fallback
    gib.Owner = missile
    -- -----------------------------------------------------------------

    timer.Simple( GIB_LIFETIME, function()
        if IsValid( gib ) then gib:Remove() end
    end )
    local phys = gib:GetPhysicsObject()
    if not IsValid( phys ) then gib:Remove() return end
    local helper
    if math.abs( hitNormal.z ) < 0.9 then
        helper = Vector( 0, 0, 1 )
    else
        helper = Vector( 1, 0, 0 )
    end
    local tangent   = hitNormal:Cross( helper )  tangent:Normalize()
    local bitangent = hitNormal:Cross( tangent ) bitangent:Normalize()
    local cos_theta = math.random()
    local sin_theta = math.sqrt( 1 - cos_theta * cos_theta )
    local phi       = math.random() * ( 2 * math.pi )
    local cp        = math.cos( phi )
    local sp        = math.sin( phi )
    local nx, ny, nz = hitNormal.x, hitNormal.y, hitNormal.z
    local dx = nx * cos_theta + tangent.x * ( sin_theta * cp ) + bitangent.x * ( sin_theta * sp )
    local dy = ny * cos_theta + tangent.y * ( sin_theta * cp ) + bitangent.y * ( sin_theta * sp )
    local dz = nz * cos_theta + tangent.z * ( sin_theta * cp ) + bitangent.z * ( sin_theta * sp )
    local dlen = math.sqrt( dx*dx + dy*dy + dz*dz )
    if dlen < 0.001 then gib:Remove() return end
    dx = dx / dlen  dy = dy / dlen  dz = dz / dlen
    local speed = math.Rand( 120, 340 )
    phys:SetVelocity( Vector( dx * speed, dy * speed, dz * speed ) )
    phys:SetAngleVelocity( Vector( math.Rand(-400,400), math.Rand(-400,400), math.Rand(-400,400) ) )
    gib:Ignite( 0, 0 )
end

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
            self:SetNWBool( "Ballistic", false )
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

local FALLOFF_MIN_FRAC = 0.08

local function EntAimPos( ent )
    local phys = ent:GetPhysicsObject()
    if IsValid( phys ) then return phys:GetMassCenter() end
    return ent:GetPos()
end

local function DoFalloffBlastDamage( inflictor, attacker, origin, radius, maxDmg )
    for _, ent in ipairs( ents.FindInSphere( origin, radius ) ) do
        if not IsValid( ent ) then continue end
        if ent == inflictor   then continue end

        local entPos = EntAimPos( ent )
        local los = util.TraceLine({
            start  = origin,
            endpos = entPos,
            mask   = MASK_SOLID_BRUSHONLY,
            filter = inflictor,
        })
        if los.Hit then continue end

        local dist  = ( entPos - origin ):Length()
        local frac  = 1 - ( dist / radius )
        frac        = math.Clamp( frac, 0, 1 )
        local scale = FALLOFF_MIN_FRAC + ( 1 - FALLOFF_MIN_FRAC ) * frac
        local dmg   = maxDmg * scale

        if dmg < 1 then continue end

        local dmginfo = DamageInfo()
        dmginfo:SetDamage( dmg )
        dmginfo:SetAttacker( attacker )
        dmginfo:SetInflictor( inflictor )
        dmginfo:SetDamageType( DMG_BLAST )
        dmginfo:SetDamagePosition( origin )
        local dir = ( entPos - origin ):GetNormalized()
        dmginfo:SetDamageForce( dir * dmg * 80 )
        ent:TakeDamageInfo( dmginfo )
    end
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
    for _, ply in ipairs( player.GetAll() ) do
        if not IsValid( ply ) then continue end
        local _shakeDist = ( ply:GetPos() - pos ):Length()
        if _shakeDist < 3000 then
            local _shakeFrac = math.Clamp( 1 - ( _shakeDist / 3000 ), 0, 1 )
            util.ScreenShake( ply:GetPos(), 20 * _shakeFrac, 200, 1.0, 1 )
        end
    end
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

    DoFalloffBlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )

    -- Always spawn 3 ignited concrete gibs
    -- Pass self so each gib is stamped with the triple APS guard.
    local upNormal = Vector( 0, 0, 1 )
    for i = 1, 3 do
        SpawnIgnitedGib( self, pos, upNormal )
    end

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
