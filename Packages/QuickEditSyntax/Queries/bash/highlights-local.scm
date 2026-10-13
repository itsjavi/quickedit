; QuickEdit additions: variables and expansions, assignment values, numbers, declaration keywords.
(variable_name) @variable
[(simple_expansion) (expansion)] @variable
(special_variable_name) @variable.builtin
(variable_assignment value: (word) @string)
(number) @number
(test_operator) @operator
["declare" "typeset" "readonly" "local" "unset" "unsetenv" "until"] @keyword
(string (simple_expansion) @string.special)
(string (expansion) @string.special)
(string (command_substitution) @string.special)
(simple_expansion "$" @variable)
(expansion ["${" "}"] @variable)
(string (simple_expansion "$" @string.special))
(string (expansion ["${" "}"] @string.special))
(string (simple_expansion (variable_name) @string.special))
(string (expansion (variable_name) @string.special))
