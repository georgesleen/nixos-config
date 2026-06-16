# Battery percentage thresholds shared by the notify/hibernate service
# (battery.nix) and the i3blocks battery readout (i3blocks.nix).
# criticalPct is the hibernate target — the i3blocks time estimate counts
# down to it rather than to 0%.
{
  criticalPct = 8;
  lowPct = 15;
}
