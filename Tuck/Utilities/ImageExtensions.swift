import AppKit

// MARK: - CGImage

nonisolated extension CGImage {
    /// A context for handling transparency data in an image.
    private struct TransparencyContext: ~Copyable {
        private let image: CGImage
        private let maxAlpha: UInt8
        private let cgContext: CGContext
        private let zeroByteBlock: UnsafeMutableRawPointer
        private let rowRange: LazySequence<Range<Int>>
        private let columnRange: LazySequence<Range<Int>>

        /// Creates a context with the given image and alpha threshold.
        init?(image: CGImage, maxAlpha: UInt8) {
            guard
                let cgContext = CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                ),
                cgContext.data != nil,
                let zeroByteBlock = calloc(image.width, MemoryLayout<UInt8>.size)
            else {
                return nil
            }

            cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

            self.image = image
            self.maxAlpha = maxAlpha
            self.cgContext = cgContext
            self.zeroByteBlock = zeroByteBlock
            self.rowRange = (0..<image.height).lazy
            self.columnRange = (0..<image.width).lazy
        }

        deinit {
            free(zeroByteBlock)
        }

        /// Trims transparent pixels from the context.
        func trim(edges: Set<CGRectEdge>) -> CGImage? {
            guard maxAlpha < 255, !edges.isEmpty else {
                return image // Nothing to trim.
            }

            guard
                let minYInset = inset(for: .minYEdge, in: edges),
                let maxYInset = inset(for: .maxYEdge, in: edges),
                let minXInset = inset(for: .minXEdge, in: edges),
                let maxXInset = inset(for: .maxXEdge, in: edges)
            else {
                return nil
            }

            guard (minYInset, maxYInset, minXInset, maxXInset) != (0, 0, 0, 0) else {
                return image // Already trimmed.
            }

            let insetRect = CGRect(
                x: minXInset,
                y: maxYInset,
                width: image.width - (minXInset + maxXInset),
                height: image.height - (minYInset + maxYInset)
            )

            return image.cropping(to: insetRect)
        }

        private func inset(for edge: CGRectEdge, in edges: Set<CGRectEdge>) -> Int? {
            guard edges.contains(edge) else { return 0 }
            return switch edge {
            case .maxYEdge:
                firstOpaqueRow(in: rowRange)
            case .minYEdge:
                firstOpaqueRow(in: rowRange.reversed()).map { (image.height - 1) - $0 }
            case .minXEdge:
                firstOpaqueColumn(in: columnRange)
            case .maxXEdge:
                firstOpaqueColumn(in: columnRange.reversed()).map { (image.width - 1) - $0 }
            }
        }

        private func isPixelOpaque(row: Int, column: Int) -> Bool {
            guard let bitmapData = cgContext.data else { return false }
            let rawAlpha = bitmapData.load(fromByteOffset: (row * cgContext.bytesPerRow) + column, as: UInt8.self)
            return rawAlpha > maxAlpha
        }

        private func firstOpaqueRow<S: Sequence>(in rowRange: S) -> Int? where S.Element == Int {
            guard let bitmapData = cgContext.data else { return nil }
            return rowRange.first { row in
                // Use memcmp to efficiently check the entire row for zeroed out alpha.
                let rowByteBlock = bitmapData + (row * cgContext.bytesPerRow)
                if memcmp(rowByteBlock, zeroByteBlock, image.width) == 0 {
                    return false
                }
                // We found a non-zero row. Check each pixel until we find one that is opaque.
                return columnRange.contains { column in
                    isPixelOpaque(row: row, column: column)
                }
            }
        }

        private func firstOpaqueColumn<S: Sequence>(in columnRange: S) -> Int? where S.Element == Int {
            columnRange.first { column in
                rowRange.contains { row in
                    isPixelOpaque(row: row, column: column)
                }
            }
        }
    }

    /// Returns an image that has been trimmed of transparency around the given edges.
    ///
    /// - Parameters:
    ///   - edges: The edges to trim from around the image.
    ///   - maxAlpha: The maximum alpha value to consider transparent. Pixels with alpha
    ///     values above this value will be considered opaque, and will therefore remain
    ///     in the image.
    func trimmingTransparentPixels(
        around edges: Set<CGRectEdge> = [.minXEdge, .maxXEdge, .minYEdge, .maxYEdge],
        maxAlpha: UInt8 = 0
    ) -> CGImage? {
        let context = TransparencyContext(image: self, maxAlpha: maxAlpha)
        return context?.trim(edges: edges)
    }
}

// MARK: - NSImage

nonisolated extension NSImage {
    /// Returns a copy of the image, redrawn at the given size.
    func resized(to size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        return image
    }
}
