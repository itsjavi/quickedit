; QuickEdit Nix highlights (replaces upstream, whose order assumes "first match wins": its generic identifier
; rules come last).

(comment) @comment

["if" "then" "else" "let" "inherit" "in" "rec" "with" "assert" "or"] @keyword

(identifier) @variable

(binding attrpath: (attrpath (identifier) @property))
(inherited_attrs attr: (identifier) @property)
(select_expression attrpath: (attrpath (identifier) @property))

(function_expression universal: (identifier) @variable.parameter)
(formal name: (identifier) @variable.parameter)

(apply_expression
  function: [
    (variable_expression (identifier) @function)
    (select_expression attrpath: (attrpath attr: (identifier) @function .))
  ])

((identifier) @constant.builtin
  (#any-of? @constant.builtin "true" "false" "null"))

((identifier) @variable.builtin
  (#any-of? @variable.builtin "builtins" "__currentSystem" "__currentTime" "__langVersion" "__nixPath" "__nixVersion" "__storeDir"))

((identifier) @function.builtin
  (#any-of? @function.builtin
    "abort" "baseNameOf" "break" "derivation" "derivationStrict" "dirOf" "fetchGit" "fetchMercurial"
    "fetchTarball" "fetchTree" "fromTOML" "import" "isNull" "map" "placeholder" "removeAttrs" "scopedImport"
    "throw" "toString"))

[(integer_expression) (float_expression)] @number
[(escape_sequence) (dollar_escape)] @escape

(unary_expression operator: _ @operator)
(binary_expression operator: _ @operator)

[";" "." "," "=" ":" "?" "@"] @punctuation.delimiter
["(" ")" "[" "]" "{" "}"] @punctuation.bracket

[(string_expression) (indented_string_expression)] @string
[(path_expression) (hpath_expression) (spath_expression)] @string.special.path
(uri_expression) @string.special.uri

(interpolation "${" @punctuation.special "}" @punctuation.special)
