; QuickEdit: custom properties stay variables (upstream orders for "first match wins"); "#" is part of a color.
((property_name) @variable
  (#match? @variable "^--"))
((plain_value) @variable
  (#match? @variable "^--"))
(color_value "#" @string.special)
