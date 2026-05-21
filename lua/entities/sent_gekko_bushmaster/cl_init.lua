-- cl_init.lua  (CLIENT)
-- Visual: GAU-style tracer beam + glow sprites, identical rendering pipeline
-- to ent_ac47_m134_bullet/cl_init.lua.  Flame/spark emitter removed.
-- Impact: decal + dust puff + bullet-impact sounds + visual ricochet tracer.
include("shared.lua")

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

-- ─── Visual ricochet store ────────────────────────────────────────────────────
-- Each entry is an independent table so rapid-fire hits can't corrupt each
-- other.  The old ring-buffer reused slots by reference, meaning a new impact
-- would overwrite the pos/vel of a slot that was already in active_visuals,
-- corrupting every live ricochet that pointed at the same slot.
local RICO_CHANCE    = 0.009
local RICO_SPEED_MIN = 8000
local RICO_SPEED_MAX = 18000
local RICO_DUR_MIN   = 0.30
local RICO_DUR_MAX   = 0.70

local active_ricos = {}   -- flat list of independent ricochet tables

local m_random = math.random
local m_rand   = math.Rand
local m_sqrt   = math.sqrt
local m_clamp  = math.Clamp
local m_abs    = math.abs
local m_pi     = math.pi
local m_cos    = math.cos
local m_sin    = math.sin

local function spawn_visual_rico(hitPos, hitNormal)
    local helper
    if m_abs(hitNormal.z) < 0.9 then
        helper = Vector(0, 0, 1)
    else
        helper = Vector(1, 0, 0)
    end
    local tangent   = hitNormal:Cross(helper)  tangent:Normalize()
    local bitangent = hitNormal:Cross(tangent) bitangent:Normalize()

    local cos_theta = m_random()
    local sin_theta = m_sqrt(1 - cos_theta * cos_theta)
    local phi       = m_random() * (2 * m_pi)
    local cp        = m_cos(phi)
    local sp        = m_sin(phi)

    local dx = hitNormal.x * cos_theta + tangent.x * (sin_theta * cp) + bitangent.x * (sin_theta * sp)
    local dy = hitNormal.y * cos_theta + tangent.y * (sin_theta * cp) + bitangent.y * (sin_theta * sp)
    local dz = hitNormal.z * cos_theta + tangent.z * (sin_theta * cp) + bitangent.z * (sin_theta * sp)
    local len = m_sqrt(dx*dx + dy*dy + dz*dz)
    if len < 0.001 then return end
    dx = dx / len  dy = dy / len  dz = dz / len

    local spd = m_rand(RICO_SPEED_MIN, RICO_SPEED_MAX)

    -- Each spawn gets its own independent table — no shared slot aliasing.
    active_ricos[#active_ricos + 1] = {
        pos      = Vector(hitPos.x, hitPos.y, hitPos.z),
        old_pos  = Vector(hitPos.x, hitPos.y, hitPos.z),
        vel      = Vector(dx * spd, dy * spd, dz * spd),
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

-- ─── Net: impact (broadcasted from server Explode()) ─────────────────────────
net.Receive("GekkoBushImpact", function()
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local sndIdx    = net.ReadUInt(8)
    sndIdx = m_clamp(sndIdx, 1, #IMPACT_SOUNDS)

    util.Decal("Impact.Concrete", hitPos + hitNormal * 2, hitPos - hitNormal * 4)
    SpawnDustPuff(hitPos, hitNormal)
    sound.Play(IMPACT_SOUNDS[sndIdx], hitPos, 75, m_random(95, 110), 1.0)

    if m_random() < RICO_CHANCE then
        spawn_visual_rico(hitPos, hitNormal)
    end
end)

-- ─── Ricochet ticker ─────────────────────────────────────────────────────────
-- Think instead of CreateMove: runs even when player isn't sending input
-- (spectator, dead, paused). dt from CurTime() is never stale or zero.
local last_think = 0

hook.Add("Think", "gekko_bushmaster_rico_tick", function()
    local now = CurTime()
    local dt  = now - last_think
    last_think = now
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
            r.old_pos.x = r.pos.x
            r.old_pos.y = r.pos.y
            r.old_pos.z = r.pos.z
            r.pos.x = r.pos.x + r.vel.x * dt
            r.pos.y = r.pos.y + r.vel.y * dt
            r.pos.z = r.pos.z + r.vel.z * dt
            i = i + 1
        end
    end
end)

-- ─── Per-entity tracer + ricochet renderer ───────────────────────────────────
local g_bush_renderers = {}   -- [entIndex] = true while entity alive

local function render_bush_tracers()
    local cam_pos   = EyePos()
    local min_trail = 120

    -- ─ live rounds ─
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
            render.DrawBeam(tail_end, render_pos, 6 * scale, 0, 1, Color(255, 30, 10, 255))
        end
        render.DrawBeam(tail_end, render_pos, 18 * scale, 0, 1, Color(200, 0, 0, 110))

        render.SetMaterial(mat_glow)
        render.DrawSprite(render_pos, 60 * scale, 60 * scale, Color(255, 40, 0, 180))
        render.DrawSprite(render_pos, 16 * scale, 16 * scale, Color(255, 200, 180, 255))
    end

    -- ─ visual ricochets ─
    local rc = #active_ricos
    if rc > 0 then
        local now = CurTime()
        for i = 1, rc do
            local r = active_ricos[i]
            if not r or now >= r.die_time then continue end

            local render_pos = r.pos
            local tail_end   = r.old_pos
            local life_frac  = m_clamp((r.die_time - now) / RICO_DUR_MAX, 0, 1)

            local alpha_core = life_frac * 255
            local alpha_halo = life_frac * 160
            local alpha_glow = life_frac * 220
            local alpha_tip  = life_frac * 255

            local dist  = m_sqrt(cam_pos:DistToSqr(render_pos))
            local scale = m_clamp(dist / 1200, 1.2, 4.5)

            render.SetMaterial(mat_beam)
            if render_pos:DistToSqr(tail_end) > 4 then
                render.DrawBeam(tail_end, render_pos, 8 * scale, 0, 1, Color(255, 60, 20, alpha_core))
            end
            render.DrawBeam(tail_end, render_pos, 24 * scale, 0, 1, Color(220, 10, 0, alpha_halo))

            render.SetMaterial(mat_glow)
            render.DrawSprite(render_pos, 80 * scale, 80 * scale, Color(255, 60, 0, alpha_glow))
            render.DrawSprite(render_pos, 22 * scale, 22 * scale, Color(255, 220, 200, alpha_tip))
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
        dlight.g          = 80
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
