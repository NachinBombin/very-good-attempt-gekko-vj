-- ============================================================
--  npc_vj_gekko / mg_physical_bullets.lua
--  STANDALONE physical bullet system for the Gekko MG.
--
--  Drop-in replacement for FireBullets() in FireMGBurst.
--  Replaces CW2.0 physical bullet logic, fully self-contained.
--
--  FEATURES:
--    - Real projectile trajectory (position + direction per tick)
--    - Bullet gravity / drop (pitch advances toward 90 over time)
--    - Velocity decay
--    - Ricochet off surfaces (one bounce, randomised spread)
--    - Tracer every 3rd bullet (rendered client-side via net msg)
--    - Whiz sound near local player
--    - Cartridge ejection (handled by caller)
--    - NO penetration logic (intentionally omitted)
--
--  WIRING:
--    init.lua  : AddCSLuaFile("mg_physical_bullets.lua")
--                include("mg_physical_bullets.lua")
--    cl_init.lua OR a clientside file:
--                include("mg_physical_bullets.lua")
--
--  USAGE (replace ent:FireBullets block in FireMGBurst):
--    GekkoMGPhysBul_Fire(ent, src, dir, MG_DAMAGE)
-- ============================================================
AddCSLuaFile()

-- ============================================================
--  CONFIG
-- ============================================================
local MUZZLE_VELOCITY       = 12000   -- units/sec, ~900 m/s scaled to GMod
local FALL_SPEED            = 1.5     -- degrees/sec pitch drop toward ground
local VELOCITY_DECAY_TARGET = 0.9     -- bullet bleeds to 90% of initial speed
local VELOCITY_DECAY_RATE   = 10000  -- approach rate per second
local RICOCHET_VEL_SCALE    = 0.60   -- speed kept after ricochet
local RICOCHET_DMG_SCALE    = 0.50   -- damage kept after ricochet
local RICOCHET_FALL_MULT    = 2.0    -- fall speed multiplier after ricochet
local RICOCHET_SPREAD       = 0.06   -- random spread on reflected direction
local TRACER_EVERY          = 3      -- every Nth bullet is a tracer
local WHIZ_DISTANCE         = 192    -- units from local player eye
local WHIZ_COOLDOWN         = 0.2    -- seconds between whiz sounds
local NET_MSG_FIRE          = "GekkoMGPhysBulFire"   -- new net msg for bullet spawn
local NET_MSG_RICOCHET      = "GekkoMGPhysBulRico"   -- new net msg for ricochet
local TRACE_MASK            = MASK_SHOT
local MAX_LIFETIME          = 2.5    -- seconds before bullet auto-expires

-- Ricochet material blacklist (don't bounce off these)
local NO_RICOCHET_MATS = {
    [MAT_FLESH]      = true,
    [MAT_BLOODYFLESH]= true,
    [MAT_ALIENFLESH] = true,
    [MAT_DIRT]       = true,
    [MAT_SAND]       = true,
    [MAT_SLOSH]      = true,
}

-- Surfaces that allow ricochet (everything not in blacklist)
local function CanRicochetMat(matType)
    return not NO_RICOCHET_MATS[matType]
end

-- ============================================================
--  NET SETUP  (server registers strings, both sides receive)
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_MSG_FIRE)
    util.AddNetworkString(NET_MSG_RICOCHET)
end

-- ============================================================
--  HELPERS
-- ============================================================
local function WritePreciseVector(v)
    net.WriteFloat(v.x)
    net.WriteFloat(v.y)
    net.WriteFloat(v.z)
end

local function ReadPreciseVector()
    local x = net.ReadFloat()
    local y = net.ReadFloat()
    local z = net.ReadFloat()
    return Vector(x, y, z)
end

local function RandomizeVector(v, amt)
    v.x = v.x + (math.random() - 0.5) * 2 * amt
    v.y = v.y + (math.random() - 0.5) * 2 * amt
    v.z = v.z + (math.random() - 0.5) * 2 * amt
    v:Normalize()
