; QuickEdit Markdown inline highlights (replaces upstream: delimiters keep their span's style).

(code_span) @markup.raw
(emphasis) @markup.italic
(strong_emphasis) @markup.bold

[
  (link_text)
  (link_label)
  (image_description)
  (link_destination)
  (uri_autolink)
  (email_autolink)
] @markup.link

(link_title) @string

[
  (backslash_escape)
  (hard_line_break)
  (entity_reference)
  (numeric_character_reference)
] @string.escape

(image ["!" "[" "]" "(" ")"] @punctuation.delimiter)
(inline_link ["[" "]" "(" ")"] @punctuation.delimiter)
(shortcut_link ["[" "]"] @punctuation.delimiter)
(full_reference_link ["[" "]"] @punctuation.delimiter)
(collapsed_reference_link ["[" "]"] @punctuation.delimiter)
