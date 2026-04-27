-- ============================================================
--  GEKKO BLOOD GEYSER CLIENT  (blood_geyser_cl.lua)
--
--  Receives the GekkoBloodGeyser net message sent by
--  blood_system.lua (server) and runs two layered effects:
--
--  SYSTEM 1 – GEYSER VARIANTS  (old system, world-origin driven)
--    Five BloodVariant_* functions already defined in cl_init.lua
--    are re-dispatched here with the exact world position + dir
--    passed over the net, so the spray always originates from
--    the actual bone hit location instead of a fixed ent:GetPos()
--    offset.  Flag = 1 (BURST) picks from all 5 variants at
--    random; flag = 0 (STREAM) skips the geyser and only runs
--    the droplet system.
--
--  SYSTEM 2 – DROPLET SIMULATION  (new system, bloodstream-style)
--    A pool of cheap client-side physics particles.  Each droplet
--    is a small coloured quad rendered in PostDrawOpaqueRenderables
--    with a simple Euler integrator (gravity + drag) and a short
--    lifetime.  No real entities are spawned so the server never
--    sees them.  Decals are stamped when a droplet hits a brush.
--
--  Both systems fire together on BURST; only DROPLETS fire on
--  STREAM (ragdoll bleeding).
-- ============================================================

if SERVER then return end

-- ============================================================
--  TUNING
-- ============================================================
local DROPLET_GRAVITY    =  800     -- upward deceleration (u/s²)
local DROPLET_DRAG       =  0.55    -- exponential speed decay per second
local DROPLET_LIFETIME   =  0.9     -- max seconds alive
local DROPLET_BOUNCE_COF =  0.28    -- coefficient of restitution on brush hit
local DROPLET_BOUNCE_MIN =  40      -- min speed (u/s) to keep bouncing
local DROPLET_SIZE_MIN   =  1.2
local DROPLET_SIZE_MAX   =  3.8
local DROPLET_POOL_MAX   =  512     -- hard cap on simultaneous droplets
local DROPLET_TRACE_DIST =  6       -- hull half-size for trace

local BURST_COUNT_MIN    =  55
local BURST_COUNT_MAX    =  95
local STREAM_COUNT_MIN   =  18
local STREAM_COUNT_MAX   =  32

local BURST_SPEED_MIN    =  320
local BURST_SPEED_MAX    = 1400
local STREAM_SPEED_MIN   =  200
local STREAM_SPEED_MAX   =  700

-- Decal probability per droplet on brush impact (0–1)
local DECAL_CHANCE       =  0.35
local DECAL_NAME         = "Blood"
local DECAL_NAME2        = "YellowBlood"

-- Colour range: deep red → bright red
local COL_R_MIN, COL_R_MAX = 140, 220
local COL_G_MIN, COL_G_MAX =   0,  20
local COL_B_MIN, COL_B_MAX =   0,  10

-- ============================================================
--  DROPLET POOL
-- ============================================================
--  Each droplet is a plain table:
--    pos  : Vector  (world)
--    vel  : Vector  (world, u/s)
--    size : float   (screen-space quad half-extent in px approximation)
--    life : float   (remaining seconds)
--    maxL : float   (total lifetime for alpha fade)
--    r,g,b: float   (colour channels 0–255)
--    dead : bool
local _droplets = {}
local _dropCnt  = 0

