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
    }
}

// MARK: - Sheet Presentation

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
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .frame(width: 56, height: 56)
        }
        .modifier(GlassModifier())
    }
}

private struct GlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: .rect(cornerRadius: 28))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
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
    settingsBtn.setImage(UIImage(systemName: "gearshape.circle.fill"), for: .normal)
    settingsBtn.tintColor = UIColor(white: 0.7, alpha: 0.8)
    settingsBtn.contentVerticalAlignment = .fill
    settingsBtn.contentHorizontalAlignment = .fill
    settingsBtn.translatesAutoresizingMaskIntoConstraints = false
    settingsBtn.isHidden = true
    window.addSubview(settingsBtn)
    settingsButton = settingsBtn

    NSLayoutConstraint.activate([
        glassHost.view.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        glassHost.view.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        glassHost.view.widthAnchor.constraint(equalToConstant: 56),
        glassHost.view.heightAnchor.constraint(equalToConstant: 56),

        settingsBtn.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        settingsBtn.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
        settingsBtn.widthAnchor.constraint(equalToConstant: 36),
        settingsBtn.heightAnchor.constraint(equalToConstant: 36),
    ])
}

// ObjC target for button actions (global functions can't use #selector directly)
final class OverlayTarget: NSObject {
    static let shared = OverlayTarget()

    @objc func addTapped() {
        presentAddEvent()
    }

    @objc func settingsTapped() {
        CalendarManager.shared.shareCalendar { url in
            guard let url = url else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
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
