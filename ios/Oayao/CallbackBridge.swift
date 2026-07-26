import UIKit
import SwiftUI

// MARK: - C Callback (called from Zig on heart tap)

let heartTapCallback: oayao_heart_tap_callback_t = { eventIdPtr in
    guard let ptr = eventIdPtr else { return }
    let eventId = String(cString: ptr)
    DispatchQueue.main.async {
        presentEventDetail(eventId: eventId)
    }
}

let counterTapCallback: oayao_counter_tap_callback_t = {
    // Defer the sheet so the tap's particle burst plays out first: presenting
    // immediately would stall the render loop and then cover the burst.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        presentSettings()
    }
}

let daysTapCallback: oayao_days_tap_callback_t = {
    // Immediate tactile feedback: the glyph pulse is subtle and the sheet is
    // deferred, so a light impact confirms the tap landed.
    DispatchQueue.main.async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    // Same deferral as the counter hearts: let the burst play out first.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        presentSettings()
    }
}

// MARK: - Bootstrap (global, called from Zig init)

@_cdecl("oayao_swift_bootstrap")
func oayao_swift_bootstrap() {
    DispatchQueue.main.async {
        oayao_set_heart_tap_callback(heartTapCallback)
        oayao_set_counter_tap_callback(counterTapCallback)
        oayao_set_days_tap_callback(daysTapCallback)

        let customColors = SettingsStore.customThemeColors
        for (role, key) in [(0, "background"), (1, "heartFill"), (2, "heartStroke"), (3, "timerText")] {
            let packed = customColors[key] ?? 0xFFFFFF
            oayao_set_custom_theme_color(
                UInt32(role),
                UInt8((packed >> 16) & 0xFF),
                UInt8((packed >> 8) & 0xFF),
                UInt8(packed & 0xFF)
            )
        }
        oayao_transition_to_theme(SettingsStore.themeId)

        oayao_set_heart_opacity(Float(SettingsStore.heartOpacity))
        oayao_set_heart_motion(UInt32(SettingsStore.heartMotion))
        oayao_set_heart_size_scale(Float(SettingsStore.heartSizeScale))
        oayao_set_sky_mode(UInt32(SettingsStore.skyMode))
        if let heartY = SettingsStore.heartY {
            oayao_set_heart_y(Float(heartY))
        }

        CalendarManager.shared.requestAccess { granted in
            if granted {
                print("[Oayao] Calendar access granted")
            } else {
                print("[Oayao] Calendar access denied")
            }
        }

        addOverlayButtons()
        addCounterHeartsAccessElement()
        #if DEBUG
        addStressPanel()
        #endif

        // Pre-warm SwiftUI view caches after the initial Metal render completes.
        // NavigationView + Form create UIKit backing views (UINavigationController,
        // UITableView) whose first-time construction is expensive enough to stall
        // the CADisplayLink-driven render loop. Forcing a layout pass now populates
        // internal caches so the real presentation is fast.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            prewarmSheetViews()
            prewarmKeyboard()
        }
    }
}

/// The first real keyboard pop in a process loads QuickType/UIInputSetHost
/// lazily (a 200–500ms stall on the keyboard's opening frames). Cycling a
/// hidden field once at launch pays that cost while the app is idle; the
/// same-runloop resign cancels the keyboard before it animates in.
private func prewarmKeyboard() {
    guard let window = keyWindow() else { return }
    let field = UITextField(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
    field.isHidden = true
    window.addSubview(field)
    field.becomeFirstResponder()
    field.resignFirstResponder()
    field.removeFromSuperview()
}

// MARK: - Sheet Presentation

/// Forces SwiftUI to build and layout backing UIKit views so that the first
/// real sheet presentation doesn't stall the CADisplayLink-driven render loop.
private func prewarmSheetViews() {
    let settingsVC = UIHostingController(rootView: SettingsSheet())
    settingsVC.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
    settingsVC.view.layoutIfNeeded()
}

private func presentEventDetail(eventId: String) {
    guard let rootVC = rootViewController() else { return }
    let sheet = UIHostingController(
        rootView: EventDetailSheet(eventId: eventId)
    )
    if let sheet = sheet.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
    }
    rootVC.present(sheet, animated: true)
}

/// Denied access can't be re-prompted by iOS; the only fix is the system's
/// Settings page, so the alert routes there instead of failing silently.
private func presentCalendarAccessAlert() {
    guard let rootVC = rootViewController() else { return }
    let alert = UIAlertController(
        title: L10n.tr(.calendarAccessTitle),
        message: L10n.tr(.calendarAccessMessage),
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: L10n.tr(.cancel), style: .cancel))
    alert.addAction(UIAlertAction(title: L10n.tr(.openSettings), style: .default) { _ in
        CalendarManager.openSystemSettings()
    })
    rootVC.present(alert, animated: true)
}

