import SwiftUI

/// In-app language override. `.system` follows the device locale.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.tr(.followSystem)
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    /// Concrete language used for string lookup when `.system` is selected.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }
}

/// Observable language selection so SwiftUI views re-render on change.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    static let storageKey = "oayao.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        language = AppLanguage(rawValue: stored) ?? .system
    }
}

/// Localized string table.
enum L10n {
    enum Key {
        case settings, done, language, followSystem
        case calendar, name, shareWithPartner, calendarFooter
        case daysCounter, startDate, counterFooter
        case theme, themeFooter, customColors, customColorsFooter
        case themeMint, themePeach, themeCustom
        case colorBackground, colorHeartFill, colorHeartStroke, colorTimerText
        case howItWorks, guideStep1, guideStep2, guideStep3, guideStep4
        case openCalendarApp, calendarNotShareable, sharingUsesIcloud
        case calendarName, calendarNamePlaceholder, calendarNameFooter
        case changesApplyImmediately
        case cancel, newEvent, title, eventName, notesOptional, saveEvent
        case notes, location, event, close, deleteEvent, loading
        case date
        case heart, opacity, motion, motionBeat, motionBreath, positionY, reset
        case size
    }

    static func tr(_ key: Key) -> String {
        let entry = table[key] ?? (en: keyFallback, zh: keyFallback)
        return LanguageManager.shared.language.resolved == .chinese ? entry.zh : entry.en
    }

    /// String(format:) variant for strings with placeholders.
    static func tr(_ key: Key, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }

    private static let keyFallback = ""

    private static let table: [Key: (en: String, zh: String)] = [
        .settings: ("Settings", "设置"),
        .done: ("Done", "完成"),
        .language: ("Language", "语言"),
        .followSystem: ("Follow System", "跟随系统"),
        .calendar: ("Calendar", "日历"),
        .name: ("Name", "名称"),
        .shareWithPartner: ("Share with Partner", "共享给对方"),
        .calendarFooter: (
            "Events in this calendar appear as floating hearts. Share it with your partner to see each other's hearts.",
            "日历中的事件会以爱心的形式出现在画布上。共享后，可看到对方的爱心。"
        ),
        .daysCounter: ("Days Counter", "天数计数"),
        .startDate: ("Start Date", "开始日期"),
        .counterFooter: (
            "Recorded in the calendar so it syncs to your partner when shared.",
            "记录于日历中,共享后会同步给对方。"
        ),
        .theme: ("Theme", "主题"),
        .themeFooter: (
            "Canvas colors fade smoothly when switching themes.",
            "切换主题时,画布颜色会平滑渐变。"
        ),
        .customColors: ("Custom Colors", "自定义颜色"),
        .customColorsFooter: (
            "Changes fade in immediately on the canvas.",
            "修改会在画布上即时渐变生效。"
        ),
        .themeMint: ("Mint", "薄荷绿"),
        .themePeach: ("Peach", "蜜桃粉"),
        .themeCustom: ("Custom", "自定义"),
        .colorBackground: ("Background", "背景"),
        .colorHeartFill: ("Heart Fill", "爱心填充"),
        .colorHeartStroke: ("Heart Stroke", "爱心描边"),
        .colorTimerText: ("Timer Text", "计数文字"),
        .howItWorks: ("How It Works", "操作步骤"),
        .guideStep1: (
            "Tap \"Open Calendar App\" below to jump to this calendar. If you land on the calendar list, tap the info button next to \"%@\".",
            "点击下方「打开日历 App」跳转到该日历。若进入的是日历列表,点击「%@」旁的详情按钮。"
        ),
        .guideStep2: (
            "Tap \"Add Person\" under Shared With.",
            "在「共享对象」下点击「添加成员」。"
        ),
        .guideStep3: (
            "Enter your partner's Apple ID email and send the invitation.",
            "输入对方的 Apple ID 邮箱并发送邀请。"
        ),
        .guideStep4: (
            "Once they accept, their events appear as hearts on your canvas — and yours on theirs. They only need this app with the same calendar name (the default works).",
            "接受后,画布实时显示双方的爱心。"
        ),
        .openCalendarApp: ("Open Calendar App", "打开日历 App"),
        .calendarNotShareable: (
            "The current calendar is not iCloud-backed, so it can't be shared. Calendars created by this app use iCloud when it's available.",
            "当前日历不在 iCloud 上,无法共享。本应用创建的日历在 iCloud 可用时会使用 iCloud。"
        ),
        .sharingUsesIcloud: (
            "Sharing uses iCloud — no account or sign-up needed in this app.",
            "共享基于 iCloud,无需在本应用中注册账号。"
        ),
        .calendarName: ("Calendar Name", "日历名称"),
        .calendarNamePlaceholder: ("Calendar name", "日历名称"),
        .calendarNameFooter: (
            "If no calendar with this name exists, a new one is created.",
            "若不存在同名日历,将自动创建。"
        ),
        .changesApplyImmediately: ("Changes apply immediately.", "修改立即生效。"),
        .cancel: ("Cancel", "取消"),
        .newEvent: ("New Event", "新建事件"),
        .title: ("Title", "标题"),
        .eventName: ("Event name", "事件名称"),
        .notesOptional: ("Notes (optional)", "备注(可选)"),
        .saveEvent: ("Save Event", "保存事件"),
        .notes: ("Notes", "备注"),
        .location: ("Location", "位置"),
        .event: ("Event", "事件"),
        .close: ("Close", "关闭"),
        .deleteEvent: ("Delete Event", "删除事件"),
        .loading: ("Loading...", "加载中…"),
        .date: ("Date", "日期"),
        .heart: ("Big Heart", "爱心"),
        .opacity: ("Opacity", "透明度"),
        .motion: ("Motion", "运动模式"),
        .motionBeat: ("Beat", "跳动"),
        .motionBreath: ("Breath", "呼吸"),
        .positionY: ("Vertical Position", "垂直位置"),
        .reset: ("Reset", "重置"),
        .size: ("Size", "尺寸"),
    ]
}
