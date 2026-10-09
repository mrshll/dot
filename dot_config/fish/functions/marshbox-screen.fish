function marshbox-screen --description "Show marshbox's desktop in Screen Sharing over an SSH tunnel"
    # marshbox's VNC server listens on its own 127.0.0.1:5900 only; this
    # carries it to 127.0.0.1:15900 here and opens Apple Screen Sharing on it.
    # `marshbox-screen stop` ends the tunnel.
    #
    # -F /dev/null leaves ~/.ssh/config out so the passh RemoteForward is not
    # requested again (a session already holding it would make this exit);
    # identity and trust are given explicitly instead. The tunnel is an ssh
    # control master on its own socket, so later runs reuse it and `stop` ends
    # exactly that connection, never anything else on the port.
    set -l port 15900
    set -l dest marsh@marshbox.local
    set -l ssh_opts -F /dev/null -S ~/.ssh/marshbox-screen.sock \
        -o IdentitiesOnly=yes -o IdentityAgent=none -i ~/.ssh/id_ed25519_marshbox \
        -o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts

    switch "$argv[1]"
        case ''
        case stop
            if ssh $ssh_opts -O check $dest 2>/dev/null
                ssh $ssh_opts -O exit $dest 2>/dev/null
            else
                echo "marshbox-screen: no tunnel running"
            end
            return 0
        case '*'
            echo "usage: marshbox-screen [stop]" >&2
            return 2
    end

    if not ssh $ssh_opts -O check $dest 2>/dev/null
        if nc -z 127.0.0.1 $port 2>/dev/null
            echo "marshbox-screen: 127.0.0.1:$port is already in use by something else; leaving it alone" >&2
            return 1
        end
        # A socket left by a tunnel that died; nothing answers on it.
        rm -f ~/.ssh/marshbox-screen.sock
        # With ExitOnForwardFailure, -f backgrounds only once the forward is up.
        if not ssh $ssh_opts -M -f -N -T \
                -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                -L 127.0.0.1:$port:127.0.0.1:5900 $dest
            echo "marshbox-screen: could not open the tunnel to $dest" >&2
            return 1
        end
    end

    open -a "Screen Sharing" vnc://127.0.0.1:$port
end
