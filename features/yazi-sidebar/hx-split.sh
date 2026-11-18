#!/bin/sh
# Prints "<editor> <sidebar> <pid>" for the window id in $1, reading the
# `kitten @ ls` JSON on stdin. A window with no sidebar prints
# "<window> - -", and <editor> is the editor even when $1 is its sidebar.
jq -r --arg active "${1:?usage: hx-split.sh <window-id>}" '
  [.[].tabs[].windows[]] as $windows
  | (first($windows[] | select((.id | tostring) == $active)) // {}) as $window
  | ($window.user_vars.hx_sidebar // $active) as $editor
  | (first($windows[] | select(.user_vars.hx_sidebar == $editor)) // null) as $sidebar
  | if $sidebar == null or ([$windows[] | select((.id | tostring) == $editor)] == [])
    then "\($active) - -"
    else "\($editor) \($sidebar.id) \($sidebar.env.HX_SIDEBAR_PID)"
    end'
