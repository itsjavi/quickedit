; QuickEdit adjustments: attribute names as attributes (as in HTML), quotes as part of values, CDATA as raw text.
(Attribute (Name) @attribute)
(AttValue ["\"" "'"] @string)
(PseudoAttValue ["\"" "'"] @string)
(CDSect
  (CDStart) @punctuation.delimiter
  (CData) @markup.raw
  "]]>" @punctuation.delimiter)
