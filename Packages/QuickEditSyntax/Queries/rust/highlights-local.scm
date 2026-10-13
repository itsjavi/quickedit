; QuickEdit: upstream's all-caps constant pattern has a stray quote and never matches.
((identifier) @constant
  (#match? @constant "^[A-Z][A-Z\\d_]+$"))

; Numbers are numbers, not builtin constants.
[(integer_literal) (float_literal)] @number
