; QuickEdit highlights for GDScript (upstream ships no queries). Later patterns win for the same node.

(identifier) @variable
(name) @variable

((identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))

((identifier) @variable.builtin
  (#eq? @variable.builtin "self"))

; Declarations

(function_definition (name) @function)
(lambda (name) @function)
(constructor_definition "_init" @function)
(signal_statement (name) @function)
(class_name_statement (name) @type)
(class_definition (name) @type)
(enum_definition (name) @type)
(enumerator left: (identifier) @constant)
(const_statement (name) @constant)
(type) @type
(inferred_type) @operator

(parameters (identifier) @variable.parameter)
(typed_parameter (identifier) @variable.parameter)
(default_parameter (identifier) @variable.parameter)
(typed_default_parameter (identifier) @variable.parameter)

; Calls and members

(call (identifier) @function)
(base_call (identifier) @function)
(attribute (_) (identifier) @property)
(attribute_call (identifier) @function)
(attribute_subscript (identifier) @property)

(annotation "@" @attribute (identifier) @attribute)

; Literals

(comment) @comment
[(region_start) (region_end)] @comment
(string) @string
(string_name) @string
[(node_path) (get_node)] @string.special
(escape_sequence) @string.escape
[(integer) (float)] @number
[(true) (false) (null)] @constant.builtin

; Keywords

[
  "if" "elif" "else" "for" "while" "match" "when" "break" "continue" "pass" "return" "class" "class_name"
  "extends" "is" "as" "in" "and" "or" "not" "func" "signal" "enum" "const" "var" "await" "set" "get" "setget"
  "onready" "export" "remote" "master" "puppet" "remotesync" "mastersync" "puppetsync"
  (static_keyword) (remote_keyword) (pass_statement) (break_statement) (continue_statement)
  (breakpoint_statement)
] @keyword

; Operators and punctuation

[
  "+" "-" "*" "/" "%" "**" "==" "!=" "<" ">" "<=" ">=" "=" "+=" "-=" "*=" "/=" "%=" "**=" "&" "|" "^" "~"
  "<<" ">>" "&&" "||" "!" ":=" "->" "&=" "|=" "^=" "<<=" ">>="
] @operator

["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," "." ":" ";"] @punctuation.delimiter
