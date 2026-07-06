# GTK 4 apps (e.g. Nicotine+) render a blank/invisible window over XQuartz and
# other remote X servers: the default GL renderer can't get a GLX drawable
# (no DRI3, "failed to create drisw screen"). Force the software cairo renderer
# when we're inside an X-forwarded SSH session.
if set -q SSH_CONNECTION; and set -q DISPLAY
    set -gx GSK_RENDERER cairo
end
