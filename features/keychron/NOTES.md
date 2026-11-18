# keychron

## Overview

Keychron keyboard support: WebHID access for launcher.keychron.com and chromium as the required browser (WebHID not available in Firefox).

uaccess/udev-acl tags don't fire under sway/Wayland sessions; use GROUP="plugdev" + MODE="0660" instead so the user gets hidraw access without a logind seat grant.
