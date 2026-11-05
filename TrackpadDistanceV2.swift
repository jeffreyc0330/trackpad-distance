import AppKit

final class DistanceView: NSView {
    private var contacts: [NSTouch] = []

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func update(_ event: NSEvent) {
        let touches = Array(
            event.touches(matching: .touching, in: self)
        ).filter { $0.type == .indirect }

        contacts = []

        if let device = touches.first?.device as? NSObject {
            contacts = touches.filter {
                guard let other = $0.device as? NSObject else {
                    return false
                }
                return device.isEqual(other)
            }.sorted {
                if $0.normalizedPosition.x == $1.normalizedPosition.x {
                    return $0.normalizedPosition.y < $1.normalizedPosition.y
                }
                return $0.normalizedPosition.x < $1.normalizedPosition.x
            }
        }

        needsDisplay = true
    }

    override func touchesBegan(with event: NSEvent) {
        update(event)
    }

    override func touchesMoved(with event: NSEvent) {
        update(event)
    }

    override func touchesEnded(with event: NSEvent) {
        update(event)
    }

    override func touchesCancelled(with event: NSEvent) {
        clear()
    }

    func clear() {
        contacts = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NSApp.terminate(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        guard let firstTouch = contacts.first else { return }

        let size = firstTouch.deviceSize
        guard size.width > 0, size.height > 0 else { return }

        // Preserve the trackpad's proportions within the window.
        let available = bounds.insetBy(dx: 20, dy: 20)
        let scale = min(
            available.width / size.width,
            available.height / size.height
        )
        guard scale > 0 else { return }

        let surface = NSRect(
            x: bounds.midX - size.width * scale / 2,
            y: bounds.midY - size.height * scale / 2,
            width: size.width * scale,
            height: size.height * scale
        )

        let points = contacts.map { touch in
            NSPoint(
                x: surface.minX
                    + touch.normalizedPosition.x * surface.width,
                y: surface.minY
                    + touch.normalizedPosition.y * surface.height
            )
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: 13,
                weight: .regular
            ),
            .foregroundColor: NSColor.black
        ]

        func drawConnection(_ i: Int, _ j: Int) {
            let a = points[i]
            let b = points[j]

            let first = contacts[i].normalizedPosition
            let second = contacts[j].normalizedPosition

            // Use the reported device dimensions, not screen pixels.
            // Physical accuracy depends on the device's reported scale.
            let dx = (second.x - first.x) * size.width
            let dy = (second.y - first.y) * size.height
            let inches = hypot(dx, dy) / 72
            let centimetres = inches * 2.54

            NSColor.black.setStroke()

            let line = NSBezierPath()
            line.lineWidth = 0.75
            line.move(to: a)
            line.line(to: b)
            line.stroke()

            let text = String(
                format: "%.2f cm / %.2f in",
                centimetres,
                inches
            ) as NSString

            let textSize = text.size(withAttributes: attributes)
            let length = hypot(b.x - a.x, b.y - a.y)

            // Keep the distance label upright.
            var angle = atan2(b.y - a.y, b.x - a.x)
            if angle > .pi / 2 { angle -= .pi }
            if angle < -.pi / 2 { angle += .pi }

            NSGraphicsContext.saveGraphicsState()

            let transform = NSAffineTransform()
            transform.translateX(
                by: (a.x + b.x) / 2,
                yBy: (a.y + b.y) / 2
            )
            transform.rotate(byRadians: angle)
            transform.concat()

            // Move labels above short lines to expose the markers.
            let labelY: CGFloat = length > textSize.width + 32
                ? -textSize.height / 2
                : 14

            let labelRect = NSRect(
                x: -textSize.width / 2,
                y: labelY,
                width: textSize.width,
                height: textSize.height
            )

            NSColor.white.setFill()
            labelRect.insetBy(dx: -7, dy: -3).fill()
            text.draw(in: labelRect, withAttributes: attributes)

            NSGraphicsContext.restoreGraphicsState()
        }

        // Draw a distance between every unique pair of fingers.
        if contacts.count >= 2 {
            for i in 0..<(contacts.count - 1) {
                for j in (i + 1)..<contacts.count {
                    drawConnection(i, j)
                }
            }
        }

        // Draw small square outlines over the connecting lines.
        for point in points {
            let square = NSBezierPath(rect: NSRect(
                x: point.x - 4,
                y: point.y - 4,
                width: 8,
                height: 8
            ))

            NSColor.white.setFill()
            square.fill()

            NSColor.black.setStroke()
            square.lineWidth = 0.75
            square.stroke()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var distanceView: DistanceView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        distanceView = DistanceView(frame: NSRect(
            x: 0,
            y: 0,
            width: 960,
            height: 640
        ))

        window = NSWindow(
            contentRect: distanceView.frame,
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .white
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 320, height: 240)
        window.isReleasedWhenClosed = false

        for button: NSWindow.ButtonType in [
            .closeButton,
            .miniaturizeButton,
            .zoomButton
        ] {
            window.standardWindowButton(button)?.isHidden = true
        }

        window.contentView = distanceView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(distanceView)

        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        distanceView?.clear()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()

application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()