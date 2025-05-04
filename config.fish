if status is-interactive
    # Commands to run in interactive sessions can go here
end

set PATH /opt/homebrew/bin $PATH
alias cat='bat'
alias ls='li'
alias gcz='czg'
alias gcza='czg ai -N=3'
alias gczb='czg break'
# alias vi='nvim'
# alias vim='nvim'

function ycd
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if set cwd (command cat -- "$tmp"); and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

set --global hydro_color_prompt a6e3a1
set --global hydro_color_error f38ba8
set --global hydro_color_pwd b4befe
set --global hydro_color_git 94e2d5
set --global hydro_color_duration eba0ac
set --global hydro_multiline true
set --global hydro_symbol_prompt "❱❱"

# set --global hydro_prefix_beginning \n" "
# set --global hydro_prefix_git " "
# set --global hydro_prefix_pwd " "
# set --global hydro_prefix_duration "󰅐 "

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :
