import AppKit

/// Draws an `OverlayPanel`'s tint, shadow, border, and shape. Reads live configuration and
/// menu bar layout state on every draw; holds no cached state of its own.
@MainActor
final class OverlayContentView: NSView {
    private var overlayPanel: OverlayPanel? { window as? OverlayPanel }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let appearance = overlayPanel.appState.appearance
        let fullConfiguration = appearance.configuration
        let configuration = appearance.previewConfiguration ?? fullConfiguration.current
        let screen = overlayPanel.owningScreen
        let insetAmount = appearance.menuBarInsetAmount
        let drawableBounds = drawableBounds

        let shapePath: NSBezierPath = switch fullConfiguration.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShape(
                in: drawableBounds,
                info: fullConfiguration.fullShapeInfo,
                isInset: fullConfiguration.isInset,
                insetAmount: insetAmount,
                screen: screen
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: fullConfiguration.splitShapeInfo,
                isInset: fullConfiguration.isInset,
                insetAmount: insetAmount,
                screen: screen,
                applicationMenuFrame: overlayPanel.applicationMenuFrame
            )
        }

        switch fullConfiguration.shapeKind {
        case .none:
            if configuration.hasShadow {
                let gradient = NSGradient(colors: [NSColor(white: 0, alpha: 0), NSColor(white: 0, alpha: 0.2)])
                let shadowBounds = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 5)
                gradient?.draw(in: shadowBounds, angle: 90)
            }

            drawTint(configuration, in: drawableBounds)

            if configuration.hasBorder {
                let borderBounds = CGRect(x: bounds.minX, y: bounds.minY + 5, width: bounds.width, height: CGFloat(configuration.borderWidth))
                configuration.borderColor.nsColor.setFill()
                NSBezierPath(rect: borderBounds).fill()
            }

        case .full, .split:
            if let desktopWallpaper = overlayPanel.desktopWallpaper {
                context.saveGraphicsState()
                let invertedClipPath = NSBezierPath(rect: drawableBounds)
                invertedClipPath.append(shapePath.reversed)
                invertedClipPath.setClip()
                context.cgContext.draw(desktopWallpaper, in: drawableBounds)
                context.restoreGraphicsState()
            }

            if configuration.hasShadow {
                context.saveGraphicsState()
                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()
                shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
                context.restoreGraphicsState()
            }

            context.saveGraphicsState()
            shapePath.setClip()
            drawTint(configuration, in: drawableBounds)
            context.restoreGraphicsState()

            if configuration.hasBorder {
                context.saveGraphicsState()
                // HACK: insetting a path to get an "inside" stroke is surprisingly
                // difficult. Doubling the line width fakes it, since anything outside the
                // shape path is clipped away.
                shapePath.lineWidth = CGFloat(configuration.borderWidth) * 2
                shapePath.setClip()
                configuration.borderColor.nsColor.setStroke()
                shapePath.stroke()
                context.restoreGraphicsState()
            }
        }
    }

    /// The area available for drawing, excluding the bottom 5pt reserved for the shadow.
    private var drawableBounds: CGRect {
        CGRect(x: bounds.minX, y: bounds.minY + 5, width: bounds.width, height: bounds.height - 5)
    }

    private func drawTint(_ configuration: PartialConfiguration, in rect: CGRect) {
        switch configuration.tintKind {
        case .none:
            break
        case .solid:
            configuration.tintColor.nsColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(rect: rect).fill()
        case .gradient:
            configuration.tintGradient.withAlphaComponent(0.2).nsGradient?.draw(in: rect, angle: 0)
        }
    }

    // MARK: - Shapes

    /// Builds a path in `rect` with the given end caps: a middle rect unioned with
    /// leading/trailing end-cap shapes, each a square of side equal to the rect's height.
    private func shapePath(in rect: CGRect, leadingEndCap: MenuBarEndCap, trailingEndCap: MenuBarEndCap, screen: NSScreen) -> NSBezierPath {
        // Purely cosmetic anti-aliasing correction; skipped on notched screens.
        let insetRect: CGRect
        if screen.hasNotch {
            insetRect = rect
        } else {
            insetRect = switch (leadingEndCap, trailingEndCap) {
            case (.square, .square):
                CGRect(x: rect.minX, y: rect.minY + 1, width: rect.width, height: rect.height - 2)
            case (.square, .round):
                CGRect(x: rect.minX, y: rect.minY + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .square):
                CGRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .round):
                CGRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: rect.height - 2)
            }
        }

        let shapeBounds = CGRect(
            x: insetRect.minX + insetRect.height / 2,
            y: insetRect.minY,
            width: insetRect.width - insetRect.height,
            height: insetRect.height
        )
        let leadingEndCapBounds = CGRect(x: insetRect.minX, y: insetRect.minY, width: insetRect.height, height: insetRect.height)
        let trailingEndCapBounds = CGRect(x: insetRect.maxX - insetRect.height, y: insetRect.minY, width: insetRect.height, height: insetRect.height)

        var path = NSBezierPath(rect: shapeBounds)
        path = switch leadingEndCap {
        case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
        }
        path = switch trailingEndCap {
        case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
        }
        return path
    }

    private func pathForFullShape(in rect: CGRect, info: FullShapeInfo, isInset: Bool, insetAmount: CGFloat, screen: NSScreen) -> NSBezierPath {
        var rect = rect
        if isInset && screen.hasNotch {
            rect = rect.insetBy(dx: 0, dy: insetAmount)
            if info.leadingEndCap == .round {
                rect.origin.x += insetAmount
                rect.size.width -= insetAmount
            }
            if info.trailingEndCap == .round {
                rect.size.width -= insetAmount
            }
        }
        return shapePath(in: rect, leadingEndCap: info.leadingEndCap, trailingEndCap: info.trailingEndCap, screen: screen)
    }

    private func pathForSplitShape(
        in rect: CGRect,
        info: SplitShapeInfo,
        isInset: Bool,
        insetAmount: CGFloat,
        screen: NSScreen,
        applicationMenuFrame: CGRect?
    ) -> NSBezierPath {
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: insetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += insetAmount
                rect.size.width -= insetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= insetAmount
            }
        }

        let leadingBounds = leadingPathBounds(in: rect, info: info, shouldInset: shouldInset, insetAmount: insetAmount, applicationMenuFrame: applicationMenuFrame)
        let trailingBounds = trailingPathBounds(in: rect, info: info, shouldInset: shouldInset, insetAmount: insetAmount, screen: screen)

        // Too little room between the two shapes (or one is empty): fall back to a single
        // unified shape rather than drawing an overlapping, garbled pair.
        guard leadingBounds != .zero, trailingBounds != .zero, !leadingBounds.intersects(trailingBounds) else {
            return shapePath(in: rect, leadingEndCap: info.leading.leadingEndCap, trailingEndCap: info.trailing.trailingEndCap, screen: screen)
        }

        let leadingPath = shapePath(in: leadingBounds, leadingEndCap: info.leading.leadingEndCap, trailingEndCap: info.leading.trailingEndCap, screen: screen)
        let trailingPath = shapePath(in: trailingBounds, leadingEndCap: info.trailing.leadingEndCap, trailingEndCap: info.trailing.trailingEndCap, screen: screen)
        let path = NSBezierPath()
        path.append(leadingPath)
        path.append(trailingPath)
        return path
    }

    private func leadingPathBounds(
        in rect: CGRect,
        info: SplitShapeInfo,
        shouldInset: Bool,
        insetAmount: CGFloat,
        applicationMenuFrame: CGRect?
    ) -> CGRect {
        guard var maxX = applicationMenuFrame?.width, maxX > 0 else { return .zero }
        if shouldInset {
            maxX += 10
            if info.leading.leadingEndCap == .square {
                maxX += insetAmount
            }
        } else {
            maxX += 20
        }
        return CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height)
    }

    private func trailingPathBounds(in rect: CGRect, info: SplitShapeInfo, shouldInset: Bool, insetAmount: CGFloat, screen: NSScreen) -> CGRect {
        let displayID = screen.displayID
        let displayBounds = CGDisplayBounds(displayID)
        // Items whose frame overflows past the display's right edge are mid-transition
        // (e.g. animating off-screen) and shouldn't count toward the trailing bounds.
        let items = MenuBarItem.all(on: displayID, onScreenOnly: true, activeSpaceOnly: true)
            .filter { $0.frame.maxX <= displayBounds.maxX }
        guard !items.isEmpty else { return .zero }

        let totalWidth = items.reduce(into: 0) { $0 += $1.frame.width }
        var position = rect.maxX - totalWidth
        if shouldInset {
            position += 4
            if info.trailing.trailingEndCap == .square {
                position -= insetAmount
            }
        } else {
            position -= 7
        }
        return CGRect(x: position, y: rect.minY, width: rect.maxX - position, height: rect.height)
    }
}

// MARK: - NSBezierPath Boolean Operations

nonisolated extension NSBezierPath {
    /// Draws a shadow in the shape of the path.
    func drawShadow(color: NSColor, radius: CGFloat) {
        guard let context = NSGraphicsContext.current, let path = copy() as? NSBezierPath else { return }

        let shadowBounds = bounds.insetBy(dx: -radius, dy: -radius)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = radius
        shadow.shadowColor = color

        context.saveGraphicsState()
        shadow.set()
        NSColor.black.set()
        shadowBounds.clip()
        path.fill()
        context.restoreGraphicsState()
    }

    /// Returns a new path filled with regions in either this path or the given path.
    func union(_ other: NSBezierPath, using windingRule: WindingRule = .evenOdd) -> NSBezierPath {
        let fillRule: CGPathFillRule = switch windingRule {
        case .nonZero: .winding
        case .evenOdd: .evenOdd
        @unknown default: .evenOdd
        }
        return NSBezierPath(cgPath: cgPath.union(other.cgPath, using: fillRule))
    }
}
