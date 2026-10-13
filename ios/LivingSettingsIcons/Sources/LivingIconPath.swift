import Foundation
import CoreGraphics

// SVG path data → CGPath, for the icon artwork (prototype/assets/icons/*.svg and the part geometry of
// prototype/src/settings/living-icons.js). All commands of SVG 1.1 §8.3 (M L H V C S Q T A Z, absolute
// and relative, implicit repeats); arcs become cubic Béziers (≤ 90° each, SVG 1.1 F.6.5-F.6.6).
// `subpaths` splits the data at every moveto like the prototype's `splitSubpaths` (a piece per
// `M`/`m`), but each piece keeps the absolute position the full path gives it.

public enum LivingIconPath {
    /// The whole path.
    public static func path(_ d: String) -> CGPath {
        let path = CGMutablePath()
        for subpath in self.subpaths(d) {
            path.addPath(subpath)
        }
        return path
    }

    /// One path per moveto, in order (a lone moveto gives an empty path, as it draws nothing).
    public static func subpaths(_ d: String) -> [CGPath] {
        var parser = Parser(Array(d.utf8))
        return parser.parse()
    }

    /// The path of an SVG `<circle>`.
    public static func circle(cx: Double, cy: Double, r: Double) -> CGPath {
        return CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2.0 * r, height: 2.0 * r), transform: nil)
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        private static func isCommand(_ c: UInt8) -> Bool {
            switch c {
            case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"), UInt8(ascii: "H"), UInt8(ascii: "h"),
                 UInt8(ascii: "V"), UInt8(ascii: "v"), UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
                 UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"), UInt8(ascii: "A"), UInt8(ascii: "a"),
                 UInt8(ascii: "Z"), UInt8(ascii: "z"):
                return true
            default:
                return false
            }
        }

        private mutating func skipSeparators() {
            while self.index < self.bytes.count {
                let c = self.bytes[self.index]
                if c == UInt8(ascii: " ") || c == UInt8(ascii: ",") || c == UInt8(ascii: "\n") || c == UInt8(ascii: "\t") || c == UInt8(ascii: "\r") {
                    self.index += 1
                } else {
                    break
                }
            }
        }

        /// Whether a number follows (after separators).
        private mutating func hasNumber() -> Bool {
            self.skipSeparators()
            guard self.index < self.bytes.count else {
                return false
            }
            let c = self.bytes[self.index]
            return (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
        }

        private mutating func number() -> Double {
            self.skipSeparators()
            let start = self.index
            if self.index < self.bytes.count, self.bytes[self.index] == UInt8(ascii: "-") || self.bytes[self.index] == UInt8(ascii: "+") {
                self.index += 1
            }
            var seenDot = false
            while self.index < self.bytes.count {
                let c = self.bytes[self.index]
                if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") {
                    self.index += 1
                } else if c == UInt8(ascii: ".") && !seenDot {
                    seenDot = true
                    self.index += 1
                } else {
                    break
                }
            }
            if self.index < self.bytes.count, self.bytes[self.index] == UInt8(ascii: "e") || self.bytes[self.index] == UInt8(ascii: "E") {
                var j = self.index + 1
                if j < self.bytes.count, self.bytes[j] == UInt8(ascii: "-") || self.bytes[j] == UInt8(ascii: "+") {
                    j += 1
                }
                if j < self.bytes.count, self.bytes[j] >= UInt8(ascii: "0") && self.bytes[j] <= UInt8(ascii: "9") {
                    self.index = j
                    while self.index < self.bytes.count, self.bytes[self.index] >= UInt8(ascii: "0") && self.bytes[self.index] <= UInt8(ascii: "9") {
                        self.index += 1
                    }
                }
            }
            guard self.index > start, let value = Double(String(decoding: self.bytes[start ..< self.index], as: UTF8.self)) else {
                self.index = max(self.index, start + 1)
                return 0.0
            }
            return value
        }

        /// An arc flag: a single 0 or 1, which may run into the next number ("a1 1 0 01.5 1").
        private mutating func flag() -> Bool {
            self.skipSeparators()
            guard self.index < self.bytes.count else {
                return false
            }
            let c = self.bytes[self.index]
            self.index += 1
            return c == UInt8(ascii: "1")
        }

        mutating func parse() -> [CGPath] {
            var result: [CGPath] = []
            var current: CGMutablePath?
            var command: UInt8 = 0
            var x = 0.0
            var y = 0.0
            var startX = 0.0
            var startY = 0.0
            // The last control point, for S/s (cubic) and T/t (quadratic) reflections.
            var lastCubic: (Double, Double)?
            var lastQuad: (Double, Double)?

            func ensure() -> CGMutablePath {
                if let current = current {
                    return current
                }
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: y))
                current = path
                result.append(path)
                return path
            }

            while true {
                self.skipSeparators()
                guard self.index < self.bytes.count else {
                    break
                }
                let c = self.bytes[self.index]
                if Parser.isCommand(c) {
                    command = c
                    self.index += 1
                } else if command == 0 || !self.hasNumber() {
                    // Not path data: stop rather than loop.
                    break
                }
                let relative = command >= UInt8(ascii: "a") && command <= UInt8(ascii: "z")
                let ox = relative ? x : 0.0
                let oy = relative ? y : 0.0
                switch command {
                case UInt8(ascii: "M"), UInt8(ascii: "m"):
                    x = self.number() + ox
                    y = self.number() + oy
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: x, y: y))
                    current = path
                    result.append(path)
                    startX = x
                    startY = y
                    // Pairs after a moveto are linetos.
                    command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
                    lastCubic = nil
                    lastQuad = nil
                case UInt8(ascii: "L"), UInt8(ascii: "l"):
                    x = self.number() + ox
                    y = self.number() + oy
                    ensure().addLine(to: CGPoint(x: x, y: y))
                    lastCubic = nil
                    lastQuad = nil
                case UInt8(ascii: "H"), UInt8(ascii: "h"):
                    x = self.number() + ox
                    ensure().addLine(to: CGPoint(x: x, y: y))
                    lastCubic = nil
                    lastQuad = nil
                case UInt8(ascii: "V"), UInt8(ascii: "v"):
                    y = self.number() + oy
                    ensure().addLine(to: CGPoint(x: x, y: y))
                    lastCubic = nil
                    lastQuad = nil
                case UInt8(ascii: "C"), UInt8(ascii: "c"):
                    let x1 = self.number() + ox
                    let y1 = self.number() + oy
                    let x2 = self.number() + ox
                    let y2 = self.number() + oy
                    x = self.number() + ox
                    y = self.number() + oy
                    ensure().addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                    lastCubic = (x2, y2)
                    lastQuad = nil
                case UInt8(ascii: "S"), UInt8(ascii: "s"):
                    let x1 = lastCubic.map { 2.0 * x - $0.0 } ?? x
                    let y1 = lastCubic.map { 2.0 * y - $0.1 } ?? y
                    let x2 = self.number() + ox
                    let y2 = self.number() + oy
                    x = self.number() + ox
                    y = self.number() + oy
                    ensure().addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                    lastCubic = (x2, y2)
                    lastQuad = nil
                case UInt8(ascii: "Q"), UInt8(ascii: "q"):
                    let qx = self.number() + ox
                    let qy = self.number() + oy
                    x = self.number() + ox
                    y = self.number() + oy
                    ensure().addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: qx, y: qy))
                    lastQuad = (qx, qy)
                    lastCubic = nil
                case UInt8(ascii: "T"), UInt8(ascii: "t"):
                    let qx = lastQuad.map { 2.0 * x - $0.0 } ?? x
                    let qy = lastQuad.map { 2.0 * y - $0.1 } ?? y
                    x = self.number() + ox
                    y = self.number() + oy
                    ensure().addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: qx, y: qy))
                    lastQuad = (qx, qy)
                    lastCubic = nil
                case UInt8(ascii: "A"), UInt8(ascii: "a"):
                    let rx = self.number()
                    let ry = self.number()
                    let phi = self.number()
                    let largeArc = self.flag()
                    let sweep = self.flag()
                    let x2 = self.number() + ox
                    let y2 = self.number() + oy
                    Parser.addArc(ensure(), from: (x, y), to: (x2, y2), rx: rx, ry: ry, phi: phi, largeArc: largeArc, sweep: sweep)
                    x = x2
                    y = y2
                    lastCubic = nil
                    lastQuad = nil
                case UInt8(ascii: "Z"), UInt8(ascii: "z"):
                    // A command after it that is not a moveto starts a new subpath at the start point,
                    // in the same piece (the prototype splits at movetos only).
                    ensure().closeSubpath()
                    x = startX
                    y = startY
                    lastCubic = nil
                    lastQuad = nil
                    command = 0
                default:
                    break
                }
            }
            return result
        }

        /// SVG 1.1 F.6.5 (endpoint → centre parameterization) and cubic segments of at most 90°.
        static func addArc(_ path: CGMutablePath, from p1: (Double, Double), to p2: (Double, Double), rx rxIn: Double, ry ryIn: Double, phi: Double, largeArc: Bool, sweep: Bool) {
            if p1.0 == p2.0 && p1.1 == p2.1 {
                return
            }
            var rx = abs(rxIn)
            var ry = abs(ryIn)
            if rx == 0.0 || ry == 0.0 {
                path.addLine(to: CGPoint(x: p2.0, y: p2.1))
                return
            }
            let rad = phi * Double.pi / 180.0
            let cosPhi = cos(rad)
            let sinPhi = sin(rad)
            let dx = (p1.0 - p2.0) / 2.0
            let dy = (p1.1 - p2.1) / 2.0
            let x1p = cosPhi * dx + sinPhi * dy
            let y1p = -sinPhi * dx + cosPhi * dy
            let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
            if lambda > 1.0 {
                rx *= sqrt(lambda)
                ry *= sqrt(lambda)
            }
            let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
            let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
            var coefficient = denominator == 0.0 ? 0.0 : sqrt(max(0.0, numerator / denominator))
            if largeArc == sweep {
                coefficient = -coefficient
            }
            let cxp = coefficient * rx * y1p / ry
            let cyp = -coefficient * ry * x1p / rx
            let cx = cosPhi * cxp - sinPhi * cyp + (p1.0 + p2.0) / 2.0
            let cy = sinPhi * cxp + cosPhi * cyp + (p1.1 + p2.1) / 2.0
            func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
                return atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            }
            let theta1 = angle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry)
            var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
            if !sweep && delta > 0.0 {
                delta -= 2.0 * Double.pi
            } else if sweep && delta < 0.0 {
                delta += 2.0 * Double.pi
            }
            let segments = max(1, Int(ceil(abs(delta) / (Double.pi / 2.0) - 1e-9)))
            let step = delta / Double(segments)
            let k = 4.0 / 3.0 * tan(step / 4.0)
            func map(_ ux: Double, _ uy: Double) -> CGPoint {
                return CGPoint(x: cx + rx * ux * cosPhi - ry * uy * sinPhi, y: cy + rx * ux * sinPhi + ry * uy * cosPhi)
            }
            var a = theta1
            for i in 0 ..< segments {
                let b = theta1 + step * Double(i + 1)
                let c1 = map(cos(a) - k * sin(a), sin(a) + k * cos(a))
                let c2 = map(cos(b) + k * sin(b), sin(b) - k * cos(b))
                let end = i == segments - 1 ? CGPoint(x: p2.0, y: p2.1) : map(cos(b), sin(b))
                path.addCurve(to: end, control1: c1, control2: c2)
                a = b
            }
        }
    }
}
