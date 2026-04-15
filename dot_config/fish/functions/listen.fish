function listen --description "Stream MPD audio and open rmpc"
    mpv --no-video http://$MPD_HOST:8000/mpd.ogg &
    set stream_pid $last_pid
    rmpc
    kill $stream_pid 2>/dev/null
end
