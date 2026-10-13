; QuickEdit: TypeScript's "^[A-Z]" type rule comes after JavaScript's all-caps constant rule; restore it.
([
  (identifier)
  (shorthand_property_identifier)
  (shorthand_property_identifier_pattern)
] @constant
  (#match? @constant "^[A-Z_][A-Z\\d_]+$"))

; QuickEdit: function names stay functions even when capitalized (components), after the "^[A-Z]" rules.
(function_declaration name: (identifier) @function)
(function_expression name: (identifier) @function)
(generator_function_declaration name: (identifier) @function)
(variable_declarator
  name: (identifier) @function
  value: [(function_expression) (arrow_function)])
