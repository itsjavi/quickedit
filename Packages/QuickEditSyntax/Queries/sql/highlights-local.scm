; QuickEdit: upstream number patterns use Lua patterns (%d) and never match.
((literal) @number
  (#match? @number "^[-+]?\\d+$"))
((literal) @number
  (#match? @number "^[-+]?\\d*\\.\\d+$"))
