# Commands for interacting with the system clipboard
#
# > These commands require your terminal to support OSC 52
# > Terminal multiplexers such as screen, tmux, zellij etc may interfere with this command

# Copy input to system clipboard
@example "Copy a string to the clipboard" { "Hello" | clip copy }
export def  copy []: [string -> nothing] {
	print -n $'(ansi osc)52;c;($in | encode base64)(ansi st)'
}


# Paste contenst of system clipboard
@example "Paste a string from the clipboard" { clip paste } --result "Hello"
export def  paste []: [nothing -> string] {
	try {
		term query $'(ansi osc)52;c;?(ansi st)' -p $'(ansi osc)52;c;' -t (ansi st)
	} catch {
		error make -u {
			msg: "Terminal did not responds to OSC 52 paste request."
			help: $"Check if your terminal supports OSC 52."
		}
	}
	| decode
	| decode base64
	| decode
}
