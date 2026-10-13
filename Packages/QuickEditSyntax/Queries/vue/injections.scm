; QuickEdit Vue injections: <script lang="ts">, <style lang="scss">, template expressions.

((script_element
  (start_tag
    (attribute
      (attribute_name) @_lang
      (quoted_attribute_value (attribute_value) @injection.language)))
  (raw_text) @injection.content)
  (#eq? @_lang "lang"))

((script_element
  (start_tag) @_tag
  (raw_text) @injection.content)
  (#not-match? @_tag "lang=")
  (#set! injection.language "javascript"))

((style_element
  (start_tag
    (attribute
      (attribute_name) @_lang
      (quoted_attribute_value (attribute_value) @injection.language)))
  (raw_text) @injection.content)
  (#eq? @_lang "lang"))

((style_element
  (start_tag) @_tag
  (raw_text) @injection.content)
  (#not-match? @_tag "lang=")
  (#set! injection.language "css"))

((interpolation
  (raw_text) @injection.content)
  (#set! injection.language "javascript"))

((directive_attribute
  (quoted_attribute_value
    (attribute_value) @injection.content))
  (#set! injection.language "javascript"))
