function listen --description "Stream music from MPD on serveserve"
    # Prefer the LAN name, fall back to the Tailscale IP (mirrors pond binaries).
    set -l candidates
    if test -z "$POND_SERVER" -o "$POND_SERVER" = serveserve.local
        set candidates serveserve.local 100.72.11.128
    else
        set candidates (string split ',' -- $POND_SERVER)
    end

    set -l host
    for c in $candidates
        test -n "$c"; or continue
        if nc -z -w2 $c 6600 2>/dev/null
            set host $c
            break
        end
    end
    if test -z "$host"
        echo "listen: no reachable pond server (tried $candidates)"
        return 1
    end

    set -lx MPD_HOST $host

    mpv --no-video --really-quiet "http://$host:8000/" >/dev/null 2>&1 &
    set -l stream_pid $last_pid

    rmpc

    kill $stream_pid 2>/dev/null
end
