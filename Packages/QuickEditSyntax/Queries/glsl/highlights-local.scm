; QuickEdit: upstream's generic `(identifier) @variable` comes after its function rules; re-assert them.
(call_expression function: (identifier) @function)
(call_expression function: (field_expression field: (field_identifier) @function))
(function_declarator declarator: (identifier) @function)
((identifier) @variable.builtin
  (#match? @variable.builtin "^gl_"))