/// Settings sheet host, created once and reused: rebuilding the
/// Form/NavigationView tree on every open was a visible stall on the
/// canvas render loop.
private var settingsHost: UIHostingController<SettingsSheet>?

private func presentSettings() {
    DispatchQueue.main.async {
        guard let rootVC = rootViewController() else { return }
        if settingsHost == nil {
            settingsHost = UIHostingController(rootView: SettingsSheet())
        }
        guard let sheet = settingsHost else { return }
        if let spc = sheet.sheetPresentationController {
            spc.detents = [.medium(), .large()]
            spc.prefersGrabberVisible = true
        }
        rootVC.present(sheet, animated: true)
    }
}

/// Publishes keyboard height for the quick-add overlay: window-level
/// overlays get no automatic keyboard avoidance, so the capsule's bottom
/// padding tracks the keyboard frame. `keyboardWillChangeFrame` covers
/// both show and hide (the hide end frame sits below the window, clamping
/// the overlap to zero).
private final class QuickAddKeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    @Published private(set) var duration: Double = 0.25

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func frameWillChange(_ note: Notification) {
        guard let window = keyWindow(),
              let info = note.userInfo,
              let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        height = max(0, window.bounds.maxY - endFrame.minY - window.safeAreaInsets.bottom)
    }
}

/// Shared editing state for the quick-add overlay. UIKit swaps hosts off
/// this publisher: a small static host for the corner circle, and a
/// full-screen editor host added only while editing (so canvas taps pass
/// untouched the rest of the time, and nothing ever resizes on screen).
private final class QuickAddState: ObservableObject {
    @Published var editing = false {
        didSet { onEditingChanged?(editing) }
    }
    var onEditingChanged: ((Bool) -> Void)?
}

// MARK: - Overlay Buttons

/// The collapsed quick-add affordance: a glass circle fixed at the
/// bottom-right corner. No animation — adding is frequent, a morph every
/// time would just be in the way.
private struct QuickAddButtonView: View {
    @ObservedObject var state: QuickAddState

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    state.editing = true
                } label: {
                    Image("AddIcon")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .frame(width: 56, height: 56)
                        .modifier(GlassModifier(cornerRadius: 28))
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(16)
    }
}

/// The editing overlay: tap-anywhere-to-cancel shim plus a full-width
/// input capsule pinned above the keyboard. Title only, no sheet; saving
/// flows through the same CalendarManager.addEvent path, so the canvas
/// heart fly-in remains the confirmation.
private struct QuickAddEditorView: View {
    @ObservedObject var state: QuickAddState
    @StateObject private var keyboard = QuickAddKeyboardObserver()
    @State private var title = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { collapse() }
            VStack {
                Spacer()
                TextField(L10n.tr(.eventName), text: $title)
                    .focused($fieldFocused)
                    // Glass sits over the theme background; use the theme's
                    // WCAG-AA readable text color instead of stark white.
                    .foregroundColor(CanvasTheme(storedId: UInt32(SettingsStore.themeId)).readableTextColor)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .modifier(GlassModifier(cornerRadius: 28))
                    // Keyboard dismissal (swipe-down) reads as cancel too.
                    .onChange(of: fieldFocused) { focused in
                        if !focused && state.editing { collapse() }
                    }
            }
            .padding(16)
            .padding(.bottom, keyboard.height)
        }
        .animation(.easeOut(duration: keyboard.duration), value: keyboard.height)
        // Focus follows the editing flag, not appearance: the host is
        // created hidden at launch, and a hidden host must never summon
        // the keyboard.
        .onChange(of: state.editing) { editing in
            if editing {
                if let draft = quickAddDraft {
                    title = draft
                    quickAddDraft = nil
                }
                fieldFocused = true
            }
        }
    }

    private func collapse() {
        fieldFocused = false
        state.editing = false
        title = ""
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        guard CalendarManager.shared.hasAccess else {
            presentCalendarAccessAlert()
            return
        }
        let eventTitle = trimmed
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        collapse()
        CalendarManager.shared.addEvent(title: eventTitle, startDate: Date(), notes: nil) { ok in
            if !ok {
                // Save failed after all: reopen with the draft restored.
                quickAddDraft = eventTitle
                state.editing = true
            }
        }
    }
}

/// Draft carry-over for a failed save: the editor view is destroyed on
/// collapse, so the title can't live in its @State across a reopen.
private var quickAddDraft: String?

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct GlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect()
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}

