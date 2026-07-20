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

// MARK: - Bootstrap (global, called from Zig init)

@_cdecl("oayao_swift_bootstrap")
func oayao_swift_bootstrap() {
    DispatchQueue.main.async {
        oayao_set_heart_tap_callback(heartTapCallback)
        oayao_set_counter_tap_callback(counterTapCallback)

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
        oayao_set_nebula_enabled(SettingsStore.nebulaEnabled ? 1 : 0)
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

        // Pre-warm SwiftUI view caches after the initial Metal render completes.
        // NavigationView + Form create UIKit backing views (UINavigationController,
        // UITableView) whose first-time construction is expensive enough to stall
        // the CADisplayLink-driven render loop. Forcing a layout pass now populates
        // internal caches so the real presentation is fast.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            prewarmSheetViews()
        }
    }
}

// MARK: - Sheet Presentation

/// Forces SwiftUI to build and layout backing UIKit views so that the first
/// real sheet presentation doesn't stall the CADisplayLink-driven render loop.
private func prewarmSheetViews() {
    let addVC = UIHostingController(rootView: AddEventSheet())
    addVC.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
    addVC.view.layoutIfNeeded()

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

private func presentAddEvent() {
    // Defer to next runloop iteration so the CADisplayLink-driven
    // Metal render loop can finish its current frame before UIKit
    // presentation work blocks the main thread.
    DispatchQueue.main.async {
        guard CalendarManager.shared.hasAccess else {
            presentCalendarAccessAlert()
            return
        }
        guard let rootVC = rootViewController() else { return }
        let sheet = UIHostingController(
            rootView: AddEventSheet()
        )
        if let sheet = sheet.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        rootVC.present(sheet, animated: true)
    }
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

private func presentSettings() {
    DispatchQueue.main.async {
        guard let rootVC = rootViewController() else { return }
        let sheet = UIHostingController(
            rootView: SettingsSheet()
        )
        if let sheet = sheet.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        rootVC.present(sheet, animated: true)
    }
}

// MARK: - Overlay Buttons

// SwiftUI glass add button for iOS 26+, fallback for older versions
private struct GlassAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .frame(width: 56, height: 56)
                .modifier(GlassModifier(cornerRadius: 28))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

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

// Settings opens by tapping the floating hearts beside the day counter;
// only the add-event button floats over the canvas.
private struct OverlayButtons: View {
    var body: some View {
        GlassAddButton {
            presentAddEvent()
        }
    }
}

private func addOverlayButtons() {
    guard let window = keyWindow() else { return }

    let host = UIHostingController(rootView: OverlayButtons())
    host.view.backgroundColor = .clear
    host.view.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(host.view)

    NSLayoutConstraint.activate([
        host.view.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        host.view.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -16),
    ])
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
