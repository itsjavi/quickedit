; QuickEdit TOML highlights (replaces upstream, which colors keys in pairs as types).

(table (bare_key) @type)
(table (dotted_key (bare_key) @type))
(table (quoted_key) @type)
(table_array_element (bare_key) @type)
(table_array_element (dotted_key (bare_key) @type))
(table_array_element (quoted_key) @type)

(pair (bare_key) @property)
(pair (quoted_key) @property)
(pair (dotted_key (bare_key) @property))
(pair (dotted_key (quoted_key) @property))

(comment) @comment
(string) @string
(escape_sequence) @string.escape
[(integer) (float)] @number
(boolean) @boolean
[
  (offset_date_time)
  (local_date_time)
  (local_date)
  (local_time)
] @string.special

["." ","] @punctuation.delimiter
"=" @operator
["[" "]" "[[" "]]" "{" "}"] @punctuation.bracket
