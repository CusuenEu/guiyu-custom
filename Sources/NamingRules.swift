import SwiftUI

enum SmartNamingFormat:String,Codable,CaseIterable,Identifiable {
    case nameOnly, month, monthDay, category
    var id:String { rawValue }
    var title:String {
        switch self { case .nameOnly: return "仅识别的名称"; case .month: return "月份 + 识别的名称"; case .monthDay: return "月日 + 识别的名称"; case .category: return "分类 + 识别的名称" }
    }
}
enum NamingDateSource:String,Codable,CaseIterable {
    case today, created
    var title:String { self == .today ? "命名当天" : "文件创建日期" }
}
struct NamingRuleSettings:Codable,Equatable {
    var folder:SmartNamingFormat = .nameOnly
    var document:SmartNamingFormat = .nameOnly
    var dateSource:NamingDateSource = .today
    init() {}
    private enum CodingKeys:String,CodingKey { case folder,document,dateSource }
    init(from decoder:Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        folder = try values.decodeIfPresent(SmartNamingFormat.self,forKey:.folder) ?? .nameOnly
        document = try values.decodeIfPresent(SmartNamingFormat.self,forKey:.document) ?? .nameOnly
        dateSource = try values.decodeIfPresent(NamingDateSource.self,forKey:.dateSource) ?? .today
    }
}
func namingCalendar() -> Calendar {
    var calendar = Calendar(identifier:.gregorian)
    calendar.timeZone = TimeZone(identifier:"Asia/Shanghai")!
    return calendar
}
@MainActor extension Store {
    var namingRuleSettings:NamingRuleSettings { settings.namingRules ?? NamingRuleSettings() }
    func namingFormat(for target:NamingTarget) -> SmartNamingFormat { target.folder ? namingRuleSettings.folder : namingRuleSettings.document }
    func smartNamingCategory(for target:NamingTarget,recognizedName:String? = nil) -> String {
        let url = URL(fileURLWithPath:target.path)
        var title = url.lastPathComponent
        if let recognizedName, !recognizedName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            // Match the current rules against both the source name and the extracted title.
            // Keep the source path for identity-checked manual assignments and entry scope.
            let originalStem = target.folder ? title : url.deletingPathExtension().lastPathComponent
            let recognizedStem = smartNamingLiteralStem(recognizedName,target:target)
            title = CategoryRule.unique([originalStem,recognizedStem]).joined(separator:" ")
            if !target.folder && !url.pathExtension.isEmpty { title += "."+url.pathExtension }
        }
        let row = BrowserRow(id:target.path,title:title,folder:target.folder)
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
        case .nameOnly: return ""
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
        titleProposedName(base,target:target,date:dateOverride ?? namingDate(for:target,now:now),month:monthOverride)
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
        case .nameOnly, .category:
            // The generated category is ordinary editable text, not an execution constraint.
            return !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
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
        case .nameOnly: prefix = ""
        case .month: prefix = "\(namingCalendar().component(.month,from:Date()))月"
        case .monthDay:
            let parts = namingCalendar().dateComponents([.month,.day],from:Date())
            prefix = String(format:"%02d%02d",parts.month ?? 1,parts.day ?? 1)
        case .category: prefix = "方案"
        }
        return (prefix.isEmpty ? "" : prefix+" ")+"智慧园区建设项目"+(folder ? "" : ".docx")
    }
    func block(_ folder:Bool) -> some View {
        VStack(alignment:.leading,spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                HStack {
                    Label(folder ? "文件夹命名" : "文档命名",systemImage:folder ? "folder" : "doc.text").font(.system(size:15,weight:.semibold)).foregroundStyle(WorkspaceTheme.ink)
                    Spacer()
                    Text("命名示例").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                Text(folder ? "首页标题优先，最多前两页；无分页 Word 只读开头节选，Excel 只读表头。" : "首页标题优先，最多前两页；无分页 Word 只读开头节选，Excel 识别横向、纵向表头。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
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
            Text("默认不加前缀，保留标题原意和原扩展名。多个标题可选择，找不到则保留原名；可手动修改，确认后才改名。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }.foregroundStyle(WorkspaceTheme.ink)
    }
}
