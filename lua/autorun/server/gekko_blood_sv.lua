-- ============================================================
--  lua/autorun/server/gekko_blood_sv.lua
--  Server-side blood signal for npc_vj_gekko.
--  Hooks EntityTakeDamage, sends GekkoBloodHit net message
--  with a random variant to all clients on bullet impact.
--  lua/autorun/client/gekko_blood.lua handles the visuals.
--
--  Requires NO changes to init.lua or cl_init.lua.
-- ============================================================
if CLIENT then return end

util.AddNetworkString("GekkoBloodHit")

hook.Add("EntityTakeDamage", "GekkoBloodSignal", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end
    if not dmginfo:IsBulletDamage() then return end

    -- Pick a random blood variant:
    --   0 = HemoStream (sustained 12-second drip)
    --   1 = Geyser     (upward burst)
    --   2 = RadialRing (360 horizontal ring)
    --   3 = BurstCloud (omnidirectional)
    --   4 = ArcShower  (forward-biased)
    --   5 = GroundPool (low horizontal spread)
    net.Start("GekkoBloodHit")
        net.WriteEntity(ent)
        net.WriteUInt(math.random(0, 5), 3)
    net.Broadcast()
end)
