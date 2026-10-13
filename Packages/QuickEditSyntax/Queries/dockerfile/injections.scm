; QuickEdit: shell commands in RUN (and shell-form CMD/ENTRYPOINT) are bash.
((shell_command) @injection.content
  (#set! injection.language "bash")
  (#set! injection.include-children))
