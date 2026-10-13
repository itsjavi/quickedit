; QuickEdit highlights for HCL and Terraform (upstream ships no queries).

(comment) @comment
(identifier) @variable

(block (identifier) @type)
(attribute (identifier) @property)
(object_elem key: (expression (variable_expr (identifier) @property)))
(get_attr (identifier) @property)
(function_call (identifier) @function)

(variable_expr
  (identifier) @variable.builtin
  (#any-of? @variable.builtin "var" "local" "module" "data" "path" "each" "count" "self" "terraform"))

[(string_lit) (quoted_template) (heredoc_template) (template_literal)] @string
[(heredoc_identifier) (heredoc_start)] @label
(numeric_lit) @number
(bool_lit) @boolean
(null_lit) @constant.builtin

[
  (template_interpolation_start) (template_interpolation_end) (template_directive_start)
  (template_directive_end) (strip_marker)
] @punctuation.special

["for" "in" "if" "else" "endif" "endfor"] @keyword

["!" "*" "/" "%" "+" "-" ">" ">=" "<" "<=" "==" "!=" "&&" "||" "?" "=>" "="] @operator
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
[(block_start) (block_end) (object_start) (object_end) (tuple_start) (tuple_end)] @punctuation.bracket
["." ".*" "," "[*]" ":"] @punctuation.delimiter
