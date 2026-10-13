import SwiftTreeSitter

/// Which syntax nodes fold, per grammar. Kept in Swift rather than as `folds.scm` queries: a tree walk that skips
/// single-line subtrees is several times faster than running a query over the whole tree, which matters for
/// folding a 10k-line file within a few milliseconds.
enum FoldRules {
    struct Rule: Sendable {
        let type: String
        /// The node's `field` child must be of type `fieldType` (YAML `key:` with a nested block).
        var field: (name: String, type: String)?
        /// The node's first named child must be one of these types (Markdown sections with a heading).
        var firstNamedChild: Set<String>?

        init(_ type: String, field: (name: String, type: String)? = nil, firstNamedChild: Set<String>? = nil) {
            self.type = type
            self.field = field
            self.firstNamedChild = firstNamedChild
        }

        func matches(_ node: Node) -> Bool {
            if let field {
                guard node.child(byFieldName: field.name)?.nodeType == field.type else { return false }
            }
            if let firstNamedChild {
                guard let type = node.namedChild(at: 0)?.nodeType, firstNamedChild.contains(type) else { return false }
            }
            return true
        }
    }

    private static func plain(_ types: String...) -> [Rule] {
        types.map { Rule($0) }
    }

    private static let javascript = plain(
        "statement_block", "class_body", "object", "array", "object_pattern", "array_pattern", "named_imports",
        "switch_body", "arguments", "formal_parameters", "parenthesized_expression", "template_string")
    private static let typescript = javascript + plain("object_type", "interface_body", "enum_body")

    private static let c = plain(
        "compound_statement", "field_declaration_list", "enumerator_list", "initializer_list", "argument_list",
        "parameter_list")

    static let rules: [String: [Rule]] = [
        "c": c,
        "glsl": c,
        "cpp": c + plain("declaration_list", "field_initializer_list"),
        "objc": c + plain(
            "class_interface", "class_implementation", "protocol_declaration", "array_literal", "dictionary_literal"),
        "c_sharp": plain(
            "block", "declaration_list", "accessor_list", "enum_member_declaration_list", "initializer_expression",
            "argument_list"),
        "java": plain(
            "block", "class_body", "interface_body", "enum_body", "annotation_type_body", "constructor_body",
            "switch_block", "array_initializer", "argument_list", "module_body"),
        "kotlin": plain(
            "class_body", "enum_class_body", "function_body", "lambda_literal", "when_expression", "collection_literal"),
        "php": plain(
            "compound_statement", "declaration_list", "enum_declaration_list", "array_creation_expression",
            "arguments", "match_block", "property_hook_list"),
        "ruby": plain(
            "method", "singleton_method", "class", "module", "singleton_class", "do_block", "block", "hash", "array",
            "if", "unless", "case", "while", "until", "for", "begin"),
        "lua": plain(
            "function_declaration", "function_definition", "do_statement", "while_statement", "if_statement",
            "for_statement", "repeat_statement", "table_constructor"),
        "scss": plain("block", "keyframe_block_list"),
        "sass": plain(
            "rule_set", "mixin_statement", "function_statement", "media_statement", "if_statement", "each_statement",
            "for_statement", "while_statement"),
        "vue": plain("element", "template_element", "script_element", "style_element"),
        "svelte": plain(
            "element", "script_element", "style_element", "if_statement", "each_statement", "await_statement",
            "key_statement", "snippet_statement"),
        "graphql": plain(
            "selection_set", "fields_definition", "arguments_definition", "enum_values_definition",
            "input_fields_definition", "object_value"),
        "proto": plain("message_body", "enum_body", "service"),
        "hcl": plain("block", "object", "tuple"),
        "terraform": plain("block", "object", "tuple"),
        "zig": plain(
            "block", "struct_declaration", "enum_declaration", "union_declaration", "switch_expression",
            "initializer_list", "anonymous_struct_initializer", "error_set_declaration"),
        "dart": plain("block", "class_body", "enum_body", "extension_body", "list_literal"),
        "powershell": plain(
            "statement_block", "script_block_expression", "hash_literal_expression", "class_statement",
            "enum_statement", "param_block", "array_expression"),
        "cmake": plain("function_def", "macro_def", "foreach_loop", "while_loop", "block_def", "if_condition"),
        "nix": plain(
            "attrset_expression", "rec_attrset_expression", "let_attrset_expression", "list_expression",
            "indented_string_expression"),
        "spicedb": plain("object_definition", "caveat_definition"),
        "json": plain("object", "array"),
        "css": plain("block", "keyframe_block_list"),
        "yaml": [
            Rule("block_mapping_pair", field: ("value", "block_node")),
            Rule("block_sequence_item", firstNamedChild: ["block_node"]),
            Rule("flow_mapping"),
            Rule("flow_sequence"),
        ],
        "toml": plain("table", "table_array_element", "inline_table", "array"),
        "javascript": javascript + plain("jsx_element"),
        "typescript": typescript,
        "tsx": typescript + plain("jsx_element"),
        "go": plain(
            "block", "literal_value", "field_declaration_list", "interface_type", "import_spec_list",
            "const_declaration", "var_declaration", "expression_switch_statement", "type_switch_statement",
            "select_statement", "argument_list", "parameter_list"),
        "rust": plain(
            "block", "declaration_list", "field_declaration_list", "enum_variant_list", "match_block", "use_list",
            "field_initializer_list", "arguments", "parameters", "array_expression", "token_tree"),
        "python": plain(
            "function_definition", "class_definition", "if_statement", "for_statement", "while_statement",
            "with_statement", "try_statement", "match_statement", "dictionary", "list", "set", "tuple",
            "argument_list", "parameters"),
        "swift": plain(
            "class_body", "protocol_body", "enum_class_body", "function_body", "computed_property", "lambda_literal",
            "array_literal", "dictionary_literal", "value_arguments", "switch_statement"),
        "markdown": [
            Rule("section", firstNamedChild: ["atx_heading", "setext_heading"]),
            Rule("fenced_code_block"),
        ],
        "html": plain("element", "script_element", "style_element"),
        "xml": plain("element"),
    ]

    /// A grammar's rules keyed by the symbols of their node types.
    static func symbols(for grammar: String, in language: SwiftTreeSitter.Language) -> [Int: [Rule]] {
        guard let rules = rules[grammar] else { return [:] }
        let byType = Dictionary(grouping: rules, by: \.type)
        var result: [Int: [Rule]] = [:]
        for symbol in 0..<language.symbolCount {
            if let name = language.symbolName(for: symbol), let rules = byType[name] {
                result[symbol] = rules
            }
        }
        return result
    }
}
