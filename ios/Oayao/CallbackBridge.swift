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

// MARK: - Bootstrap (global, called from Zig init)

@_cdecl("oayao_swift_bootstrap")
func oayao_swift_bootstrap() {
    DispatchQueue.main.async {
        oayao_set_heart_tap_callback(heartTapCallback)

        CalendarManager.shared.requestAccess { granted in
            if granted {
                print("[Oayao] Calendar access granted")
            } else {
                print("[Oayao] Calendar access denied")
            }
        }

        addOverlayButtons()

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

private var addButton: UIButton?
private var settingsButton: UIButton?

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
                .modifier(GlassModifier())
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
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect()
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(.white.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}

private func addOverlayButtons() {
    guard let window = keyWindow() else { return }

    let glassHost = UIHostingController(rootView: GlassAddButton {
        presentAddEvent()
    })
    glassHost.view.backgroundColor = .clear
    glassHost.view.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(glassHost.view)

    let settingsBtn = UIButton(type: .system)
    settingsBtn.setImage(UIImage(named: "SettingsIcon"), for: .normal)
    settingsBtn.tintColor = .white
    settingsBtn.translatesAutoresizingMaskIntoConstraints = false
    settingsBtn.addTarget(OverlayTarget.shared, action: #selector(OverlayTarget.settingsTapped), for: .touchUpInside)
    window.addSubview(settingsBtn)
    settingsButton = settingsBtn

    NSLayoutConstraint.activate([
        glassHost.view.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        glassHost.view.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        glassHost.view.widthAnchor.constraint(equalToConstant: 56),
        glassHost.view.heightAnchor.constraint(equalToConstant: 56),

        settingsBtn.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 8),
        settingsBtn.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 4),
        settingsBtn.widthAnchor.constraint(equalToConstant: 44),
        settingsBtn.heightAnchor.constraint(equalToConstant: 44),
    ])
}

// ObjC target for button actions (global functions can't use #selector directly)
final class OverlayTarget: NSObject {
    static let shared = OverlayTarget()

    @objc func settingsTapped() {
        presentSettings()
    }
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
