; QuickEdit: TypeScript's "^[A-Z]" type rule comes after JavaScript's all-caps constant rule; restore it.
([
  (identifier)
  (shorthand_property_identifier)
  (shorthand_property_identifier_pattern)
] @constant
  (#match? @constant "^[A-Z_][A-Z\\d_]+$"))
