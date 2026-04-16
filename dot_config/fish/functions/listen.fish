function listen --description "Stream music from MPD on serveserve"
    set -l host $POND_SERVER
    if test -z "$host"
        echo "POND_SERVER not set"
        return 1
    end

    mpv --no-video --really-quiet "http://$host:8000/" >/dev/null 2>&1 &
    set -l stream_pid $last_pid

    rmpc

    kill $stream_pid 2>/dev/null
end