end

-- ============================================================
--  BULLET BUFFER   [SERVER]
--  Keyed by NPC entity, value = array of bullet structs
-- ============================================================
if SERVER then

local BulletBuffer = {}   -- BulletBuffer[npc] = { bullet, bullet, ... }

-- Per-NPC tracer counter (every TRACER_EVERY rounds = tracer)
local TracerCounter = {}

-- ---- Create bullet struct ----------------------------------
local function MakeBullet(npc, src, dir, damage, isRicochet)
    local b = {
        npc             = npc,
        position        = Vector(src.x, src.y, src.z),
        direction       = Vector(dir.x, dir.y, dir.z),
        directionAngle  = dir:Angle(),
        velocity        = MUZZLE_VELOCITY,
        initialVelocity = MUZZLE_VELOCITY,
        damage          = damage,
        isTracer        = false,
        noRicochet      = isRicochet or false,
        fallSpeed       = FALL_SPEED,
        spawnTime       = CurTime(),
        initialPos      = Vector(src.x, src.y, src.z),
    }
    return b
end

-- ---- Ricochet reflect helper --------------------------------
local function ReflectBullet(bullet, trace)
    -- Reflect direction off hit normal
    local dot = bullet.direction:Dot(trace.HitNormal)
    local reflected = bullet.direction + trace.HitNormal * (-2 * dot)
    reflected:Normalize()
    RandomizeVector(reflected, RICOCHET_SPREAD)

    local child = MakeBullet(
        bullet.npc,
        trace.HitPos + trace.HitNormal * 2,  -- step off surface slightly
        reflected,
        bullet.damage * RICOCHET_DMG_SCALE,
        true  -- no further ricochet
    )
    child.velocity        = bullet.velocity * RICOCHET_VEL_SCALE
    child.initialVelocity = child.velocity
    child.fallSpeed       = bullet.fallSpeed * RICOCHET_FALL_MULT
    return child
end

-- ---- Single bullet simulation tick --------------------------
-- Returns: "alive" | "hit" | "expired"
local function SimBullet(bullet, dt)
    -- Lifetime check
    if CurTime() - bullet.spawnTime > MAX_LIFETIME then return "expired" end

    -- Solid-contents check (already inside wall)
    if util.PointContents(bullet.position) == CONTENTS_SOLID then
        return "expired"
    end

    -- ---- Gravity (pitch drop) --------------------------------
    local ang = bullet.directionAngle
    ang.p = ang.p + bullet.fallSpeed * dt
    if ang.p > 90 then ang.p = 90 end
    bullet.directionAngle = ang
    bullet.direction      = ang:Forward()

    -- ---- Velocity decay ------------------------------------
    bullet.velocity = math.Approach(
        bullet.velocity,
        bullet.initialVelocity * VELOCITY_DECAY_TARGET,
        dt * VELOCITY_DECAY_RATE
    )

    -- ---- Trace this tick ------------------------------------
    local stepEnd = bullet.position + bullet.direction * (bullet.velocity * dt)
    local tr = util.TraceLine({
        start  = bullet.position,
        endpos = stepEnd,
        mask   = TRACE_MASK,
        filter = bullet.npc,
    })

    -- ---- Advance position -----------------------------------
    if tr.Hit then
        bullet.position = tr.HitPos
    else
        bullet.position = stepEnd
    end

    -- ---- Hit processing -------------------------------------
    if tr.Hit then
        if not tr.HitSky then
            -- Apply damage via FireBullets so VJ base registers it correctly
            if IsValid(bullet.npc) then
                bullet.npc:FireBullets({
                    Attacker   = bullet.npc,
                    Damage     = math.Round(bullet.damage),
                    Dir        = bullet.direction,
                    Src        = tr.HitPos - bullet.direction * 2,
                    AmmoType   = "AR2",
                    Num        = 1,
                    Spread     = vector_origin,
                    Force      = bullet.damage * 0.3,
                    Callback   = function(_, cbTr, _)
                        if cbTr.Hit and cbTr.HitNormal then
                            -- Broadcast impact flash to clients
                            net.Start("GekkoBulletImpact")
                                net.WriteVector(cbTr.HitPos)
                                net.WriteVector(cbTr.HitNormal)
                                net.WriteUInt(1, 3)
                            net.Broadcast()
                        end
                    end,
                })
            end
        end

        -- ---- Ricochet check ---------------------------------
        if not bullet.noRicochet and not tr.HitSky then
            local matType = tr.MatType or MAT_METAL
            -- Only ricochet at shallow-ish angles (dot < 0.6 means angle > ~53 deg)
            local dot = math.abs(bullet.direction:Dot(tr.HitNormal))
            if CanRicochetMat(matType) and dot < 0.6 then
                local child = ReflectBullet(bullet, tr)
                -- Add child to buffer
                local npc = bullet.npc
                if IsValid(npc) then
                    if not BulletBuffer[npc] then BulletBuffer[npc] = {} end
                    table.insert(BulletBuffer[npc], child)
                    -- Tell clients about the ricochet tracer
                    net.Start(NET_MSG_RICOCHET)
                        WritePreciseVector(child.position)
                        WritePreciseVector(child.direction)
                    net.Broadcast()
                end
            end
        end

        return "hit"
    end

    return "alive"
