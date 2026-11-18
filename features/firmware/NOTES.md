# firmware

## Overview

Firmware updates via fwupd/LVFS: `fwupdmgr refresh && fwupdmgr update`.

The `lvfs-testing` remote was dropped with the ThinkPad Universal USB-C Dock
(40AY), whose firmware is published only there. Re-add
`services.fwupd.extraRemotes = [ "lvfs-testing" ];` if a device needs it.
