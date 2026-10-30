import Foundation

extension ConfigSchema {
    /// A setting of the schema, spelled generally: the position of an entry of a list of tables and the id of a table per id are `*`
    /// (`general.terminal`, `preset.*.prompt`, `agent.*.variant.*.arguments`).
    public struct Leaf: Sendable, Equatable {
        public var key: String
        public var node: SchemaNode
    }

    /// Every setting the schema describes that holds a value, in the order the schema lists them.
    public static var leaves: [Leaf] {
        func walk(_ nodes: [SchemaNode], prefix: String) -> [Leaf] {
            nodes.flatMap { node -> [Leaf] in
                switch node.kind {
                case .table: return walk(node.children, prefix: prefix + node.key + ".")
                case .tableArray, .tableMap: return walk(node.children, prefix: prefix + node.key + ".*.")
                case .string, .integer, .boolean, .stringArray: return [Leaf(key: prefix + node.key, node: node)]
                }
            }
        }
        return walk(root, prefix: "")
    }

    /// The general spelling of a path as the config names it (`preset.2.prompt` is `preset.*.prompt`, `agent.claude.args` is `agent.*.args`); `nil` for a path that is no setting.
    public static func genericKey(of path: String) -> String? {
        guard let segments = try? ConfigDocument.segments(path) else { return nil }
        var level = root
        var out: [String] = []
        var index = 0
        while index < segments.count {
            guard let node = level.first(where: { $0.key == segments[index] }) else { return nil }
            out.append(node.key)
            index += 1
            if node.kind == .tableMap || node.kind == .tableArray, index < segments.count {
                if node.kind == .tableArray, Int(segments[index]) == nil { return nil }
                out.append("*")
                index += 1
            }
            level = node.children
        }
        return out.joined(separator: ".")
    }
}
