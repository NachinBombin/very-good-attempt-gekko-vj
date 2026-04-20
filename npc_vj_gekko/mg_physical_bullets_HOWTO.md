# Gekko MG Physical Bullets — Integration Guide

File: `mg_physical_bullets.lua`  
Branch: `gekko-physical-bullets`

---

## What this file does

Fully standalone physical bullet system that replaces the `FireBullets()` call
inside `FireMGBurst`. Features:

- Real projectile position simulated every tick via `Think` hook
- Bullet gravity (pitch drops toward ground at `FALL_SPEED` deg/sec)
- Velocity decay (bleeds to 90% of muzzle velocity over time)
- **Ricochet** off metal/concrete/tile surfaces at shallow angles (< ~53°)
  - Reflected direction randomised by `RICOCHET_SPREAD`
  - Child bullet loses 40% speed and 50% damage
  - One bounce only (`noRicochet = true` on child)
- Tracer every 3rd bullet — orange beam + sprite rendered client-side
- Whiz sound when a bullet passes within 192 units of the local player
- Penetration intentionally **not** implemented

---

## Step 1 — Register the file

In `init.lua`, at the top with the other `AddCSLuaFile` / `include` calls:

```lua
AddCSLuaFile("mg_physical_bullets.lua")
include("mg_physical_bullets.lua")      -- SERVER loads serverside logic
```

In `cl_init.lua`:

```lua
include("mg_physical_bullets.lua")      -- CLIENT loads render + whiz logic
```

---

## Step 2 — Register the new net strings

In `init.lua`, alongside the existing `util.AddNetworkString` calls:

```lua
-- these are already added inside mg_physical_bullets.lua on SERVER
-- but listed here for documentation:
--   util.AddNetworkString("GekkoMGPhysBulFire")
--   util.AddNetworkString("GekkoMGPhysBulRico")
-- NO action needed — the file handles it automatically.
```

---

## Step 3 — Replace FireBullets in FireMGBurst

In `init.lua`, find the `FireMGBurst` function.  
Replace the entire `ent:FireBullets({ ... })` block with:

```lua
-- BEFORE (remove this):
ent:FireBullets({
    Attacker   = ent,
    Damage     = MG_DAMAGE,
    Dir        = dir,
    Src        = src,
    AmmoType   = "AR2",
    TracerName = "Tracer",
    Num        = 1,
    Spread     = Vector(mgSpread,mgSpread,mgSpread),
    Callback   = function(_, tr, _)
        if tr.Hit and tr.HitNormal then
            SendBulletImpact(tr.HitPos, tr.HitNormal, 1)
        end
    end,
})

-- AFTER (add this):
GekkoMGPhysBul_Fire(ent, src, dir, MG_DAMAGE)
```

> **Note:** Spread is now handled internally by the physical bullet's
> ricochet randomisation. You can remove the `mgSpread` variable from
> `FireMGBurst` or keep it unused — it won't affect anything.

> **Note:** `SendBulletImpact` is now called inside the bullet's own
> `FireBullets` callback. No need to call it manually.

---

## Step 4 — Nothing else needed

The system is fully self-contained:
- `Think` hook drives server simulation
- `Think` hook drives client simulation  
- `PostDrawOpaqueRenderables` renders tracers
- Net messages are registered inside the file
- No changes to `shared.lua`, `cl_init.lua` (other than the include),
  or any other system file

---

## Tuning constants (top of `mg_physical_bullets.lua`)

| Constant | Default | Effect |
|---|---|---|
| `MUZZLE_VELOCITY` | `12000` | Units/sec at fire (raise = flatter trajectory) |
| `FALL_SPEED` | `1.5` | Degrees/sec pitch drop (raise = more drop) |
| `RICOCHET_VEL_SCALE` | `0.60` | Speed multiplier after bounce |
| `RICOCHET_DMG_SCALE` | `0.50` | Damage multiplier after bounce |
| `RICOCHET_SPREAD` | `0.06` | Random scatter on reflected direction |
| `TRACER_EVERY` | `3` | Every Nth bullet has a visible tracer |
| `WHIZ_DISTANCE` | `192` | Units radius for whiz sound |
| `MAX_LIFETIME` | `2.5` | Seconds before bullet auto-expires |
