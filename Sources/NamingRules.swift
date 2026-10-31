import SwiftUI

enum SmartNamingFormat:String,Codable,CaseIterable,Identifiable {
    case month, monthDay, category
    var id:String { rawValue }
    var title:String {
        switch self { case .month: return "月份 + 识别的名称"; case .monthDay: return "月日 + 识别的名称"; case .category: return "分类 + 识别的名称" }
    }
}
enum NamingDateSource:String,Codable,CaseIterable {
    case today, created
    var title:String { self == .today ? "命名当天" : "文件创建日期" }
}
struct NamingRuleSettings:Codable,Equatable {
    var folder:SmartNamingFormat = .month
    var document:SmartNamingFormat = .category
    var dateSource:NamingDateSource = .today
}
func namingCalendar() -> Calendar {
    var calendar = Calendar(identifier:.gregorian)
    calendar.timeZone = TimeZone(identifier:"Asia/Shanghai")!
    return calendar
}
func smartRecognitionStem(_ value:String,target:NamingTarget,category:String) -> String {
    var text = value.trimmingCharacters(in:.whitespacesAndNewlines)
    let ext = URL(fileURLWithPath:target.path).pathExtension
    if !target.folder && !ext.isEmpty && text.hasSuffix("."+ext) { text = String(text.dropLast(ext.count+1)) }
    // Only remove explicit prefixes, never a bare number inside the recognized title.
    for _ in 0..<3 {
        let old = text
        text = text.replacingOccurrences(of:"^(?:1[0-2]|[1-9])月\\s+",with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:"^(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])[ _-]+",with:"",options:.regularExpression)
        for prefix in ["解决方案-","招标文件-","投标文件-",cleanName(category)+" "] where !prefix.trimmingCharacters(in:.whitespaces).isEmpty {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)); break }
        }
        if text == old { break }
    }
    return text.trimmingCharacters(in:.whitespacesAndNewlines)
}
@MainActor extension Store {
    var namingRuleSettings:NamingRuleSettings { settings.namingRules ?? NamingRuleSettings() }
    func namingFormat(for target:NamingTarget) -> SmartNamingFormat { target.folder ? namingRuleSettings.folder : namingRuleSettings.document }
    func smartNamingCategory(for target:NamingTarget) -> String {
        let row = BrowserRow(id:target.path,title:URL(fileURLWithPath:target.path).lastPathComponent,folder:target.folder)
        return resolvedCategory(row,categories:workspaceCategories,assignments:workspaceAssignments)?.name ?? "其他"
    }
    func namingDate(for target:NamingTarget,now:Date = Date()) -> Date {
        if namingRuleSettings.dateSource == .created {
            return (try? URL(fileURLWithPath:target.path).resourceValues(forKeys:[.creationDateKey]).creationDate) ?? now
        }
        return now
    }
    func namingMonth(for target:NamingTarget,date:Date) -> Int {
        if target.folder && namingRuleSettings.dateSource == .created { return suggestedMonth(target.path) }
        return namingCalendar().component(.month,from:date)
    }
    func smartNamingPrefix(for target:NamingTarget,date:Date,month:Int? = nil) -> String {
        switch namingFormat(for:target) {
        case .month: return "\(month ?? namingMonth(for:target,date:date))月"
        case .monthDay:
            let parts = namingCalendar().dateComponents([.month,.day],from:date)
            return String(format:"%02d%02d",parts.month ?? 1,parts.day ?? 1)
        case .category:
            let category = cleanName(smartNamingCategory(for:target))
            return category.isEmpty ? "其他" : category
        }
    }
    func smartProposedName(base:String,target:NamingTarget,now:Date = Date(),dateOverride:Date? = nil,monthOverride:Int? = nil) -> String {
        let stem = smartRecognitionStem(base,target:target,category:smartNamingCategory(for:target))
        guard !stem.isEmpty else { return "" }
        let prefix = smartNamingPrefix(for:target,date:dateOverride ?? namingDate(for:target,now:now),month:monthOverride)
        let name = prefix+" "+stem
        return target.folder ? name : proposedName(base:name,month:1,folder:false,original:target.path)
    }
    @discardableResult func saveNamingRuleSettings(_ value:NamingRuleSettings) -> Bool {
        var updated = settings;updated.namingRules = value
        do {
            try fm.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(updated).write(to:stateURL,options:.atomic)
            settings = updated;return true
        } catch { self.error = "命名规则未保存："+error.localizedDescription;return false }
    }
    func validateSmartFolderPrefix(_ name:String,target:NamingTarget) -> Bool {
        switch namingRuleSettings.folder {
        case .month: return name.range(of:"^(?:1[0-2]|[1-9])月\\s+.+$",options:.regularExpression) != nil
        case .monthDay:
            guard name.range(of:"^[0-9]{4}\\s+.+$",options:.regularExpression) != nil,
                  let month = Int(name.prefix(2)),let day = Int(name.dropFirst(2).prefix(2)) else { return false }
            let calendar = namingCalendar()
            guard let date = calendar.date(from:DateComponents(year:2000,month:month,day:day)) else { return false }
            return calendar.component(.month,from:date) == month && calendar.component(.day,from:date) == day
        case .category:
            let prefix = smartNamingPrefix(for:target,date:Date())+" "
            return name.hasPrefix(prefix) && !name.dropFirst(prefix.count).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        }
    }
}

