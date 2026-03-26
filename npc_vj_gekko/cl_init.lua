include("shared.lua")

-- ============================================================
--  STOMP LEG DRIVER (the old "broken" huge stride sine wave)
--  Runs only during GekkoStompEnd window.
--  High freq + high amp = chaotic thrashing legs.
-- ============================================================
local function GekkoStompLegs(ent)
    local t    = CurTime()
    local freq = 14      -- very fast cycle
    local amp  = 55      -- huge amplitude — the original "broken" look

    local phaseR = t * freq
    local phaseL = t * freq + math.pi

    local function setB(name, a)
        local id = ent:LookupBone(name)
        if id and id >= 0 then ent:ManipulateBoneAngles(id, a, false) end
    end

    setB("b_r_thigh",     Angle(math.sin(phaseR)       * amp,        0, 0))
    setB("b_r_upperleg",  Angle(math.sin(phaseR + 0.4) * amp * 0.7,  0, 0))
    setB("b_r_calf",      Angle(math.sin(phaseR + 0.9) * amp * 0.5,  0, 0))
    setB("b_r_foot",      Angle(math.sin(phaseR + 1.2) * -amp * 0.4, 0, 0))
    setB("b_r_toe",       Angle(math.sin(phaseR + 1.5) * -amp * 0.3, 0, 0))

    setB("b_l_thigh",     Angle(math.sin(phaseL)       * amp,        0, 0))
    setB("b_l_upperleg",  Angle(math.sin(phaseL + 0.4) * amp * 0.7,  0, 0))
    setB("b_l_calf",      Angle(math.sin(phaseL + 0.9) * amp * 0.5,  0, 0))
    setB("b_l_foot",      Angle(math.sin(phaseL + 1.2) * -amp * 0.4, 0, 0))
    setB("b_l_toe",       Angle(math.sin(phaseL + 1.5) * -amp * 0.3, 0, 0))

    -- Pelvis slams down for stomp emphasis
    local slam = math.abs(math.sin(t * freq * 0.5)) * 12
    setB("b_pelvis",       Angle(slam, 0, 0))
    setB("b_r_hippiston1", Angle(math.sin(phaseR) * amp * 0.4, 0, 0))
    setB("b_l_hippiston1", Angle(math.sin(phaseL) * amp * 0.4, 0, 0))
end

function ENT:Draw()
    self:SetupBones()

    -- ---- Spine / head aim ----
    if not self._spineBone then
        self._spineBone = self:LookupBone("b_spine4")
    end

    local bone = self._spineBone
    if bone and bone >= 0 then
        local t       = CurTime()
        local bodyYaw = self:GetAngles().y
        local vel     = self:GetNWFloat("GekkoSpeed", 0)
        local enemy   = self:GetNWEntity("GekkoEnemy", NULL)

        if not self._cl_headYaw then
            self._cl_headYaw    = bodyYaw
            self._cl_headDir    = 1
            self._cl_scanNext   = t + 1.5
            self._cl_scanTarget = bodyYaw
            self._cl_lastT      = t
        end

        local dt = math.Clamp(t - self._cl_lastT, 0, 0.05)
        self._cl_lastT = t

        local targetYaw
        if IsValid(enemy) then
            local toEnemy = (enemy:GetPos() + Vector(0,0,40) - self:GetPos()):Angle()
            targetYaw = toEnemy.y
        elseif vel < 6 then
            if t > self._cl_scanNext then
                self._cl_headDir    = -self._cl_headDir
                self._cl_scanNext   = t + math.Rand(2, 5)
                self._cl_scanTarget = bodyYaw + self._cl_headDir * math.Rand(35, 70)
            end
            targetYaw = self._cl_scanTarget
        else
            targetYaw = bodyYaw
        end

        local relTarget = math.Clamp(math.NormalizeAngle(targetYaw - bodyYaw), -70, 70)
        targetYaw = bodyYaw + relTarget

        self._cl_headYaw = bodyYaw + math.Clamp(math.NormalizeAngle(self._cl_headYaw - bodyYaw), -70, 70)

        local maxTurn = 180 * dt
        local diff    = math.NormalizeAngle(targetYaw - self._cl_headYaw)
        self._cl_headYaw = self._cl_headYaw + math.Clamp(diff, -maxTurn, maxTurn)

        local rel = math.Clamp(math.NormalizeAngle(self._cl_headYaw - bodyYaw), -70, 70)
        self:ManipulateBoneAngles(bone, Angle(-rel, 0, 0), false)
    end

    -- ---- Stomp melee leg override ----
    local stompEnd = self:GetNWFloat("GekkoStompEnd", 0)
    if CurTime() < stompEnd then
        GekkoStompLegs(self)
    end

    self:DrawModel()
end