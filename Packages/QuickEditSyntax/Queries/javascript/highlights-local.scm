; QuickEdit: a regex's slashes are part of it (otherwise they're division operators).
(regex "/" @string.special)

; QuickEdit: function names stay functions even when capitalized (components), after the "^[A-Z]" rules.
(function_declaration name: (identifier) @function)
(function_expression name: (identifier) @function)
(generator_function_declaration name: (identifier) @function)
(variable_declarator
  name: (identifier) @function
  value: [(function_expression) (arrow_function)])
