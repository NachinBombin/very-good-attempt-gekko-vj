-- cl_gekko_bloodpool.lua
-- Blood pool is now handled entirely server-side via
-- CreateBloodPoolForRagdoll / ParticleEffect (PCF particles).
-- No client-side net receiver needed.
-- File kept to avoid stale references.
if not CLIENT then return end