#if DEBUG
/// Floating stress-test panel over the canvas (debug builds only): the
/// effect of every action is visible live without leaving the canvas.
/// The hosting view uses a fixed frame — SwiftUI hit-testing is
/// content-aware, so empty areas fall through to the canvas while the
/// buttons always stay in bounds.
private struct StressPanel: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var expanded = false
    @State private var status: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                Image("DebugIcon")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: 44, height: 44)
                    // .modifier(GlassModifier(cornerRadius: 22))
            }
            // .buttonStyle(ScaleButtonStyle())

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    StressButton(title: "生成 2000 心") {
                        calendarManager.stressSpawn(count: 2000)
                        status = "已推送 2000，观察分批淡入"
                    }
                    StressButton(title: "清除压测心") {
                        calendarManager.stressClearRenderer(count: 2000)
                        status = "已清除"
                    }
                    StressButton(title: "写入日历 2000") {
                        status = "写入中…"
                        calendarManager.stressSeedCalendar(count: 2000) { saved in
                            status = "已写入 \(saved) 条，杀进程冷启动验证"
                        }
                    }
                    StressButton(title: "清除日历压测") {
                        status = "清除中…"
                        calendarManager.stressClearCalendar { removed in
                            status = "已删除 \(removed) 条"
                        }
                    }
                    if let status {
                        Text(status)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// Full-width row button with an explicit hit shape, so taps anywhere on
/// the row register — the default borderless hit area is label-only.
private struct StressButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

private func addStressPanel() {
    guard let window = keyWindow() else { return }

    let host = UIHostingController(rootView: StressPanel())
    host.view.backgroundColor = .clear
    host.view.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(host.view)

    NSLayoutConstraint.activate([
        host.view.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        host.view.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 16),
        host.view.widthAnchor.constraint(equalToConstant: 200),
        host.view.heightAnchor.constraint(equalToConstant: 300),
    ])
}
#endif

private func addOverlayButtons() {
    guard let window = keyWindow() else { return }

    let state = QuickAddState()

    // Collapsed circle: a small static box at the corner. It never moves
    // and never resizes — the editor is a separate host, so there is no
    // layout flip to flash or fly across the screen.
    let buttonHost = UIHostingController(rootView: QuickAddButtonView(state: state))
    buttonHost.view.backgroundColor = .clear
    buttonHost.view.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(buttonHost.view)
    NSLayoutConstraint.activate([
        buttonHost.view.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor),
        buttonHost.view.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor),
        buttonHost.view.widthAnchor.constraint(equalToConstant: 88),
        buttonHost.view.heightAnchor.constraint(equalToConstant: 88),
    ])

    // The editor host is built up front and kept hidden: tapping the
    // circle only flips isHidden, so no view-tree construction or first
    // layout lands on the keyboard's opening frames. Hidden views don't
    // hit-test, so canvas taps stay free while collapsed.
    let editorHost = UIHostingController(rootView: QuickAddEditorView(state: state))
    editorHost.view.backgroundColor = .clear
    editorHost.view.isHidden = true
    editorHost.view.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(editorHost.view)
    NSLayoutConstraint.activate([
        editorHost.view.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor),
        editorHost.view.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor),
        editorHost.view.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor),
        editorHost.view.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor),
    ])

    state.onEditingChanged = { isEditing in
        buttonHost.view.isHidden = isEditing
        editorHost.view.isHidden = !isEditing
    }
}

// MARK: - Accessibility

/// VoiceOver-only settings entry over the counter hearts. The Metal canvas
/// is invisible to the accessibility tree, so the double-heart tap target
/// needs a native proxy; its frame is queried live from the renderer
/// because the hearts float and pulse.
private final class CounterHeartsAccessElement: UIAccessibilityElement {
    override var accessibilityFrameInContainerSpace: CGRect {
        get {
            let f = oayao_counter_hearts_frame()
            return CGRect(x: CGFloat(f.x), y: CGFloat(f.y), width: CGFloat(f.w), height: CGFloat(f.h))
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        presentSettings()
        return true
    }
}

private func addCounterHeartsAccessElement() {
    guard let window = keyWindow() else { return }
    let container = UIView(frame: window.bounds)
    container.isUserInteractionEnabled = false
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(container)

    let element = CounterHeartsAccessElement(accessibilityContainer: container)
    element.accessibilityLabel = L10n.tr(.settings)
    element.accessibilityTraits = .button
    container.accessibilityElements = [element]
}

// MARK: - Helpers

private func rootViewController() -> UIViewController? {
    return keyWindow()?.rootViewController
}

private func keyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })
}
