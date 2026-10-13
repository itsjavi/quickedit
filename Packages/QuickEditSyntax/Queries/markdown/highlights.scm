; QuickEdit Markdown block highlights (replaces upstream: whole headings, list markers, quotes).
; Inline syntax comes from the markdown_inline injection; fenced code from the info string's language.

[
  (atx_heading)
  (setext_heading)
] @markup.heading

(block_quote) @markup.quote

[
  (indented_code_block)
  (fenced_code_block)
] @markup.raw

; Code with a language is colored by its grammar, not as raw text.
(fenced_code_block
  (info_string) @label
  (code_fence_content) @none)

(fenced_code_block_delimiter) @punctuation.delimiter

[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
  (task_list_marker_checked)
  (task_list_marker_unchecked)
] @markup.list

(thematic_break) @punctuation.delimiter

[
  (pipe_table_delimiter_row)
  "|"
] @punctuation.delimiter

(pipe_table_header (pipe_table_cell) @markup.strong)

(link_reference_definition
  (link_label) @markup.link
  (link_destination) @markup.link.url)
(link_title) @string

[
  (backslash_escape)
  (entity_reference)
  (numeric_character_reference)
] @string.escape