local function SpawnDroplets(origin, dir, count, speedMin, speedMax)
    -- dir is the dominant spray direction (normalised, world-space)
    -- droplets fan out in a cone around it
    local right, up
    do
        local world_up = Vector(0, 0, 1)
        if math.abs(dir:Dot(world_up)) > 0.95 then
            world_up = Vector(1, 0, 0)
        end
        right = dir:Cross(world_up):GetNormalized()
        up    = dir:Cross(right):GetNormalized()
    end

    for _ = 1, count do
        if _dropCnt >= DROPLET_POOL_MAX then break end

        -- random cone spread (bloodstream-style: tighter at centre)
        local theta = math.Rand(0, math.pi * 2)
        local r     = math.sqrt(math.random()) * 0.65   -- radius in unit circle
        local spread_r = right * (math.cos(theta) * r)
        local spread_u = up    * (math.sin(theta) * r)
        local d = (dir + spread_r + spread_u):GetNormalized()

        local speed = math.Rand(speedMin, speedMax)

        local drop = {
            pos  = origin + d * math.Rand(2, 8),
            vel  = d * speed,
            size = math.Rand(DROPLET_SIZE_MIN, DROPLET_SIZE_MAX),
            life = math.Rand(DROPLET_LIFETIME * 0.4, DROPLET_LIFETIME),
            r    = math.Rand(COL_R_MIN, COL_R_MAX),
            g    = math.Rand(COL_G_MIN, COL_G_MAX),
            b    = math.Rand(COL_B_MIN, COL_B_MAX),
            dead = false,
        }
        drop.maxL = drop.life

        _droplets[#_droplets + 1] = drop
        _dropCnt = _dropCnt + 1
    end
end

-- ============================================================
--  DROPLET PHYSICS TICK
--  Runs in Think hook; updates all live droplets each frame.
-- ============================================================
local _lastTick = 0

hook.Add("Think", "GekkoDropletTick", function()
    local now = RealTime()
    local dt  = math.Clamp(now - _lastTick, 0, 0.05)
    _lastTick = now

    if dt <= 0 or _dropCnt == 0 then return end

    local drag_factor = math.exp(-DROPLET_DRAG * dt)
    local grav_dv     = -DROPLET_GRAVITY * dt

    local alive = 0
    local n = #_droplets

    for i = 1, n do
        local d = _droplets[i]
        if d.dead then goto continue end

        d.life = d.life - dt
        if d.life <= 0 then
            d.dead = true
            goto continue
        end

        -- Euler step
        local vx, vy, vz = d.vel.x, d.vel.y, d.vel.z
        vx = vx * drag_factor
        vy = vy * drag_factor
        vz = vz * drag_factor + grav_dv

        local nx = d.pos.x + vx * dt
        local ny = d.pos.y + vy * dt
        local nz = d.pos.z + vz * dt

        -- Brush trace
        local tr = util.TraceLine({
            start  = d.pos,
            endpos = Vector(nx, ny, nz),
            mask   = MASK_SOLID_BRUSHONLY,
        })

        if tr.Hit then
            -- Stamp decal
            if math.random() < DECAL_CHANCE then
                local dn = (math.random(1, 6) == 1) and DECAL_NAME2 or DECAL_NAME
                util.Decal(dn, tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
            end

            local speed = math.sqrt(vx*vx + vy*vy + vz*vz)
            if speed < DROPLET_BOUNCE_MIN then
                d.dead = true
                goto continue
            end

            -- Reflect velocity off surface normal
            local nx2, ny2, nz2 = tr.HitNormal.x, tr.HitNormal.y, tr.HitNormal.z
            local dot = vx*nx2 + vy*ny2 + vz*nz2
            vx = (vx - 2 * dot * nx2) * DROPLET_BOUNCE_COF
            vy = (vy - 2 * dot * ny2) * DROPLET_BOUNCE_COF
            vz = (vz - 2 * dot * nz2) * DROPLET_BOUNCE_COF

            nx = tr.HitPos.x + tr.HitNormal.x * 1.5
            ny = tr.HitPos.y + tr.HitNormal.y * 1.5
            nz = tr.HitPos.z + tr.HitNormal.z * 1.5
        end

        d.pos.x, d.pos.y, d.pos.z = nx, ny, nz
        d.vel.x, d.vel.y, d.vel.z = vx, vy, vz

        alive = alive + 1
        ::continue::
    end

    -- Compact pool when heavily dead to avoid unbounded growth
    if alive < _dropCnt * 0.35 then
        local fresh = {}
        for i = 1, n do
            if not _droplets[i].dead then
                fresh[#fresh + 1] = _droplets[i]
            end
        end
        _droplets = fresh
        _dropCnt  = #fresh
    end
end)

-- ============================================================
--  DROPLET RENDER
--  Billboard quads in PostDrawOpaqueRenderables so they depth-
--  sort correctly against world geometry without needing
--  translucency passes.
-- ============================================================
local _mat_blood = CreateMaterial(
    "gekko_blood_drop",
    "UnlitGeneric",
    {
        ["$basetexture"]  = "particle/blood1",
        ["$vertexalpha"]  = "1",
        ["$vertexcolor"]  = "1",
        ["$additive"]     = "0",
        ["$nocull"]       = "1",
    }
)

hook.Add("PostDrawOpaqueRenderables", "GekkoDropletRender", function()
    if _dropCnt == 0 then return end

    render.SetMaterial(_mat_blood)

    local cam_pos   = EyePos()
    local cam_ang   = EyeAngles()
    local cam_right = cam_ang:Right()
    local cam_up    = cam_ang:Up()

    for i = 1, #_droplets do
        local d = _droplets[i]
        if d.dead then continue end

        local alpha = math.Clamp(d.life / d.maxL, 0, 1)
        -- distance fade: taper off beyond 1500 units
        local dist  = d.pos:Distance(cam_pos)
        local distF = 1 - math.Clamp((dist - 900) / 600, 0, 1)
        alpha = alpha * distF
        if alpha <= 0.02 then continue end

        local s = d.size
        -- Billboard corners around drop position
        local tl = d.pos - cam_right * s + cam_up * s
        local tr = d.pos + cam_right * s + cam_up * s
        local br = d.pos + cam_right * s - cam_up * s
        local bl = d.pos - cam_right * s - cam_up * s

        render.DrawQuad(
            tl, tr, br, bl,
            Color(d.r, d.g, d.b, math.floor(255 * alpha))
        )
    end
end)

-- ============================================================
--  NET RECEIVER  –  GekkoBloodGeyser
--  flag 1 = BURST  (hit during combat)
--  flag 0 = STREAM (ragdoll bleed)
-- ============================================================
net.Receive("GekkoBloodGeyser", function()
    local origin = net.ReadVector()
    local dir    = net.ReadVector()
    local flag   = net.ReadUInt(1)   -- 0 = stream, 1 = burst

    if flag == 1 then
        -- ---- BURST: old geyser system + heavy droplet spray ----
        -- Pick one of the 5 geyser variants (these functions are
        -- defined in cl_init.lua and are globals by the time this
        -- file is included).
        local variant = math.random(1, 5)
        if     variant == 1 then BloodVariant_Geyser(origin)
        elseif variant == 2 then BloodVariant_RadialRing(origin)
        elseif variant == 3 then BloodVariant_BurstCloud(origin)
        elseif variant == 4 then BloodVariant_ArcShower(origin, dir)
        elseif variant == 5 then BloodVariant_GroundPool(origin)
        end

        -- New droplet layer on top
        SpawnDroplets(
            origin, dir,
            math.random(BURST_COUNT_MIN, BURST_COUNT_MAX),
            BURST_SPEED_MIN, BURST_SPEED_MAX
        )

        -- Proximity screen-shake so nearby players feel the impact
        local ply = LocalPlayer()
        if IsValid(ply) then
            local dist  = ply:GetPos():Distance(origin)
            local alpha = 1 - math.Clamp(dist / 600, 0, 1)
            if alpha > 0 then
                util.ScreenShake(origin, 8 * alpha, 18, 0.12, 600)
            end
        end
    else
        -- ---- STREAM: lighter drip for ragdoll bleeding ----
        -- No geyser variant — just a steady trickle of droplets
        -- aimed slightly downward from the wound site.
        local drip_dir = (dir + Vector(0, 0, -0.7)):GetNormalized()
        SpawnDroplets(
            origin, drip_dir,
            math.random(STREAM_COUNT_MIN, STREAM_COUNT_MAX),
            STREAM_SPEED_MIN, STREAM_SPEED_MAX
        )
    end
end)
