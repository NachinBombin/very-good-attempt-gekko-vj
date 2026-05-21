-- cl_init.lua  (CLIENT)
-- Visual: 25mm API-T tracer beam + glow sprites.
-- Impact: decal + dust puff + bullet-impact sounds + visual ricochet tracer
--         + 3-tier explosive flash effects (small / medium / large).
include("shared.lua")

local mat_beam  = Material("effects/laser1")
local mat_glow  = Material("sprites/light_glow02_add")
local mat_smoke = Material("particle/smokestack")
local mat_exp   = Material("sprites/physbeam")

-- ─── Ricochet store ───────────────────────────────────────────────────────────
local RICO_CHANCE    = 1.0
local RICO_SPEED_MIN = 8000
local RICO_SPEED_MAX = 18000
local RICO_DUR_MIN   = 0.30
local RICO_DUR_MAX   = 0.70
local RICO_TRAIL_LEN = 180   -- fixed visual trail length in units

local active_ricos = {}

local m_random = math.random
local m_rand   = math.Rand
local m_sqrt   = math.sqrt
local m_clamp  = math.Clamp
local m_abs    = math.abs
local m_pi     = math.pi
local m_cos    = math.cos
local m_sin    = math.sin

local function spawn_visual_rico(hitPos, hitNormal)
    -- Normalise the incoming normal; fall back to Vector(0,0,1) when zero
    -- (can happen when Touch()'s short forward-trace misses geometry).
    local nx, ny, nz = hitNormal.x, hitNormal.y, hitNormal.z
    local nlen = m_sqrt(nx*nx + ny*ny + nz*nz)
    if nlen < 0.001 then
        nx, ny, nz = 0, 0, 1
    else
        nx = nx / nlen
        ny = ny / nlen
        nz = nz / nlen
    end

    local helper
    if m_abs(nz) < 0.9 then
        helper = Vector(0, 0, 1)
    else
        helper = Vector(1, 0, 0)
    end

    local n = Vector(nx, ny, nz)
    local tangent   = n:Cross(helper)  tangent:Normalize()
    local bitangent = n:Cross(tangent) bitangent:Normalize()

    local cos_theta = m_random()
    local sin_theta = m_sqrt(1 - cos_theta * cos_theta)
    local phi       = m_random() * (2 * m_pi)
    local cp        = m_cos(phi)
    local sp        = m_sin(phi)

    local dx = nx * cos_theta + tangent.x * (sin_theta * cp) + bitangent.x * (sin_theta * sp)
    local dy = ny * cos_theta + tangent.y * (sin_theta * cp) + bitangent.y * (sin_theta * sp)
    local dz = nz * cos_theta + tangent.z * (sin_theta * cp) + bitangent.z * (sin_theta * sp)
    local len = m_sqrt(dx*dx + dy*dy + dz*dz)
    if len < 0.001 then return end
    dx = dx / len  dy = dy / len  dz = dz / len

    local spd = m_rand(RICO_SPEED_MIN, RICO_SPEED_MAX)

    -- vel_dir is the normalised travel direction, used by the renderer to
    -- synthesise a fixed-length tail that is always visible regardless of
    -- how many Think ticks fire between render frames.
    active_ricos[#active_ricos + 1] = {
        pos      = Vector(hitPos.x, hitPos.y, hitPos.z),
        vel      = Vector(dx * spd, dy * spd, dz * spd),
        vel_dir  = Vector(dx, dy, dz),   -- normalised direction, never changes
        die_time = CurTime() + m_rand(RICO_DUR_MIN, RICO_DUR_MAX),
    }
end

-- ─── Impact sounds ────────────────────────────────────────────────────────────
local IMPACT_SOUNDS = {
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
}

-- ─── Dust puff ────────────────────────────────────────────────────────────────
local function SpawnDustPuff(hitPos, hitNormal)
    local emitter = ParticleEmitter(hitPos, false)
    if not emitter then return end
    for _ = 1, 6 do
        local p = emitter:Add("particle/smokestack", hitPos)
        if p then
            local scatter = VectorRand() * 18
            scatter.z     = m_abs(scatter.z)
            local vel     = hitNormal * m_rand(20, 55) + scatter
            p:SetVelocity(vel)
            p:SetLifeTime(0)
            p:SetDieTime(m_rand(0.25, 0.55))
            p:SetStartAlpha(m_random(60, 100))
            p:SetEndAlpha(0)
            p:SetStartSize(m_rand(4, 9))
            p:SetEndSize(m_rand(12, 22))
            p:SetRoll(m_rand(0, 360))
            p:SetRollDelta(m_rand(-1.5, 1.5))
            p:SetColor(
                m_random(140, 190),
                m_random(120, 160),
                m_random(80,  120)
            )
            p:SetGravity(Vector(0, 0, -30))
            p:SetAirResistance(80)
        end
    end
    emitter:Finish()
end

-- ─── IMPACT LIGHT ─────────────────────────────────────────────────────────────
local IMPACT_LIGHT = {
    [1] = { r=255, g=200, b=100, brightness=2.5, size=180, decay=3800 },
    [2] = { r=255, g=160, b=60,  brightness=3.5, size=280, decay=3200 },
    [3] = { r=255, g=120, b=30,  brightness=5.0, size=420, decay=2600 },
}

local light_uid = 1

local function SpawnImpactLight(hitPos, tier)
    local cfg = IMPACT_LIGHT[tier]
    if not cfg then return end
    light_uid = (light_uid % 64) + 1
    local dl = DynamicLight(1000 + light_uid)
    if not dl then return end
    dl.pos        = hitPos
    dl.r          = cfg.r
    dl.g          = cfg.g
    dl.b          = cfg.b
    dl.brightness = cfg.brightness
    dl.Size       = cfg.size
    dl.Decay      = cfg.decay
    dl.DieTime    = CurTime() + 0.08
end

-- ─── TIER 1: SMALL ────────────────────────────────────────────────────────────
local function ImpactTier1(hitPos, hitNormal)
    SpawnImpactLight(hitPos, 1)
    local emitter = ParticleEmitter(hitPos, false)
    if emitter then
        local p = emitter:Add("effects/yellowflare", hitPos)
        if p then
            p:SetVelocity(hitNormal * m_rand(8, 18))
            p:SetLifeTime(0)
            p:SetDieTime(m_rand(0.04, 0.07))
            p:SetStartAlpha(220)
            p:SetEndAlpha(0)
            p:SetStartSize(m_rand(5, 9))
            p:SetEndSize(m_rand(1, 3))
            p:SetRoll(m_rand(0, 360))
            p:SetColor(255, 220, 140)
            p:SetLighting(false)
        end
        for _ = 1, m_random(2, 3) do
            local sp = emitter:Add("effects/spark", hitPos)
            if sp then
                local scatter = VectorRand() * 120
                scatter.z = m_abs(scatter.z) * 1.4
                sp:SetVelocity(hitNormal * m_rand(60, 140) + scatter)
                sp:SetLifeTime(0)
                sp:SetDieTime(m_rand(0.08, 0.18))
                sp:SetStartAlpha(255)
                sp:SetEndAlpha(0)
                sp:SetStartSize(m_rand(1, 2))
                sp:SetEndSize(0)
                sp:SetColor(255, 240, 200)
                sp:SetGravity(Vector(0, 0, -160))
                sp:SetAirResistance(40)
                sp:SetLighting(false)
            end
        end
        emitter:Finish()
    end
end

-- ─── TIER 2: MEDIUM ───────────────────────────────────────────────────────────
local function ImpactTier2(hitPos, hitNormal)
    SpawnImpactLight(hitPos, 2)
    local emitter = ParticleEmitter(hitPos, false)
    if emitter then
        for _ = 1, 2 do
            local p = emitter:Add("effects/yellowflare", hitPos)
            if p then
                p:SetVelocity(hitNormal * m_rand(12, 28) + VectorRand() * 10)
                p:SetLifeTime(0)
                p:SetDieTime(m_rand(0.05, 0.09))
                p:SetStartAlpha(200)
                p:SetEndAlpha(0)
                p:SetStartSize(m_rand(8, 14))
                p:SetEndSize(m_rand(2, 5))
                p:SetRoll(m_rand(0, 360))
                p:SetColor(255, 200, 100)
                p:SetLighting(false)
            end
        end
        for _ = 1, m_random(5, 7) do
            local sp = emitter:Add("effects/spark", hitPos)
            if sp then
                local scatter = VectorRand() * 180
                scatter.z = m_abs(scatter.z) * 1.6
                sp:SetVelocity(hitNormal * m_rand(80, 200) + scatter)
                sp:SetLifeTime(0)
                sp:SetDieTime(m_rand(0.12, 0.28))
                sp:SetStartAlpha(255)
                sp:SetEndAlpha(0)
                sp:SetStartSize(m_rand(1, 3))
                sp:SetEndSize(0)
                sp:SetColor(255, 200, 100)
                sp:SetGravity(Vector(0, 0, -240))
                sp:SetAirResistance(30)
                sp:SetLighting(false)
            end
        end
        for _ = 1, 2 do
            local sm = emitter:Add("particle/smokestack", hitPos)
            if sm then
                local scatter = VectorRand() * 12
                sm:SetVelocity(hitNormal * m_rand(18, 40) + scatter)
                sm:SetLifeTime(0)
                sm:SetDieTime(m_rand(0.35, 0.65))
                sm:SetStartAlpha(m_random(45, 70))
                sm:SetEndAlpha(0)
                sm:SetStartSize(m_rand(6, 11))
                sm:SetEndSize(m_rand(18, 32))
                sm:SetRoll(m_rand(0, 360))
                sm:SetRollDelta(m_rand(-1, 1))
                sm:SetColor(m_random(100, 140), m_random(90, 120), m_random(60, 90))
                sm:SetGravity(Vector(0, 0, 18))
                sm:SetAirResistance(60)
            end
        end
        emitter:Finish()
    end
end

-- ─── TIER 3: LARGE ────────────────────────────────────────────────────────────
local function ImpactTier3(hitPos, hitNormal)
    SpawnImpactLight(hitPos, 3)
    local emitter = ParticleEmitter(hitPos, false)
    if emitter then
        for _ = 1, 3 do
            local p = emitter:Add("effects/yellowflare", hitPos)
            if p then
                local jitter = VectorRand() * 14
                p:SetVelocity(hitNormal * m_rand(18, 40) + jitter)
                p:SetLifeTime(0)
                p:SetDieTime(m_rand(0.06, 0.11))
                p:SetStartAlpha(230)
                p:SetEndAlpha(0)
                p:SetStartSize(m_rand(12, 20))
                p:SetEndSize(m_rand(3, 7))
                p:SetRoll(m_rand(0, 360))
                p:SetColor(255, 170, 60)
                p:SetLighting(false)
            end
        end
        for _ = 1, m_random(8, 11) do
            local sp = emitter:Add("effects/spark", hitPos)
            if sp then
                local scatter = VectorRand() * 260
                scatter.z = m_abs(scatter.z) * 1.8
                sp:SetVelocity(hitNormal * m_rand(120, 320) + scatter)
                sp:SetLifeTime(0)
                sp:SetDieTime(m_rand(0.18, 0.38))
                sp:SetStartAlpha(255)
                sp:SetEndAlpha(0)
                sp:SetStartSize(m_rand(2, 4))
                sp:SetEndSize(0)
                sp:SetColor(255, 160, 50)
                sp:SetGravity(Vector(0, 0, -320))
                sp:SetAirResistance(22)
                sp:SetLighting(false)
            end
        end
        for _ = 1, m_random(3, 4) do
            local sm = emitter:Add("particle/smokestack", hitPos)
            if sm then
                local scatter = VectorRand() * 22
                sm:SetVelocity(hitNormal * m_rand(28, 60) + scatter)
                sm:SetLifeTime(0)
                sm:SetDieTime(m_rand(0.45, 0.80))
                sm:SetStartAlpha(m_random(55, 80))
                sm:SetEndAlpha(0)
                sm:SetStartSize(m_rand(9, 16))
                sm:SetEndSize(m_rand(26, 46))
                sm:SetRoll(m_rand(0, 360))
                sm:SetRollDelta(m_rand(-1.2, 1.2))
                sm:SetColor(m_random(70, 110), m_random(60, 95), m_random(40, 70))
                sm:SetGravity(Vector(0, 0, 28))
                sm:SetAirResistance(50)
            end
        end
        emitter:Finish()
    end
end

-- ─── Net: impact ──────────────────────────────────────────────────────────────
net.Receive("GekkoBushImpact", function()
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local sndIdx    = net.ReadUInt(8)
    local tier      = net.ReadUInt(2)
    sndIdx = m_clamp(sndIdx, 1, #IMPACT_SOUNDS)
    if tier < 1 then tier = 1 end
    if tier > 3 then tier = 3 end

    util.Decal("Impact.Concrete", hitPos + hitNormal * 2, hitPos - hitNormal * 4)
    SpawnDustPuff(hitPos, hitNormal)
    sound.Play(IMPACT_SOUNDS[sndIdx], hitPos, 75, m_random(95, 110), 1.0)

    -- Always spawn a rico; spawn_visual_rico handles zero/denormal normals.
    spawn_visual_rico(hitPos, hitNormal)

    if     tier == 1 then ImpactTier1(hitPos, hitNormal)
    elseif tier == 2 then ImpactTier2(hitPos, hitNormal)
    else                   ImpactTier3(hitPos, hitNormal)
    end
end)

-- ─── Ricochet ticker ──────────────────────────────────────────────────────────
-- Advances rico positions using raw CurTime() delta.
-- old_pos is intentionally NOT stored here; the renderer derives the tail
-- from vel_dir (normalised direction) so it is always the correct length.
local last_think = 0

hook.Add("Think", "gekko_bushmaster_rico_tick", function()
    local now = CurTime()
    local dt  = now - last_think
    last_think = now
    -- clamp dt: skip stall frames, prevent large jumps
    if dt <= 0 or dt > 0.1 then return end

    local rc = #active_ricos
    local i  = 1
    while i <= rc do
        local r = active_ricos[i]
        if now >= r.die_time then
            active_ricos[i] = active_ricos[rc]
            active_ricos[rc] = nil
            rc = rc - 1
        else
            r.pos.x = r.pos.x + r.vel.x * dt
            r.pos.y = r.pos.y + r.vel.y * dt
            r.pos.z = r.pos.z + r.vel.z * dt
            i = i + 1
        end
    end
end)

-- ─── Per-entity tracer + ricochet renderer ────────────────────────────────────
local g_bush_renderers = {}

local function render_bush_tracers()
    local cam_pos   = EyePos()
    local min_trail = 120

    -- ─ live projectile tracers ─
    for entIdx, _ in pairs(g_bush_renderers) do
        local ent = Entity(entIdx)
        if not IsValid(ent) then
            g_bush_renderers[entIdx] = nil
            continue
        end

        local render_pos = ent:GetRenderOrigin() or ent:GetPos()
        local fwd        = ent:GetForward()
        local tail_end   = render_pos - fwd * min_trail

        local dist  = m_sqrt(cam_pos:DistToSqr(render_pos))
        local scale = m_clamp(dist / 1200, 1.5, 5)

        render.SetMaterial(mat_beam)
        if render_pos:DistToSqr(tail_end) > 4 then
            render.DrawBeam(tail_end, render_pos, 8 * scale, 0, 1, Color(255, 240, 160, 255))
        end
        render.DrawBeam(tail_end, render_pos, 22 * scale, 0, 1, Color(255, 120, 0, 120))

        render.SetMaterial(mat_glow)
        render.DrawSprite(render_pos, 70 * scale, 70 * scale, Color(255, 160, 20, 200))
        render.DrawSprite(render_pos, 18 * scale, 18 * scale, Color(255, 255, 200, 255))
    end

    -- ─ visual ricochets ─
    local rc = #active_ricos
    if rc > 0 then
        local now = CurTime()
        for i = 1, rc do
            local r = active_ricos[i]
            if not r or now >= r.die_time then continue end

            local render_pos = r.pos

            local tail_end = Vector(
                render_pos.x - r.vel_dir.x * RICO_TRAIL_LEN,
                render_pos.y - r.vel_dir.y * RICO_TRAIL_LEN,
                render_pos.z - r.vel_dir.z * RICO_TRAIL_LEN
            )

            local life_frac  = m_clamp((r.die_time - now) / RICO_DUR_MAX, 0, 1)

            local alpha_core = life_frac * 255
            local alpha_halo = life_frac * 160
            local alpha_glow = life_frac * 220
            local alpha_tip  = life_frac * 255

            local dist  = m_sqrt(cam_pos:DistToSqr(render_pos))
            local scale = m_clamp(dist / 1200, 1.2, 4.5)

            render.SetMaterial(mat_beam)
            render.DrawBeam(tail_end, render_pos, 10 * scale, 0, 1, Color(255, 255, 180, alpha_core))
            render.DrawBeam(tail_end, render_pos, 28 * scale, 0, 1, Color(255, 140, 0,   alpha_halo))

            render.SetMaterial(mat_glow)
            render.DrawSprite(render_pos, 100 * scale, 100 * scale, Color(255, 180, 30,  alpha_glow))
            render.DrawSprite(render_pos,  26 * scale,  26 * scale, Color(255, 255, 220, alpha_tip))
        end
    end
end

hook.Add("PostDrawTranslucentRenderables", "gekko_bushmaster_render", function(depth, skybox)
    if depth or skybox then return end
    render_bush_tracers()
end)

-- =========================================================================
-- ENT callbacks
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end
    self:SetRenderBounds(Vector(-64, -64, -64), Vector(64, 64, 64))
    g_bush_renderers[self:EntIndex()] = true
end

function ENT:Draw()
    local pos = self:GetRenderOrigin() or self:GetPos()
    if not pos then return end

    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.pos        = pos
        dlight.r          = 255
        dlight.g          = 160
        dlight.b          = 20
        dlight.brightness = 4
        dlight.Decay      = 1400
        dlight.Size       = 280
        dlight.DieTime    = CurTime() + 0.05
    end
end

function ENT:OnRemove()
    g_bush_renderers[self:EntIndex()] = nil
    local dl = DynamicLight(self:EntIndex())
    if dl then dl.DieTime = 0 end
end
