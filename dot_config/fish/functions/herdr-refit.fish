function herdr-refit --description "Resize herdr panes stuck at a stale mobile client size"
    # herdr sizes a pane's PTY to the last client that *attached* to it, not the
    # last one you interact with (herdrdev/herdr#1401). After switching from the
    # phone to the desktop, leftover mobile attach streams keep new panes at the
    # phone's geometry, and resizing the desktop window never recovers them
    # (herdrdev/herdr#985). Attaching a client with --takeover evicts the stale
    # owner; releasing it lets the server resize the pane to its layout rect.
    #
    # Usage: herdr-refit [--host HOST] [--dry-run] [pane-id ...]
    #                    (default: every pane in the session)
    #
    # --host / $HERDR_REFIT_HOST force the target machine. This matters because a
    # `herdr pane list` probe cannot tell us who owns the session: a machine that
    # mirrors a remote session runs its own local herdr server, which answers the
    # probe with its own panes. Without an override we would refit the mirror.

    argparse 'host=' 'dry-run' -- $argv
    or return 1

    # Run against the explicit host, else the local server if there is one, else
    # the server over ssh.
    set -l host ""
    if set -q _flag_host
        set host $_flag_host
    else if set -q HERDR_REFIT_HOST
        set host $HERDR_REFIT_HOST
    else if not herdr pane list >/dev/null 2>&1
        for c in serveserve.local 100.72.11.128
            if nc -z -w2 $c 22 2>/dev/null
                set host $c
                break
            end
        end
        if test -z "$host"
            echo "herdr-refit: no local herdr server, and serveserve is unreachable"
            return 1
        end
    end

    set -l where "the local herdr server"
    if test -n "$host"
        set where $host
    end

    set -l snap (__herdr_refit_exec "$host" herdr api snapshot)
    if test (count $snap) -eq 0
        echo "herdr-refit: could not read the pane layout from $where"
        return 1
    end

    # A machine that mirrors a remote session runs its own herdr server, and that
    # server answers with herdr-mirror shim panes whose layout rects are thumbnail
    # geometry rather than the real session's. Refitting to those shrinks healthy
    # panes instead of restoring them, so refuse rather than resize the wrong end.
    # Note we cannot tell these apart geometrically: each workspace holds a single
    # pane, so identical rects and origins are normal on the real server too.
    set -l total (printf '%s\n' $snap | jq -r '(.result.snapshot.panes // []) | length')
    set -l mirrored (printf '%s\n' $snap \
        | jq -r '[(.result.snapshot.panes // [])[] | select((.cwd // "") | test("herdr-mirror"))] | length')
    if test "$mirrored" -gt 0 -a "$mirrored" -eq "$total"
        echo "herdr-refit: all $total panes on $where are herdr-mirror shims, so its"
        echo "             layout rects mirror a remote session rather than describe one."
        echo "             Target the machine that owns the session: herdr-refit --host HOST"
        return 1
    end

    # "<pane-id> <cols> <rows>" per pane, from the layout the server already knows.
    set -l rects (printf '%s\n' $snap \
        | jq -r '.result.snapshot.layouts[].panes[] | "\(.pane_id) \(.rect.width) \(.rect.height)"')
    if test (count $rects) -eq 0
        echo "herdr-refit: could not read the pane layout from $where"
        return 1
    end

    for rect in $rects
        set -l fields (string split ' ' -- $rect)
        if test (count $argv) -gt 0; and not contains -- $fields[1] $argv
            continue
        end
        if set -q _flag_dry_run
            echo "would refit $fields[1] ($fields[2]x$fields[3]) on $where"
            continue
        end
        __herdr_refit_exec "$host" "sleep 2 | herdr terminal session control $fields[1] --cols $fields[2] --rows $fields[3] --takeover >/dev/null 2>&1"
        echo "refit $fields[1] ($fields[2]x$fields[3])"
    end
end

function __herdr_refit_exec --description "Run a herdr command locally or on the herdr host"
    set -l host $argv[1]
    set -l cmd 'PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"; '(string join ' ' -- $argv[2..])
    if test -z "$host"
        sh -c $cmd
    else
        # command ssh: the interactive `kitten ssh` alias mangles remote commands.
        command ssh $host /bin/sh -c (string escape -- $cmd)
    end
end
