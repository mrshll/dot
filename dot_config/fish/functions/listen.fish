function listen --description "Stream MPD audio and open rmpc"
    mpv --no-video --really-quiet http://$MPD_HOST:8000/mpd.ogg >/dev/null 2>&1 &
    set stream_pid $last_pid
    rmpc
    kill $stream_pid 2>/dev/null
end
