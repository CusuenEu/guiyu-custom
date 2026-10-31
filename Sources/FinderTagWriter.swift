import Foundation

/// 写入 Finder 七色标签（com.apple.metadata:_kMDItemUserTags）。
/// 标签格式：二进制 plist 字符串数组，元素为 "分类名\n颜色码"（1灰 2绿 3紫 4蓝 5黄 6红 7橙）。
/// 只在分类名命中七色映射时写入；写入失败静默（标签是增强，不阻断归档/改名）。
enum FinderTagWriter {

    static let colorCodes: [String: Int] = [
        "收件箱": 5, "个人": 7, "工作": 6, "学习": 2, "项目": 4, "媒体": 3, "系统": 1,
    ]

    /// 按文件名匹配工作区分类（排除词优先；关键词或扩展主任一命中；同命中取优先级高者）。
    /// 手动归类优先：identity 有值且命中手动归档表时直接返回该分类名。
    static func match(name: String, isFolder: Bool, categories: [WorkspaceCategory], assignments: [String: CategoryAssignment] = [:], identity: String? = nil) -> String? {
        if let identity = identity, let assignment = assignments.values.first(where: { $0.identity == identity }),
           let category = categories.first(where: { $0.id == assignment.categoryID }) {
            return category.name
        }
        let lower = name.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        var best: (name: String, priority: Int)? = nil
        for category in categories {
            let rule = category.effectiveRule
            guard rule.enabled else { continue }
            if rule.scope == .files && isFolder { continue }
            if rule.scope == .folders && !isFolder { continue }
            if rule.excludedKeywords.map({ $0.lowercased() }).contains(where: { lower.contains($0) }) { continue }
            let keywordHit = rule.keywords.map({ $0.lowercased() }).contains(where: { lower.contains($0) })
            let extHit = !ext.isEmpty && rule.extensions.map({ $0.lowercased() }).contains(ext)
            guard keywordHit || extHit else { continue }
            if best == nil || rule.priority > best!.priority {
                best = (category.name, rule.priority)
            }
        }
        return best?.name
    }

    /// 给文件/文件夹写七色标签。分类名不在七色映射内则跳过。
    static func writeTag(at path: String, label: String?) {
        guard let label = label, let code = colorCodes[label] else { return }
        let payload = ["\(label)\n\(code)"]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0) else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = setxattr(path, "com.apple.metadata:_kMDItemUserTags", base, buffer.count, 0, 0)
        }
    }
}