end

-- ---- Process all bullets for an NPC (called from Think) -----
local function ProcessNPCBullets(npc, dt)
    local buf = BulletBuffer[npc]
    if not buf or #buf == 0 then return end

    local i = 1
    while i <= #buf do
        local result = SimBullet(buf[i], dt)
        if result == "hit" or result == "expired" then
            table.remove(buf, i)
        else
            i = i + 1
        end
    end
end

-- ---- Hook into Think to tick all NPC bullets ----------------
hook.Add("Think", "GekkoMGPhysBul_ServerTick", function()
    local dt = FrameTime()
    for npc, _ in pairs(BulletBuffer) do
        if not IsValid(npc) then
            BulletBuffer[npc] = nil
        else
            ProcessNPCBullets(npc, dt)
        end
    end
end)

-- ============================================================
--  PUBLIC API   GekkoMGPhysBul_Fire(npc, src, dir, damage)
--  Call this from FireMGBurst instead of npc:FireBullets()
-- ============================================================
function GekkoMGPhysBul_Fire(npc, src, dir, damage)
    if not IsValid(npc) then return end

    -- Track tracer counter per NPC
    TracerCounter[npc] = (TracerCounter[npc] or 0) + 1
    local isTracer = (TracerCounter[npc] % TRACER_EVERY == 0)

    local bullet = MakeBullet(npc, src, dir, damage, false)
    bullet.isTracer = isTracer

    if not BulletBuffer[npc] then BulletBuffer[npc] = {} end
    table.insert(BulletBuffer[npc], bullet)

    -- Network the bullet to ALL clients (they render tracers + whiz)
    net.Start(NET_MSG_FIRE)
        WritePreciseVector(src)
        WritePreciseVector(dir)
        net.WriteBool(isTracer)
    net.Broadcast()
end

end -- SERVER

-- ============================================================
--  CLIENT-SIDE: tracer rendering + whiz sounds
-- ============================================================
if CLIENT then

local TracerMat = Material("sprites/glow03", "addons")
local TRACER_COLOR    = Color(255, 167, 112, 255)
local TRACER_SPRITE_DIST  = 128   -- sprite drawn N units ahead of position
local TRACER_BEAM_LENGTH  = 256   -- beam drawn behind bullet
local TRACER_SPRITE_SIZE  = 3
local TRACER_BEAM_WIDTH   = 1.2

local ClientBullets = {}   -- array of { pos, dir, vel, ang, isTracer, spawnTime, fallSpeed }
local _lastWhizTime = 0

local WHIZ_SOUNDS = {
    "physics/metal/metal_box_impact_bullet1.wav",
    "physics/metal/metal_box_impact_bullet2.wav",
    "physics/metal/metal_box_impact_bullet3.wav",
}

