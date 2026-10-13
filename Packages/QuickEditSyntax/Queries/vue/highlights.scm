; QuickEdit highlights for Vue single-file components (upstream ships no queries). Script, style and template
; expressions are injected (see injections.scm).

(tag_name) @tag
(erroneous_end_tag_name) @tag.error
(doctype) @constant
(attribute_name) @attribute
[(attribute_value) (quoted_attribute_value)] @string
(comment) @comment
(entity) @string.special

["<" ">" "</" "/>" "<!"] @punctuation.bracket

; v-if, v-for, :prop, @event, #slot
(directive_name) @keyword
(directive_attribute [":" "@" "#"] @keyword)
[(directive_value) (dynamic_directive_value)] @attribute
(directive_modifier) @attribute
(directive_modifiers "." @punctuation.delimiter)

(interpolation ["{{" "}}"] @punctuation.special)
