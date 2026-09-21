function listen --description "Stream music from MPD on serveserve"
    # Prefer the Tailscale IP: serveserve.local resolves to global IPv6 records
    # that intermittently have no route, which fails mpv and rmpc mid-session.
    set -l candidates
    if test -z "$POND_SERVER" -o "$POND_SERVER" = serveserve.local
        set candidates 100.72.11.128 serveserve.local
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

    # The audio stream is a separate port from MPD's control port: if only 6600
    # answers, rmpc drives the library fine and playback is silent. Say so
    # instead of leaving a dead mpv behind a /dev/null redirect.
    set -l stream_pid
    set -l stream_log (mktemp)
    if nc -z -w2 $host 8000 2>/dev/null
        mpv --no-video --msg-level=all=error "http://$host:8000/" >$stream_log 2>&1 &
        set stream_pid $last_pid
        sleep 1
        if not kill -0 $stream_pid 2>/dev/null
            echo "listen: stream player exited immediately:"
            cat $stream_log
            set stream_pid
        end
    else
        echo "listen: no audio stream at $host:8000 — MPD's httpd output is down, continuing without sound"
    end

    rmpc

    if test -n "$stream_pid"
        kill $stream_pid 2>/dev/null
    end
    rm -f $stream_log
end