local function ReadPV()
    return Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
end

-- ---- Receive bullet fire from server ------------------------
net.Receive(NET_MSG_FIRE, function()
    local src      = ReadPV()
    local dir      = ReadPV()
    local isTracer = net.ReadBool()
    table.insert(ClientBullets, {
        pos       = src,
        dir       = dir,
        ang       = dir:Angle(),
        vel       = MUZZLE_VELOCITY,
        initVel   = MUZZLE_VELOCITY,
        isTracer  = isTracer,
        fallSpeed = FALL_SPEED,
        spawnTime = CurTime(),
    })
end)

-- ---- Receive ricochet child bullet --------------------------
net.Receive(NET_MSG_RICOCHET, function()
    local src = ReadPV()
    local dir = ReadPV()
    table.insert(ClientBullets, {
        pos       = src,
        dir       = dir,
        ang       = dir:Angle(),
        vel       = MUZZLE_VELOCITY * RICOCHET_VEL_SCALE,
        initVel   = MUZZLE_VELOCITY * RICOCHET_VEL_SCALE,
        isTracer  = true,   -- ricochets are always visible
        fallSpeed = FALL_SPEED * RICOCHET_FALL_MULT,
        spawnTime = CurTime(),
    })
end)

-- ---- Simulate client bullets each frame --------------------
hook.Add("Think", "GekkoMGPhysBul_ClientTick", function()
    local dt  = FrameTime()
    local now = CurTime()
    local eye = LocalPlayer():EyePos()

    local i = 1
    while i <= #ClientBullets do
        local b = ClientBullets[i]

        -- Expire
        if now - b.spawnTime > MAX_LIFETIME then
            table.remove(ClientBullets, i)
        else
            -- Gravity
            b.ang.p = b.ang.p + b.fallSpeed * dt
            if b.ang.p > 90 then b.ang.p = 90 end
            b.dir = b.ang:Forward()

            -- Velocity decay
            b.vel = math.Approach(b.vel, b.initVel * VELOCITY_DECAY_TARGET, dt * VELOCITY_DECAY_RATE)

            -- Advance
            local newPos = b.pos + b.dir * (b.vel * dt)

            -- Trace for client-side removal
            local tr = util.TraceLine({
                start  = b.pos,
                endpos = newPos,
                mask   = TRACE_MASK,
            })

            if tr.Hit then
                table.remove(ClientBullets, i)
            else
                b.pos = newPos

                -- Whiz check
                if now - _lastWhizTime > WHIZ_COOLDOWN then
                    local toEye = eye - b.pos
                    local dist  = toEye:Length()
                    if dist < WHIZ_DISTANCE then
                        -- Check bullet is heading roughly toward player
                        local toEyeN = toEye / dist
                        if b.dir:Dot(toEyeN) > 0.3 then
                            sound.Play(WHIZ_SOUNDS[math.random(#WHIZ_SOUNDS)], eye, 75, math.random(95, 110), 0.6)
                            _lastWhizTime = now
                        end
                    end
                end

                i = i + 1
            end
        end
    end
end)

-- ---- Render tracer bullets ----------------------------------
hook.Add("PostDrawOpaqueRenderables", "GekkoMGPhysBul_Render", function()
    if #ClientBullets == 0 then return end

    render.SetMaterial(TracerMat)

    for _, b in ipairs(ClientBullets) do
        if b.isTracer then
            local spritePos = b.pos + b.dir * TRACER_SPRITE_DIST
            local beamStart = b.pos
            local beamEnd   = b.pos + b.dir * TRACER_BEAM_LENGTH

            -- Sprite at bullet tip
            render.DrawSprite(spritePos, TRACER_SPRITE_SIZE, TRACER_SPRITE_SIZE, TRACER_COLOR)

            -- Beam trail
            render.DrawBeam(beamStart, beamEnd, TRACER_BEAM_WIDTH, 0, 1, TRACER_COLOR)
        end
    end
end)

end -- CLIENT
