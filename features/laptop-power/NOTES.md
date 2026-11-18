# laptop-power

## services.tlp

Three power profiles, switched by tlp-pd (power-profiles-daemon D-Bus API, so the waybar pill and `tlpctl performance|balanced|power-saver` work):

```
performance  = the _AC parameters
balanced     = the _BAT parameters: EPP balance_power with turbo
               available, so HWP decides and ramps up under load itself
power-saver  = the _SAV parameters, falling back to _BAT for anything
               without a _SAV value; this is the pre-2026-09 battery
               policy (EPP power, no turbo)
```

`tlpctl launch -p performance -- <cmd>` holds a profile for one command. No CPU_SCALING_GOVERNOR_ON_SAV: it falls back to _BAT = powersave, the only sensible governor under intel_pstate active mode.
