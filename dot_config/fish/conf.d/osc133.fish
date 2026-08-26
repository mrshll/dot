# mark prompt lines with OSC 133 so tmux's previous-prompt/next-prompt work
# (fish doesn't emit these itself); used by the prefix+C-y binding in
# ~/.tmux.conf.local to yank the last command and its output
function __osc133_prompt_start --on-event fish_prompt
    printf '\e]133;A\a'
end
