function marshbox-screen --description "Show marshbox's desktop in Screen Sharing over an SSH tunnel"
    # marshbox's VNC server listens on its own 127.0.0.1:5900 only; this
    # carries it to 127.0.0.1:15900 here and opens Apple Screen Sharing on it.
    # Closing Screen Sharing leaves the tunnel up for next time;
    # `marshbox-screen stop` ends it (and any viewer using it), but never the
    # VNC service on marshbox.
    #
    # -F /dev/null leaves ~/.ssh/config out so the passh RemoteForward is not
    # requested again (a session already holding it would make this exit);
    # identity and trust are given explicitly instead. The tunnel is an ssh
    # control master on its own socket, so later runs reuse it and `stop` ends
    # exactly that connection, never anything else on the port. A reused
    # master keeps the forward it started with: after changing the endpoint
    # here, `stop` first.
    switch "$argv[1]"
        case '' stop
        case '*'
            echo "usage: marshbox-screen [stop]" >&2
            return 2
    end

    # One start or stop at a time, so a concurrent run never mistakes a tunnel
    # that is still starting for a dead one and removes its socket. The lock is
    # a kernel flock (macOS has no flock(1), so perl takes it) handed to the
    # worker fish as fd 9: the process doing the work holds it, and the kernel
    # drops it however that process ends. The ssh master is started with fd 9
    # closed, so the tunnel it leaves running never holds the lock.
    perl -MFcntl=:flock -MPOSIX=dup2 -e '
        open(my $lock, ">>", shift) or die "marshbox-screen: cannot open lock: $!\n";
        for (1 .. 10) {
            if (flock($lock, LOCK_EX | LOCK_NB)) {
                defined dup2(fileno($lock), 9) or die "marshbox-screen: lock: $!\n";
                exec @ARGV or die "marshbox-screen: $!\n";
            }
            select(undef, undef, undef, 0.3);
        }
        warn "marshbox-screen: another marshbox-screen is starting or stopping the tunnel; try again\n";
        exit 1;
    ' ~/.ssh/marshbox-screen.lock \
        (status fish-path) --no-config -c 'source $argv[1]; __marshbox_screen $argv[2..]' \
        (functions --details marshbox-screen) $argv
end

function __marshbox_screen
    set -l port 15900
    set -l dest marsh@marshbox.local
    set -l ssh_opts -F /dev/null -S ~/.ssh/marshbox-screen.sock \
        -o IdentitiesOnly=yes -o IdentityAgent=none -i ~/.ssh/id_ed25519_marshbox \
        -o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts

    if test "$argv[1]" = stop
        if not ssh $ssh_opts -O check $dest 2>/dev/null
            echo "marshbox-screen: no tunnel running"
            return 0
        end
        if not ssh $ssh_opts -O exit $dest 2>/dev/null
            echo "marshbox-screen: the tunnel did not stop" >&2
            return 1
        end
        return 0
    end

    if not ssh $ssh_opts -O check $dest 2>/dev/null
        # lsof, not a connection: anything reaching marshbox's VNC port without
        # authenticating counts towards TigerVNC blacklisting this address.
        if lsof -nP -iTCP@127.0.0.1:$port -sTCP:LISTEN -t >/dev/null 2>&1
            echo "marshbox-screen: 127.0.0.1:$port is already in use by something else; leaving it alone" >&2
            return 1
        end
        # Under the lock, a socket nothing answers on is left by a dead tunnel.
        rm -f ~/.ssh/marshbox-screen.sock
        # With ExitOnForwardFailure, -f backgrounds only once the forward is up.
        if not ssh $ssh_opts -M -f -N -T \
                -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                -L 127.0.0.1:$port:127.0.0.1:5900 $dest 9>&-
            echo "marshbox-screen: could not open the tunnel to $dest" >&2
            return 1
        end
    end

    # The tunnel comes up whether or not anything listens on marshbox's 5900,
    # and the VNC service there is transient (gone after a logout or reboot).
    # Ask marshbox over the tunnel's own connection whether it listens. Never
    # probe the VNC port itself: TigerVNC counts every unauthenticated
    # connection towards blacklisting this address.
    if not ssh $ssh_opts $dest 'ss -Hltn "sport = :5900"' 2>/dev/null | string match -q '*127.0.0.1:5900*'
        echo "marshbox-screen: tunnel is up, but nothing listens on marshbox's 127.0.0.1:5900;" \
            "start its desktop-sharing service, then run this again" >&2
        return 1
    end

    if not open -a "Screen Sharing" vnc://127.0.0.1:$port
        echo "marshbox-screen: could not open Screen Sharing; the tunnel stays up (marshbox-screen stop ends it)" >&2
        return 1
    end
end
