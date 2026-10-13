; QuickEdit Svelte injections (replaces upstream, which relies on Neovim's html_tags inheritance and would
; inject JavaScript into <style>).

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

((svelte_raw_text) @injection.content
  (#set! injection.language "javascript"))
