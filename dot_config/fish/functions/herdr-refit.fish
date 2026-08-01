function herdr-refit --description "Resize herdr panes stuck at a stale mobile client size"
    # herdr sizes a pane's PTY to the last client that *attached* to it, not the
    # last one you interact with (herdrdev/herdr#1401). After switching from the
    # phone to the desktop, leftover mobile attach streams keep new panes at the
    # phone's geometry, and resizing the desktop window never recovers them
    # (herdrdev/herdr#985). Attaching a client with --takeover evicts the stale
    # owner; releasing it lets the server resize the pane to its layout rect.
    #
    # Usage: herdr-refit [pane-id ...]   (default: every pane in the session)

    # Run against the local server if there is one, else the server over ssh.
    set -l host ""
    if not herdr pane list >/dev/null 2>&1
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

    # "<pane-id> <cols> <rows>" per pane, from the layout the server already knows.
    set -l rects (__herdr_refit_exec "$host" herdr api snapshot \
        | jq -r '.result.snapshot.layouts[].panes[] | "\(.pane_id) \(.rect.width) \(.rect.height)"')
    if test (count $rects) -eq 0
        echo "herdr-refit: could not read the pane layout"
        return 1
    end

    for rect in $rects
        set -l fields (string split ' ' -- $rect)
        if test (count $argv) -gt 0; and not contains -- $fields[1] $argv
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
