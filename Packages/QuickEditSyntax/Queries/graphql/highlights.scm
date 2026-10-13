; QuickEdit highlights for GraphQL (upstream ships no queries).

(comment) @comment
[(description) (string_value)] @string
[(int_value) (float_value)] @number
(boolean_value) @boolean
(null_value) @constant.builtin
(enum_value) @constant
(directive_location) @constant.builtin
(variable) @variable.parameter

(named_type (name) @type)
[
  (scalar_type_definition (name) @type)
  (object_type_definition (name) @type)
  (interface_type_definition (name) @type)
  (union_type_definition (name) @type)
  (enum_type_definition (name) @type)
  (input_object_type_definition (name) @type)
  (scalar_type_extension (name) @type)
  (object_type_extension (name) @type)
  (interface_type_extension (name) @type)
  (union_type_extension (name) @type)
  (enum_type_extension (name) @type)
  (input_object_type_extension (name) @type)
]

(field (name) @property)
(alias (name) @property)
(field_definition (name) @property)
(object_field (name) @property)
(input_value_definition (name) @variable.parameter)
(argument (name) @variable.parameter)

(operation_definition (name) @function)
(fragment_name) @function

(directive "@" @attribute (name) @attribute)
(directive_definition "@" @attribute (name) @attribute)

(operation_type) @keyword
[
  "query" "mutation" "subscription" "fragment" "on" "type" "interface" "union" "enum" "input" "scalar"
  "schema" "extend" "implements" "directive" "repeatable"
] @keyword

["(" ")" "[" "]" "{" "}"] @punctuation.bracket
[":" "|" "&" "..."] @punctuation.delimiter
["=" "!"] @operator