struct NamingRulesSettingsView:View {
    @ObservedObject var store:Store
    private func binding(_ folder:Bool) -> Binding<SmartNamingFormat> {
        Binding(get:{folder ? store.namingRuleSettings.folder : store.namingRuleSettings.document},set:{ format in
            var rules = store.namingRuleSettings
            if folder { rules.folder = format } else { rules.document = format }
            _ = store.saveNamingRuleSettings(rules)
        })
    }
    private func example(_ format:SmartNamingFormat,folder:Bool) -> String {
        let prefix:String
        switch format {
        case .month: prefix = "\(namingCalendar().component(.month,from:Date()))月"
        case .monthDay:
            let parts = namingCalendar().dateComponents([.month,.day],from:Date())
            prefix = String(format:"%02d%02d",parts.month ?? 1,parts.day ?? 1)
        case .category: prefix = "方案"
        }
        return prefix+" 智慧园区建设项目"+(folder ? "" : ".docx")
    }
    func block(_ folder:Bool) -> some View {
        VStack(alignment:.leading,spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                HStack {
                    Label(folder ? "文件夹命名" : "文档命名",systemImage:folder ? "folder" : "doc.text").font(.system(size:15,weight:.semibold)).foregroundStyle(WorkspaceTheme.ink)
                    Spacer()
                    Text("命名示例").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                Text(folder ? "识别顺序：招标项目名 → 方案标题 → 单位＋关键方案名" : "优先识别文档自身项目名／标题，必要时参考同项目材料。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
            }
            VStack(spacing:3) {
                ForEach(SmartNamingFormat.allCases) { format in
                    let selected = binding(folder).wrappedValue == format
                    Button { binding(folder).wrappedValue = format } label: {
                        HStack(spacing:10) {
                            Image(systemName:selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? accent : WorkspaceTheme.secondary)
                            Text(format.title).font(.system(size:13,weight:selected ? .semibold : .regular))
                            Spacer(minLength:8)
                            Text(example(format,folder:folder)).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1).truncationMode(.middle)
                        }.padding(.horizontal,12).padding(.vertical,9).frame(maxWidth:.infinity,alignment:.leading)
                            .background(selected ? WorkspaceTheme.mint : WorkspaceTheme.projectCanvas,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            block(true)
            Divider()
            block(false)
            HStack {
                Text("日期取值").font(.system(size:12,weight:.medium))
                Picker("日期取值",selection:Binding(get:{store.namingRuleSettings.dateSource},set:{ value in
                    var rules = store.namingRuleSettings;rules.dateSource = value;_ = store.saveNamingRuleSettings(rules)
                })) { ForEach(NamingDateSource.allCases,id:\.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width:170)
                Spacer()
            }
            Text("两类命名独立设置。分类取当前文件分类，未匹配时使用“其他”；文档保留扩展名。仅在确认智能命名后改名。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }.foregroundStyle(WorkspaceTheme.ink)
    }
}
