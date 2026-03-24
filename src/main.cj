package svg_renderer

import std.collection.*
import std.fs.*
import std.math.*
import std.math.numeric.*

let PI_VALUE: Float64 = 3.141592653589793
let SAMPLE_COUNT: Int64 = 4

struct Point {
    var x: Float64
    var y: Float64

    init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }
}

struct Bounds {
    var minX: Float64
    var minY: Float64
    var maxX: Float64
    var maxY: Float64

    init() {
        this.minX = 1.0e30
        this.minY = 1.0e30
        this.maxX = -1.0e30
        this.maxY = -1.0e30
    }

    func include(p: Point): Bounds {
        var out = this
        if (p.x < out.minX) { out.minX = p.x }
        if (p.y < out.minY) { out.minY = p.y }
        if (p.x > out.maxX) { out.maxX = p.x }
        if (p.y > out.maxY) { out.maxY = p.y }
        return out
    }

    func valid(): Bool {
        return minX <= maxX && minY <= maxY
    }
}

struct Matrix {
    var a: Float64
    var b: Float64
    var c: Float64
    var d: Float64
    var e: Float64
    var f: Float64

    init(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64) {
        this.a = a
        this.b = b
        this.c = c
        this.d = d
        this.e = e
        this.f = f
    }

    func apply(p: Point): Point {
        return Point(a * p.x + c * p.y + e, b * p.x + d * p.y + f)
    }
}

struct Color {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        this.r = r
        this.g = g
        this.b = b
        this.a = a
    }
}

struct StyleState {
    var visible: Bool
    var fillEnabled: Bool
    var fillColor: Color
    var strokeEnabled: Bool
    var strokeColor: Color
    var strokeWidth: Float64
    var opacity: Float64
    var fillOpacity: Float64
    var strokeOpacity: Float64
    var evenOdd: Bool
    var transform: Matrix

    init() {
        this.visible = true
        this.fillEnabled = true
        this.fillColor = Color(0, 0, 0, 255)
        this.strokeEnabled = false
        this.strokeColor = Color(0, 0, 0, 255)
        this.strokeWidth = 1.0
        this.opacity = 1.0
        this.fillOpacity = 1.0
        this.strokeOpacity = 1.0
        this.evenOdd = false
        this.transform = identityMatrix()
    }
}

class PathContour {
    var points: ArrayList<Point>
    var closed: Bool

    init(closed: Bool) {
        this.points = ArrayList<Point>()
        this.closed = closed
    }
}

class Geometry {
    var contours: ArrayList<PathContour>

    init() {
        this.contours = ArrayList<PathContour>()
    }
}

class Node {
    let name: String
    var attrs: HashMap<String, String>
    var children: ArrayList<Node>

    init(name: String) {
        this.name = name
        this.attrs = HashMap<String, String>()
        this.children = ArrayList<Node>()
    }
}

class XmlParser {
    let text: String
    var index: Int64

    init(text: String) {
        this.text = text
        this.index = 0
    }

    func eof(): Bool {
        return index >= text.size
    }

    func cur(): Int64 {
        return Int64(text[index])
    }

    func startsWith(prefix: String): Bool {
        if (index + prefix.size > text.size) {
            return false
        }
        return text[index..(index + prefix.size)] == prefix
    }

    func skipSpaces(): Unit {
        while (!eof()) {
            let ch = cur()
            if (ch == 32 || ch == 9 || ch == 10 || ch == 13) {
                index += 1
            } else {
                break
            }
        }
    }

    func skipComment(): Unit {
        index += 4
        while (!eof() && !startsWith("-->")) {
            index += 1
        }
        if (startsWith("-->")) {
            index += 3
        }
    }

    func skipInstruction(): Unit {
        index += 2
        while (!eof() && !startsWith("?>")) {
            index += 1
        }
        if (startsWith("?>")) {
            index += 2
        }
    }

    func skipDeclaration(): Unit {
        index += 2
        while (!eof() && cur() != 62) {
            index += 1
        }
        if (!eof()) {
            index += 1
        }
    }

    func parseName(): String {
        let start = index
        while (!eof() && isNameChar(cur())) {
            index += 1
        }
        if (index <= start) {
            return ""
        }
        return text[start..index]
    }

    func parseValue(): String {
        if (eof()) {
            return ""
        }
        let qv = cur()
        if (qv == 34 || qv == 39) {
            index += 1
            let start = index
            while (!eof() && cur() != qv) {
                index += 1
            }
            let out = text[start..index]
            if (!eof()) {
                index += 1
            }
            return out
        }
        let start = index
        while (!eof()) {
            let ch = cur()
            if (ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 62) {
                break
            }
            index += 1
        }
        return text[start..index]
    }

    func parseElement(): Node {
        if (eof() || cur() != 60) {
            return Node("")
        }
        index += 1
        if (!eof() && cur() == 47) {
            while (!eof() && cur() != 62) {
                index += 1
            }
            if (!eof()) {
                index += 1
            }
            return Node("")
        }
        let rawName = parseName()
        let node = Node(stripNamePrefix(rawName))
        skipSpaces()
        while (!eof() && cur() != 62 && cur() != 47) {
            let rawKey = parseName()
            let key = stripNamePrefix(rawKey)
            skipSpaces()
            var value = ""
            if (!eof() && cur() == 61) {
                index += 1
                skipSpaces()
                value = parseValue()
            }
            if (rawKey != "") {
                node.attrs[rawKey] = value
                if (!node.attrs.contains(key)) {
                    node.attrs[key] = value
                }
            }
            skipSpaces()
        }
        var selfClose = false
        if (!eof() && cur() == 47) {
            selfClose = true
            index += 1
        }
        if (!eof() && cur() == 62) {
            index += 1
        }
        if (selfClose) {
            return node
        }
        while (!eof()) {
            if (startsWith("<!--")) {
                skipComment()
                continue
            }
            if (startsWith("</")) {
                index += 2
                let _ = parseName()
                while (!eof() && cur() != 62) {
                    index += 1
                }
                if (!eof()) {
                    index += 1
                }
                break
            }
            if (cur() == 60) {
                let child = parseElement()
                if (child.name != "") {
                    node.children.add(child)
                }
            } else {
                index += 1
            }
        }
        return node
    }

    func parseDocument(): Node {
        let root = Node("#document")
        while (!eof()) {
            skipSpaces()
            if (eof()) {
                break
            }
            if (startsWith("<!--")) {
                skipComment()
            } else if (startsWith("<?")) {
                skipInstruction()
            } else if (startsWith("<!")) {
                skipDeclaration()
            } else if (cur() == 60) {
                let child = parseElement()
                if (child.name != "") {
                    root.children.add(child)
                }
            } else {
                index += 1
            }
        }
        return root
    }
}

class PathReader {
    let text: String
    var index: Int64

    init(text: String) {
        this.text = text
        this.index = 0
    }

    func eof(): Bool {
        return index >= text.size
    }

    func skipSeparators(): Unit {
        while (!eof()) {
            let ch = Int64(text[index])
            if (ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 44) {
                index += 1
            } else {
                break
            }
        }
    }

    func peekCommand(): String {
        skipSeparators()
        if (eof()) {
            return ""
        }
        let ch = Int64(text[index])
        if ((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)) {
            return text[index..(index + 1)]
        }
        return ""
    }

    func takeCommand(): String {
        let cmd = peekCommand()
        if (cmd != "") {
            index += 1
        }
        return cmd
    }

    func hasNumber(): Bool {
        skipSeparators()
        if (eof()) {
            return false
        }
        let ch = Int64(text[index])
        return ch == 43 || ch == 45 || ch == 46 || (ch >= 48 && ch <= 57)
    }

    func readNumber(): Float64 {
        skipSeparators()
        let start = index
        if (!eof()) {
            let ch = Int64(text[index])
            if (ch == 43 || ch == 45) {
                index += 1
            }
        }
        var hasDigit = false
        while (!eof()) {
            let ch = Int64(text[index])
            if (ch >= 48 && ch <= 57) {
                hasDigit = true
                index += 1
            } else {
                break
            }
        }
        if (!eof() && Int64(text[index]) == 46) {
            index += 1
            while (!eof()) {
                let ch = Int64(text[index])
                if (ch >= 48 && ch <= 57) {
                    hasDigit = true
                    index += 1
                } else {
                    break
                }
            }
        }
        if (!eof()) {
            let ch = Int64(text[index])
            if (ch == 69 || ch == 101) {
                index += 1
                if (!eof()) {
                    let next = Int64(text[index])
                    if (next == 43 || next == 45) {
                        index += 1
                    }
                }
                while (!eof()) {
                    let digit = Int64(text[index])
                    if (digit >= 48 && digit <= 57) {
                        index += 1
                    } else {
                        break
                    }
                }
            }
        }
        if (!hasDigit) {
            if (!eof()) {
                index += 1
            }
            return 0.0
        }
        return parseFloat(text[start..index])
    }
}

class Canvas {
    let width: Int64
    let height: Int64
    var pixels: Array<UInt8>

    init(width: Int64, height: Int64) {
        this.width = width
        this.height = height
        this.pixels = Array<UInt8>(width * height * 4, repeat: 255)
    }

    func blendPixel(x: Int64, y: Int64, color: Color, alpha: Float64): Unit {
        if (x < 0 || y < 0 || x >= width || y >= height) {
            return
        }
        var a = alpha
        if (a <= 0.0) {
            return
        }
        if (a > 1.0) {
            a = 1.0
        }
        let idx = (y * width + x) * 4
        let dr = Float64(pixels[idx + 0])
        let dg = Float64(pixels[idx + 1])
        let db = Float64(pixels[idx + 2])
        let sa = a * Float64(color.a) / 255.0
        let inv = 1.0 - sa
        pixels[idx + 0] = clampByte(Float64(color.r) * sa + dr * inv)
        pixels[idx + 1] = clampByte(Float64(color.g) * sa + dg * inv)
        pixels[idx + 2] = clampByte(Float64(color.b) * sa + db * inv)
        pixels[idx + 3] = 255
    }

    func saveBmp(path: Path): Unit {
        let rowStride = width * 4
        let imageSize = rowStride * height
        let fileSize = 54 + imageSize
        var out = ArrayList<UInt8>()
        pushByte(out, 66)
        pushByte(out, 77)
        pushU32(out, UInt32(fileSize))
        pushU16(out, 0)
        pushU16(out, 0)
        pushU32(out, 54)
        pushU32(out, 40)
        pushI32(out, Int32(width))
        pushI32(out, Int32(height))
        pushU16(out, 1)
        pushU16(out, 32)
        pushU32(out, 0)
        pushU32(out, UInt32(imageSize))
        pushI32(out, 2835)
        pushI32(out, 2835)
        pushU32(out, 0)
        pushU32(out, 0)
        for (row in 0..height) {
            let y = height - 1 - row
            for (x in 0..width) {
                let idx = (y * width + x) * 4
                pushByte(out, pixels[idx + 2])
                pushByte(out, pixels[idx + 1])
                pushByte(out, pixels[idx + 0])
                pushByte(out, 0)
            }
        }
        File.writeTo(path, out.toArray())
    }
}

func identityMatrix(): Matrix {
    return Matrix(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
}

func multiplyMatrix(left: Matrix, right: Matrix): Matrix {
    return Matrix(
        left.a * right.a + left.c * right.b,
        left.b * right.a + left.d * right.b,
        left.a * right.c + left.c * right.d,
        left.b * right.c + left.d * right.d,
        left.a * right.e + left.c * right.f + left.e,
        left.b * right.e + left.d * right.f + left.f
    )
}

func translateMatrix(tx: Float64, ty: Float64): Matrix {
    return Matrix(1.0, 0.0, 0.0, 1.0, tx, ty)
}

func scaleMatrix(sx: Float64, sy: Float64): Matrix {
    return Matrix(sx, 0.0, 0.0, sy, 0.0, 0.0)
}

func rotateMatrix(angleDeg: Float64): Matrix {
    let rad = angleDeg * PI_VALUE / 180.0
    let c = cos(rad)
    let s = sin(rad)
    return Matrix(c, s, -s, c, 0.0, 0.0)
}

func clampFloat(v: Float64, low: Float64, high: Float64): Float64 {
    if (v < low) { return low }
    if (v > high) { return high }
    return v
}

func clampByte(v: Float64): UInt8 {
    let r = round(v)
    if (r <= 0.0) { return 0 }
    if (r >= 255.0) { return 255 }
    return UInt8(Int64(r))
}

func absFloat(v: Float64): Float64 {
    if (v < 0.0) { return -v }
    return v
}

func isNameChar(ch: Int64): Bool {
    return (ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch == 45 || ch == 46 || ch == 58
}

func stripNamePrefix(name: String): String {
    let pos = match (name.indexOf(":")) {
        case Some(v) => v
        case None => -1
    }
    if (pos >= 0) {
        return name[(pos + 1)..name.size]
    }
    return name
}

func lowerAscii(text: String): String {
    let src = text.toArray()
    var out = ArrayList<UInt8>()
    for (b in src) {
        if (b >= 65 && b <= 90) {
            out.add(UInt8(Int64(b) + 32))
        } else {
            out.add(b)
        }
    }
    return String.fromUtf8(out.toArray())
}

func trimAscii(text: String): String {
    var start: Int64 = 0
    var end = text.size
    while (start < end) {
        let ch = Int64(text[start])
        if (ch == 32 || ch == 9 || ch == 10 || ch == 13) {
            start += 1
        } else {
            break
        }
    }
    while (end > start) {
        let ch = Int64(text[end - 1])
        if (ch == 32 || ch == 9 || ch == 10 || ch == 13) {
            end -= 1
        } else {
            break
        }
    }
    if (start >= end) {
        return ""
    }
    return text[start..end]
}

func parseFloat(text: String): Float64 {
    var value = trimAscii(text)
    if (value == "") {
        return 0.0
    }
    if (value.endsWith("px") || value.endsWith("pt") || value.endsWith("pc") || value.endsWith("mm") || value.endsWith("cm") || value.endsWith("in")) {
        value = value[0..(value.size - 2)]
    } else if (value.endsWith("%")) {
        value = value[0..(value.size - 1)]
    }
    try {
        return Decimal.parse(value).toFloat64()
    } catch (_) {
        return 0.0
    }
}

func parseOptionalFloat(attrs: HashMap<String, String>, key: String, defaultValue: Float64): Float64 {
    if (attrs.contains(key)) {
        return parseFloat(attrs[key])
    }
    return defaultValue
}

func parseHexByte(text: String): UInt8 {
    let lowered = lowerAscii(text)
    var value: Int64 = 0
    for (i in 0..lowered.size) {
        let ch = Int64(lowered[i])
        value *= 16
        if (ch >= 48 && ch <= 57) {
            value += ch - 48
        } else if (ch >= 97 && ch <= 102) {
            value += ch - 87
        }
    }
    return UInt8(value)
}

func parseRgbComponent(text: String): UInt8 {
    let value = trimAscii(text)
    if (value.endsWith("%")) {
        return clampByte(parseFloat(value[0..(value.size - 1)]) * 2.55)
    }
    return clampByte(parseFloat(value))
}

func parseColor(text: String): (Bool, Color) {
    let value = lowerAscii(trimAscii(text))
    if (value == "" || value == "none") { return (false, Color(0, 0, 0, 0)) }
    if (value == "transparent") { return (true, Color(0, 0, 0, 0)) }
    if (value == "black") { return (true, Color(0, 0, 0, 255)) }
    if (value == "white") { return (true, Color(255, 255, 255, 255)) }
    if (value == "red") { return (true, Color(255, 0, 0, 255)) }
    if (value == "green") { return (true, Color(0, 128, 0, 255)) }
    if (value == "blue") { return (true, Color(0, 0, 255, 255)) }
    if (value == "yellow") { return (true, Color(255, 255, 0, 255)) }
    if (value == "gray" || value == "grey") { return (true, Color(128, 128, 128, 255)) }
    if (value == "cyan" || value == "aqua") { return (true, Color(0, 255, 255, 255)) }
    if (value == "magenta" || value == "fuchsia") { return (true, Color(255, 0, 255, 255)) }
    if (value == "orange") { return (true, Color(255, 165, 0, 255)) }
    if (value == "purple") { return (true, Color(128, 0, 128, 255)) }
    if (value == "pink") { return (true, Color(255, 192, 203, 255)) }
    if (value == "brown") { return (true, Color(165, 42, 42, 255)) }
    if (value.startsWith("#")) {
        let hex = value[1..value.size]
        if (hex.size == 3) {
            return (
                true,
                Color(
                    parseHexByte(hex[0..1] + hex[0..1]),
                    parseHexByte(hex[1..2] + hex[1..2]),
                    parseHexByte(hex[2..3] + hex[2..3]),
                    255
                )
            )
        }
        if (hex.size == 6) {
            return (true, Color(parseHexByte(hex[0..2]), parseHexByte(hex[2..4]), parseHexByte(hex[4..6]), 255))
        }
    }
    if (value.startsWith("rgb(") && value.endsWith(")")) {
        let body = value[4..(value.size - 1)]
        let parts = body.split(",")
        if (parts.size >= 3) {
            return (true, Color(parseRgbComponent(parts[0]), parseRgbComponent(parts[1]), parseRgbComponent(parts[2]), 255))
        }
    }
    return (false, Color(0, 0, 0, 255))
}

func parseNumberList(text: String): ArrayList<Float64> {
    let reader = PathReader(text)
    var result = ArrayList<Float64>()
    while (reader.hasNumber()) {
        result.add(reader.readNumber())
    }
    return result
}

func parseTransform(text: String): Matrix {
    var result = identityMatrix()
    var index: Int64 = 0
    while (index < text.size) {
        while (index < text.size) {
            let ch = Int64(text[index])
            if (ch == 32 || ch == 9 || ch == 10 || ch == 13) {
                index += 1
            } else {
                break
            }
        }
        let start = index
        while (index < text.size) {
            let ch = Int64(text[index])
            if ((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)) {
                index += 1
            } else {
                break
            }
        }
        if (index <= start) {
            index += 1
            continue
        }
        let name = lowerAscii(text[start..index])
        while (index < text.size) {
            let ch = Int64(text[index])
            if (ch == 32 || ch == 9 || ch == 10 || ch == 13) {
                index += 1
            } else {
                break
            }
        }
        if (index >= text.size || Int64(text[index]) != 40) {
            continue
        }
        index += 1
        let begin = index
        while (index < text.size && Int64(text[index]) != 41) {
            index += 1
        }
        let args = parseNumberList(text[begin..index])
        if (index < text.size && Int64(text[index]) == 41) {
            index += 1
        }
        var item = identityMatrix()
        if (name == "translate") {
            let tx = if (args.size >= 1) { args[0] } else { 0.0 }
            let ty = if (args.size >= 2) { args[1] } else { 0.0 }
            item = translateMatrix(tx, ty)
        } else if (name == "scale") {
            let sx = if (args.size >= 1) { args[0] } else { 1.0 }
            let sy = if (args.size >= 2) { args[1] } else { sx }
            item = scaleMatrix(sx, sy)
        } else if (name == "rotate") {
            let angle = if (args.size >= 1) { args[0] } else { 0.0 }
            if (args.size >= 3) {
                item = multiplyMatrix(translateMatrix(args[1], args[2]), multiplyMatrix(rotateMatrix(angle), translateMatrix(-args[1], -args[2])))
            } else {
                item = rotateMatrix(angle)
            }
        } else if (name == "matrix" && args.size >= 6) {
            item = Matrix(args[0], args[1], args[2], args[3], args[4], args[5])
        }
        result = multiplyMatrix(result, item)
    }
    return result
}

func applyStyleProperty(style: StyleState, keyText: String, valueText: String): StyleState {
    var s = style
    let key = lowerAscii(trimAscii(keyText))
    let value = trimAscii(valueText)
    if (key == "fill") {
        let c = parseColor(value)
        s.fillEnabled = c[0]
        s.fillColor = c[1]
    } else if (key == "stroke") {
        let c = parseColor(value)
        s.strokeEnabled = c[0]
        s.strokeColor = c[1]
    } else if (key == "stroke-width") {
        s.strokeWidth = parseFloat(value)
    } else if (key == "opacity") {
        s.opacity *= clampFloat(parseFloat(value), 0.0, 1.0)
    } else if (key == "fill-opacity") {
        s.fillOpacity *= clampFloat(parseFloat(value), 0.0, 1.0)
    } else if (key == "stroke-opacity") {
        s.strokeOpacity *= clampFloat(parseFloat(value), 0.0, 1.0)
    } else if (key == "fill-rule") {
        s.evenOdd = lowerAscii(value) == "evenodd"
    } else if (key == "display") {
        if (lowerAscii(value) == "none") {
            s.visible = false
        }
    } else if (key == "visibility") {
        if (lowerAscii(value) == "hidden") {
            s.visible = false
        }
    } else if (key == "transform") {
        s.transform = multiplyMatrix(s.transform, parseTransform(value))
    }
    return s
}

func applyStyle(node: Node, inherited: StyleState): StyleState {
    var s = inherited
    if (node.attrs.contains("fill")) { s = applyStyleProperty(s, "fill", node.attrs["fill"]) }
    if (node.attrs.contains("stroke")) { s = applyStyleProperty(s, "stroke", node.attrs["stroke"]) }
    if (node.attrs.contains("stroke-width")) { s = applyStyleProperty(s, "stroke-width", node.attrs["stroke-width"]) }
    if (node.attrs.contains("opacity")) { s = applyStyleProperty(s, "opacity", node.attrs["opacity"]) }
    if (node.attrs.contains("fill-opacity")) { s = applyStyleProperty(s, "fill-opacity", node.attrs["fill-opacity"]) }
    if (node.attrs.contains("stroke-opacity")) { s = applyStyleProperty(s, "stroke-opacity", node.attrs["stroke-opacity"]) }
    if (node.attrs.contains("fill-rule")) { s = applyStyleProperty(s, "fill-rule", node.attrs["fill-rule"]) }
    if (node.attrs.contains("display")) { s = applyStyleProperty(s, "display", node.attrs["display"]) }
    if (node.attrs.contains("visibility")) { s = applyStyleProperty(s, "visibility", node.attrs["visibility"]) }
    if (node.attrs.contains("transform")) { s = applyStyleProperty(s, "transform", node.attrs["transform"]) }
    if (node.attrs.contains("style")) {
        let parts = node.attrs["style"].split(";")
        for (part in parts) {
            let item = trimAscii(part)
            if (item == "") {
                continue
            }
            let pos = match (item.indexOf(":")) {
                case Some(v) => v
                case None => -1
            }
            if (pos >= 0) {
                s = applyStyleProperty(s, item[0..pos], item[(pos + 1)..item.size])
            }
        }
    }
    return s
}

func buildIdMap(node: Node, ids: HashMap<String, Node>): Unit {
    if (node.attrs.contains("id")) {
        ids[node.attrs["id"]] = node
    }
    for (child in node.children) {
        buildIdMap(child, ids)
    }
}

func addPoint(contour: PathContour, p: Point): Unit {
    if (contour.points.size > 0) {
        let last = contour.points[contour.points.size - 1]
        if (absFloat(last.x - p.x) < 1.0e-9 && absFloat(last.y - p.y) < 1.0e-9) {
            return
        }
    }
    contour.points.add(p)
}

func appendArc(contour: PathContour, cx: Float64, cy: Float64, rx: Float64, ry: Float64, startAngle: Float64, endAngle: Float64, segments: Int64): Unit {
    let steps = max(1, segments)
    for (i in 0..(steps + 1)) {
        let t = Float64(i) / Float64(steps)
        let ang = startAngle + (endAngle - startAngle) * t
        addPoint(contour, Point(cx + rx * cos(ang), cy + ry * sin(ang)))
    }
}

func buildEllipse(cx: Float64, cy: Float64, rx: Float64, ry: Float64): Geometry {
    let geometry = Geometry()
    let contour = PathContour(true)
    appendArc(contour, cx, cy, rx, ry, 0.0, PI_VALUE * 2.0, 64)
    geometry.contours.add(contour)
    return geometry
}

func buildRect(x: Float64, y: Float64, width: Float64, height: Float64, rx: Float64, ry: Float64): Geometry {
    let geometry = Geometry()
    let contour = PathContour(true)
    let crx = clampFloat(rx, 0.0, width * 0.5)
    let cry = clampFloat(ry, 0.0, height * 0.5)
    if (crx <= 0.0 || cry <= 0.0) {
        contour.points.add(Point(x, y))
        contour.points.add(Point(x + width, y))
        contour.points.add(Point(x + width, y + height))
        contour.points.add(Point(x, y + height))
    } else {
        addPoint(contour, Point(x + crx, y))
        addPoint(contour, Point(x + width - crx, y))
        appendArc(contour, x + width - crx, y + cry, crx, cry, -PI_VALUE / 2.0, 0.0, 8)
        addPoint(contour, Point(x + width, y + height - cry))
        appendArc(contour, x + width - crx, y + height - cry, crx, cry, 0.0, PI_VALUE / 2.0, 8)
        addPoint(contour, Point(x + crx, y + height))
        appendArc(contour, x + crx, y + height - cry, crx, cry, PI_VALUE / 2.0, PI_VALUE, 8)
        addPoint(contour, Point(x, y + cry))
        appendArc(contour, x + crx, y + cry, crx, cry, PI_VALUE, PI_VALUE * 1.5, 8)
    }
    geometry.contours.add(contour)
    return geometry
}

func buildLine(x1: Float64, y1: Float64, x2: Float64, y2: Float64): Geometry {
    let geometry = Geometry()
    let contour = PathContour(false)
    contour.points.add(Point(x1, y1))
    contour.points.add(Point(x2, y2))
    geometry.contours.add(contour)
    return geometry
}

func buildPoly(pointsText: String, closed: Bool): Geometry {
    let nums = parseNumberList(pointsText)
    let geometry = Geometry()
    let contour = PathContour(closed)
    let pairCount = nums.size / 2
    for (i in 0..pairCount) {
        contour.points.add(Point(nums[i * 2], nums[i * 2 + 1]))
    }
    geometry.contours.add(contour)
    return geometry
}

func appendQuadratic(contour: PathContour, p0: Point, p1: Point, p2: Point): Unit {
    let steps: Int64 = 24
    for (i in 1..(steps + 1)) {
        let t = Float64(i) / Float64(steps)
        let mt = 1.0 - t
        let x = mt * mt * p0.x + 2.0 * mt * t * p1.x + t * t * p2.x
        let y = mt * mt * p0.y + 2.0 * mt * t * p1.y + t * t * p2.y
        addPoint(contour, Point(x, y))
    }
}

func appendCubic(contour: PathContour, p0: Point, p1: Point, p2: Point, p3: Point): Unit {
    let steps: Int64 = 32
    for (i in 1..(steps + 1)) {
        let t = Float64(i) / Float64(steps)
        let mt = 1.0 - t
        let x = mt * mt * mt * p0.x + 3.0 * mt * mt * t * p1.x + 3.0 * mt * t * t * p2.x + t * t * t * p3.x
        let y = mt * mt * mt * p0.y + 3.0 * mt * mt * t * p1.y + 3.0 * mt * t * t * p2.y + t * t * t * p3.y
        addPoint(contour, Point(x, y))
    }
}

func vectorAngle(ux: Float64, uy: Float64, vx: Float64, vy: Float64): Float64 {
    return atan2(ux * vy - uy * vx, ux * vx + uy * vy)
}

func appendArcTo(contour: PathContour, from: Point, rxIn: Float64, ryIn: Float64, angleDeg: Float64, largeArcFlag: Bool, sweepFlag: Bool, to: Point): Unit {
    var rx = absFloat(rxIn)
    var ry = absFloat(ryIn)
    if (rx <= 1.0e-9 || ry <= 1.0e-9) {
        addPoint(contour, to)
        return
    }
    let phi = angleDeg * PI_VALUE / 180.0
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let dx2 = (from.x - to.x) * 0.5
    let dy2 = (from.y - to.y) * 0.5
    let x1p = cosPhi * dx2 + sinPhi * dy2
    let y1p = -sinPhi * dx2 + cosPhi * dy2
    let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
    if (lambda > 1.0) {
        let scale = sqrt(lambda)
        rx *= scale
        ry *= scale
    }
    let sign = if (largeArcFlag == sweepFlag) { -1.0 } else { 1.0 }
    let rx2 = rx * rx
    let ry2 = ry * ry
    let x1p2 = x1p * x1p
    let y1p2 = y1p * y1p
    let numerator = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2
    let denom = rx2 * y1p2 + ry2 * x1p2
    let coef = if (denom <= 1.0e-12) { 0.0 } else { sign * sqrt(max(0.0, numerator / denom)) }
    let cxp = coef * (rx * y1p / ry)
    let cyp = coef * (-ry * x1p / rx)
    let cx = cosPhi * cxp - sinPhi * cyp + (from.x + to.x) * 0.5
    let cy = sinPhi * cxp + cosPhi * cyp + (from.y + to.y) * 0.5
    let ux = (x1p - cxp) / rx
    let uy = (y1p - cyp) / ry
    let vx = (-x1p - cxp) / rx
    let vy = (-y1p - cyp) / ry
    let startAngle = vectorAngle(1.0, 0.0, ux, uy)
    var deltaAngle = vectorAngle(ux, uy, vx, vy)
    if (!sweepFlag && deltaAngle > 0.0) {
        deltaAngle -= PI_VALUE * 2.0
    }
    if (sweepFlag && deltaAngle < 0.0) {
        deltaAngle += PI_VALUE * 2.0
    }
    let steps = max(4, Int64(ceil(absFloat(deltaAngle) / (PI_VALUE / 8.0))))
    for (i in 1..(steps + 1)) {
        let t = Float64(i) / Float64(steps)
        let angle = startAngle + deltaAngle * t
        let xp = rx * cos(angle)
        let yp = ry * sin(angle)
        let x = cosPhi * xp - sinPhi * yp + cx
        let y = sinPhi * xp + cosPhi * yp + cy
        addPoint(contour, Point(x, y))
    }
}

func parsePath(data: String): Geometry {
    let reader = PathReader(data)
    let geometry = Geometry()
    var current = Point(0.0, 0.0)
    var subStart = Point(0.0, 0.0)
    var contour = PathContour(false)
    var active = false
    var command = ""
    var lastCubic = Point(0.0, 0.0)
    var lastQuad = Point(0.0, 0.0)
    var prevCommand = ""

    while (!reader.eof()) {
        let next = reader.peekCommand()
        if (next != "") {
            command = reader.takeCommand()
        } else if (command == "") {
            reader.index += 1
            continue
        }
        let lower = lowerAscii(command)
        let relative = command != lower

        if (lower == "m") {
            if (!reader.hasNumber()) {
                continue
            }
            let x = reader.readNumber()
            let y = reader.readNumber()
            current = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
            if (active && contour.points.size > 0) {
                geometry.contours.add(contour)
            }
            contour = PathContour(false)
            active = true
            addPoint(contour, current)
            subStart = current
            while (reader.hasNumber()) {
                let px = reader.readNumber()
                let py = reader.readNumber()
                current = if (relative) { Point(current.x + px, current.y + py) } else { Point(px, py) }
                addPoint(contour, current)
            }
            prevCommand = "L"
            continue
        }

        if (!active) {
            contour = PathContour(false)
            active = true
            addPoint(contour, current)
            subStart = current
        }

        if (lower == "z") {
            contour.closed = true
            geometry.contours.add(contour)
            contour = PathContour(false)
            active = false
            current = subStart
            prevCommand = command
            continue
        }

        while (reader.hasNumber()) {
            if (lower == "l") {
                let x = reader.readNumber()
                let y = reader.readNumber()
                current = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
                addPoint(contour, current)
            } else if (lower == "h") {
                let x = reader.readNumber()
                current = if (relative) { Point(current.x + x, current.y) } else { Point(x, current.y) }
                addPoint(contour, current)
            } else if (lower == "v") {
                let y = reader.readNumber()
                current = if (relative) { Point(current.x, current.y + y) } else { Point(current.x, y) }
                addPoint(contour, current)
            } else if (lower == "c") {
                let x1 = reader.readNumber()
                let y1 = reader.readNumber()
                let x2 = reader.readNumber()
                let y2 = reader.readNumber()
                let x = reader.readNumber()
                let y = reader.readNumber()
                let p1 = if (relative) { Point(current.x + x1, current.y + y1) } else { Point(x1, y1) }
                let p2 = if (relative) { Point(current.x + x2, current.y + y2) } else { Point(x2, y2) }
                let p3 = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
                appendCubic(contour, current, p1, p2, p3)
                current = p3
                lastCubic = p2
                prevCommand = command
            } else if (lower == "s") {
                let x2 = reader.readNumber()
                let y2 = reader.readNumber()
                let x = reader.readNumber()
                let y = reader.readNumber()
                let p1 = if (prevCommand == "C" || prevCommand == "c" || prevCommand == "S" || prevCommand == "s") {
                    Point(2.0 * current.x - lastCubic.x, 2.0 * current.y - lastCubic.y)
                } else {
                    current
                }
                let p2 = if (relative) { Point(current.x + x2, current.y + y2) } else { Point(x2, y2) }
                let p3 = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
                appendCubic(contour, current, p1, p2, p3)
                current = p3
                lastCubic = p2
                prevCommand = command
            } else if (lower == "q") {
                let x1 = reader.readNumber()
                let y1 = reader.readNumber()
                let x = reader.readNumber()
                let y = reader.readNumber()
                let p1 = if (relative) { Point(current.x + x1, current.y + y1) } else { Point(x1, y1) }
                let p2 = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
                appendQuadratic(contour, current, p1, p2)
                current = p2
                lastQuad = p1
                prevCommand = command
            } else if (lower == "t") {
                let x = reader.readNumber()
                let y = reader.readNumber()
                let p1 = if (prevCommand == "Q" || prevCommand == "q" || prevCommand == "T" || prevCommand == "t") {
                    Point(2.0 * current.x - lastQuad.x, 2.0 * current.y - lastQuad.y)
                } else {
                    current
                }
                let p2 = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
                appendQuadratic(contour, current, p1, p2)
                current = p2
                lastQuad = p1
                prevCommand = command
            } else if (lower == "a") {
                let rx = reader.readNumber()
                let ry = reader.readNumber()
                let rot = reader.readNumber()
                let large = reader.readNumber() >= 0.5
                let sweep = reader.readNumber() >= 0.5
                let x = reader.readNumber()
                let y = reader.readNumber()
                let target = if (relative) { Point(current.x + x, current.y + y) } else { Point(x, y) }
                appendArcTo(contour, current, rx, ry, rot, large, sweep, target)
                current = target
                prevCommand = command
            } else {
                break
            }
            if (lower != "c" && lower != "s") {
                lastCubic = current
            }
            if (lower != "q" && lower != "t") {
                lastQuad = current
            }
            if (lower == "l" || lower == "h" || lower == "v" || lower == "a") {
                prevCommand = command
            }
        }
    }

    if (active && contour.points.size > 0) {
        geometry.contours.add(contour)
    }
    return geometry
}

func geometryFromNode(node: Node): Geometry {
    if (node.name == "rect") {
        let x = parseOptionalFloat(node.attrs, "x", 0.0)
        let y = parseOptionalFloat(node.attrs, "y", 0.0)
        let width = parseOptionalFloat(node.attrs, "width", 0.0)
        let height = parseOptionalFloat(node.attrs, "height", 0.0)
        let rx = if (node.attrs.contains("rx")) { parseFloat(node.attrs["rx"]) } else { 0.0 }
        let ry = if (node.attrs.contains("ry")) { parseFloat(node.attrs["ry"]) } else { rx }
        return buildRect(x, y, width, height, rx, ry)
    }
    if (node.name == "circle") {
        let cx = parseOptionalFloat(node.attrs, "cx", 0.0)
        let cy = parseOptionalFloat(node.attrs, "cy", 0.0)
        let r = parseOptionalFloat(node.attrs, "r", 0.0)
        return buildEllipse(cx, cy, r, r)
    }
    if (node.name == "ellipse") {
        let cx = parseOptionalFloat(node.attrs, "cx", 0.0)
        let cy = parseOptionalFloat(node.attrs, "cy", 0.0)
        let rx = parseOptionalFloat(node.attrs, "rx", 0.0)
        let ry = parseOptionalFloat(node.attrs, "ry", 0.0)
        return buildEllipse(cx, cy, rx, ry)
    }
    if (node.name == "line") {
        return buildLine(
            parseOptionalFloat(node.attrs, "x1", 0.0),
            parseOptionalFloat(node.attrs, "y1", 0.0),
            parseOptionalFloat(node.attrs, "x2", 0.0),
            parseOptionalFloat(node.attrs, "y2", 0.0)
        )
    }
    if (node.name == "polyline") {
        return buildPoly(if (node.attrs.contains("points")) { node.attrs["points"] } else { "" }, false)
    }
    if (node.name == "polygon") {
        return buildPoly(if (node.attrs.contains("points")) { node.attrs["points"] } else { "" }, true)
    }
    if (node.name == "path") {
        return parsePath(if (node.attrs.contains("d")) { node.attrs["d"] } else { "" })
    }
    return Geometry()
}

func geometryBounds(geometry: Geometry): Bounds {
    var bounds = Bounds()
    for (contour in geometry.contours) {
        for (p in contour.points) {
            bounds = bounds.include(p)
        }
    }
    return bounds
}

func transformGeometry(geometry: Geometry, transform: Matrix): Geometry {
    let out = Geometry()
    for (contour in geometry.contours) {
        let dst = PathContour(contour.closed)
        for (p in contour.points) {
            dst.points.add(transform.apply(p))
        }
        out.contours.add(dst)
    }
    return out
}

func estimatedScale(transform: Matrix): Float64 {
    let sx = sqrt(transform.a * transform.a + transform.b * transform.b)
    let sy = sqrt(transform.c * transform.c + transform.d * transform.d)
    if (sx <= 0.0 && sy <= 0.0) {
        return 1.0
    }
    return (sx + sy) * 0.5
}

func isLeft(a: Point, b: Point, p: Point): Float64 {
    return (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
}

func pointInContourEvenOdd(contour: PathContour, p: Point): Int64 {
    var hits: Int64 = 0
    let n = contour.points.size
    for (i in 0..n) {
        let a = contour.points[i]
        let b = contour.points[(i + 1) % n]
        let cross = (a.y > p.y) != (b.y > p.y)
        if (cross) {
            let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
            if (x > p.x) {
                hits += 1
            }
        }
    }
    return hits
}

func pointInContourWinding(contour: PathContour, p: Point): Int64 {
    var w: Int64 = 0
    let n = contour.points.size
    for (i in 0..n) {
        let a = contour.points[i]
        let b = contour.points[(i + 1) % n]
        if (a.y <= p.y) {
            if (b.y > p.y && isLeft(a, b, p) > 0.0) {
                w += 1
            }
        } else {
            if (b.y <= p.y && isLeft(a, b, p) < 0.0) {
                w -= 1
            }
        }
    }
    return w
}

func pointInGeometry(geometry: Geometry, p: Point, evenOdd: Bool): Bool {
    if (evenOdd) {
        var hits: Int64 = 0
        for (contour in geometry.contours) {
            if (contour.closed && contour.points.size >= 3) {
                hits += pointInContourEvenOdd(contour, p)
            }
        }
        return hits % 2 == 1
    }
    var winding: Int64 = 0
    for (contour in geometry.contours) {
        if (contour.closed && contour.points.size >= 3) {
            winding += pointInContourWinding(contour, p)
        }
    }
    return winding != 0
}

func pointSegmentDistanceSquared(p: Point, a: Point, b: Point): Float64 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    if (len2 <= 1.0e-12) {
        let ex = p.x - a.x
        let ey = p.y - a.y
        return ex * ex + ey * ey
    }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
    t = clampFloat(t, 0.0, 1.0)
    let qx = a.x + dx * t
    let qy = a.y + dy * t
    let ex = p.x - qx
    let ey = p.y - qy
    return ex * ex + ey * ey
}

func pointNearStroke(geometry: Geometry, p: Point, radius: Float64): Bool {
    let r2 = radius * radius
    for (contour in geometry.contours) {
        let n = contour.points.size
        if (n < 2) {
            continue
        }
        let segmentCount = if (contour.closed) { n } else { n - 1 }
        for (i in 0..segmentCount) {
            let a = contour.points[i]
            let b = contour.points[(i + 1) % n]
            if (pointSegmentDistanceSquared(p, a, b) <= r2) {
                return true
            }
        }
    }
    return false
}

func rasterFill(canvas: Canvas, geometry: Geometry, color: Color, alpha: Float64, evenOdd: Bool, bounds: Bounds): Unit {
    let minX = max(0, Int64(floor(bounds.minX - 1.0)))
    let minY = max(0, Int64(floor(bounds.minY - 1.0)))
    let maxX = min(canvas.width - 1, Int64(ceil(bounds.maxX + 1.0)))
    let maxY = min(canvas.height - 1, Int64(ceil(bounds.maxY + 1.0)))
    for (y in minY..(maxY + 1)) {
        for (x in minX..(maxX + 1)) {
            var inside: Int64 = 0
            for (sy in 0..2) {
                for (sx in 0..2) {
                    let sample = Point(Float64(x) + 0.25 + Float64(sx) * 0.5, Float64(y) + 0.25 + Float64(sy) * 0.5)
                    if (pointInGeometry(geometry, sample, evenOdd)) {
                        inside += 1
                    }
                }
            }
            if (inside > 0) {
                canvas.blendPixel(x, y, color, alpha * Float64(inside) / Float64(SAMPLE_COUNT))
            }
        }
    }
}

func rasterStroke(canvas: Canvas, geometry: Geometry, color: Color, alpha: Float64, width: Float64, bounds: Bounds): Unit {
    let radius = width * 0.5
    let minX = max(0, Int64(floor(bounds.minX - radius - 1.0)))
    let minY = max(0, Int64(floor(bounds.minY - radius - 1.0)))
    let maxX = min(canvas.width - 1, Int64(ceil(bounds.maxX + radius + 1.0)))
    let maxY = min(canvas.height - 1, Int64(ceil(bounds.maxY + radius + 1.0)))
    for (y in minY..(maxY + 1)) {
        for (x in minX..(maxX + 1)) {
            var inside: Int64 = 0
            for (sy in 0..2) {
                for (sx in 0..2) {
                    let sample = Point(Float64(x) + 0.25 + Float64(sx) * 0.5, Float64(y) + 0.25 + Float64(sy) * 0.5)
                    if (pointNearStroke(geometry, sample, radius)) {
                        inside += 1
                    }
                }
            }
            if (inside > 0) {
                canvas.blendPixel(x, y, color, alpha * Float64(inside) / Float64(SAMPLE_COUNT))
            }
        }
    }
}

func renderGeometry(canvas: Canvas, geometry: Geometry, style: StyleState, strokeScale: Float64): Unit {
    let bounds = geometryBounds(geometry)
    if (!bounds.valid()) {
        return
    }
    if (style.fillEnabled && style.fillColor.a > 0) {
        let alpha = style.opacity * style.fillOpacity
        if (alpha > 0.0) {
            rasterFill(canvas, geometry, style.fillColor, alpha, style.evenOdd, bounds)
        }
    }
    if (style.strokeEnabled && style.strokeColor.a > 0 && style.strokeWidth > 0.0) {
        let alpha = style.opacity * style.strokeOpacity
        if (alpha > 0.0) {
            rasterStroke(canvas, geometry, style.strokeColor, alpha, style.strokeWidth * strokeScale, bounds)
        }
    }
}

func renderNode(node: Node, inherited: StyleState, canvas: Canvas, ids: HashMap<String, Node>, renderable: Bool): Unit {
    let style = applyStyle(node, inherited)
    if (!style.visible) {
        return
    }
    if (node.name == "defs") {
        for (child in node.children) {
            renderNode(child, style, canvas, ids, false)
        }
        return
    }
    if (node.name == "svg" || node.name == "g" || node.name == "symbol") {
        for (child in node.children) {
            renderNode(child, style, canvas, ids, renderable)
        }
        return
    }
    if (node.name == "use") {
        var href = ""
        if (node.attrs.contains("href")) {
            href = node.attrs["href"]
        } else if (node.attrs.contains("xlink:href")) {
            href = node.attrs["xlink:href"]
        }
        if (href.startsWith("#")) {
            let id = href[1..href.size]
            if (ids.contains(id)) {
                var useStyle = style
                let ux = parseOptionalFloat(node.attrs, "x", 0.0)
                let uy = parseOptionalFloat(node.attrs, "y", 0.0)
                useStyle.transform = multiplyMatrix(useStyle.transform, translateMatrix(ux, uy))
                renderNode(ids[id], useStyle, canvas, ids, true)
            }
        }
        return
    }
    if (renderable && (node.name == "rect" || node.name == "circle" || node.name == "ellipse" || node.name == "line" || node.name == "polyline" || node.name == "polygon" || node.name == "path")) {
        let geometry = transformGeometry(geometryFromNode(node), style.transform)
        renderGeometry(canvas, geometry, style, estimatedScale(style.transform))
    }
    for (child in node.children) {
        renderNode(child, style, canvas, ids, renderable)
    }
}

func findSvgRoot(document: Node): Node {
    for (child in document.children) {
        if (child.name == "svg") {
            return child
        }
    }
    return document
}

func lastIndexOf(text: String, token: String): Int64 {
    var pos: Int64 = -1
    var index: Int64 = 0
    while (index <= text.size - token.size) {
        if (text[index..(index + token.size)] == token) {
            pos = index
        }
        index += 1
    }
    return pos
}

func buildRootInfo(svg: Node): (Float64, Float64, Matrix) {
    var viewportW = 1000.0
    var viewportH = 1000.0
    if (svg.attrs.contains("width")) { viewportW = parseFloat(svg.attrs["width"]) }
    if (svg.attrs.contains("height")) { viewportH = parseFloat(svg.attrs["height"]) }
    let vb = if (svg.attrs.contains("viewBox")) { parseNumberList(svg.attrs["viewBox"]) } else { ArrayList<Float64>() }
    if (vb.size >= 4 && (viewportW <= 0.0 || viewportH <= 0.0)) {
        viewportW = vb[2]
        viewportH = vb[3]
    }
    if (viewportW <= 0.0) { viewportW = 1000.0 }
    if (viewportH <= 0.0) { viewportH = 1000.0 }
    var root = identityMatrix()
    let preserve = if (svg.attrs.contains("preserveAspectRatio")) { lowerAscii(trimAscii(svg.attrs["preserveAspectRatio"])) } else { "xmidymid meet" }
    if (vb.size >= 4 && vb[2] > 0.0 && vb[3] > 0.0) {
        if (preserve == "none") {
            let sx = viewportW / vb[2]
            let sy = viewportH / vb[3]
            root = Matrix(sx, 0.0, 0.0, sy, -vb[0] * sx, -vb[1] * sy)
        } else {
            let s = min(viewportW / vb[2], viewportH / vb[3])
            let tx = (viewportW - vb[2] * s) * 0.5 - vb[0] * s
            let ty = (viewportH - vb[3] * s) * 0.5 - vb[1] * s
            root = Matrix(s, 0.0, 0.0, s, tx, ty)
        }
    }
    let scale = max(1.0, 1000.0 / min(viewportW, viewportH))
    let outW = max(1.0, round(viewportW * scale))
    let outH = max(1.0, round(viewportH * scale))
    return (outW, outH, multiplyMatrix(scaleMatrix(scale, scale), root))
}


func hexValue(ch: Int64): Int64 {
    if (ch >= 48 && ch <= 57) { return ch - 48 }
    if (ch >= 65 && ch <= 70) { return ch - 55 }
    if (ch >= 97 && ch <= 102) { return ch - 87 }
    return -1
}

func decodePercentUtf8(text: String): String {
    var bytes = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i < text.size) {
        let ch = Int64(text[i])
        if (ch == 37 && i + 2 < text.size) {
            let h1 = hexValue(Int64(text[i + 1]))
            let h2 = hexValue(Int64(text[i + 2]))
            if (h1 >= 0 && h2 >= 0) {
                bytes.add(UInt8(h1 * 16 + h2))
                i += 3
                continue
            }
        }
        bytes.add(UInt8(ch))
        i += 1
    }
    return String.fromUtf8(bytes.toArray())
}

func normalizeInputArg(arg: String): String {
    if (arg.startsWith("file:///")) {
        let body = decodePercentUtf8(arg[8..arg.size])
        var out = ArrayList<UInt8>()
        for (b in body.toArray()) {
            if (b == 47) {
                out.add(92)
            } else {
                out.add(b)
            }
        }
        return String.fromUtf8(out.toArray())
    }
    return arg
}

func outputPathFor(input: Path, originalArg: String): Path {
    let name = input.fileName
    let dot = lastIndexOf(name, ".")
    let stem = if (dot >= 0) { name[0..dot] } else { name }
    let outName = Path(stem + ".bmp")
    let slash1 = lastIndexOf(originalArg, "\\")
    let slash2 = lastIndexOf(originalArg, "/")
    if (max(slash1, slash2) < 0) {
        return outName
    }
    return input.parent.join(outName)
}

func pushByte(data: ArrayList<UInt8>, value: UInt8): Unit {
    data.add(value)
}

func pushU16(data: ArrayList<UInt8>, value: UInt16): Unit {
    pushByte(data, UInt8(Int64(value) & 255))
    pushByte(data, UInt8((Int64(value) >> 8) & 255))
}

func pushU32(data: ArrayList<UInt8>, value: UInt32): Unit {
    pushByte(data, UInt8(Int64(value) & 255))
    pushByte(data, UInt8((Int64(value) >> 8) & 255))
    pushByte(data, UInt8((Int64(value) >> 16) & 255))
    pushByte(data, UInt8((Int64(value) >> 24) & 255))
}


func utf8ToAsciiView(bytes: Array<UInt8>): String {
    var out = ArrayList<UInt8>()
    var i: Int64 = 0
    if (bytes.size >= 3 && bytes[0] == 239 && bytes[1] == 187 && bytes[2] == 191) {
        i = 3
    }
    while (i < bytes.size) {
        let b0 = Int64(bytes[i])
        if (b0 < 128) {
            out.add(bytes[i])
            i += 1
            continue
        }
        if (b0 >= 194 && b0 <= 223 && i + 1 < bytes.size) {
            let b1 = Int64(bytes[i + 1])
            if (b1 >= 128 && b1 <= 191) {
                out.add(32)
                i += 2
                continue
            }
        }
        if (b0 >= 224 && b0 <= 239 && i + 2 < bytes.size) {
            let b1 = Int64(bytes[i + 1])
            let b2 = Int64(bytes[i + 2])
            let ok = (b1 >= 128 && b1 <= 191) && (b2 >= 128 && b2 <= 191) && !(b0 == 224 && b1 < 160) && !(b0 == 237 && b1 >= 160)
            if (ok) {
                out.add(32)
                i += 3
                continue
            }
        }
        if (b0 >= 240 && b0 <= 244 && i + 3 < bytes.size) {
            let b1 = Int64(bytes[i + 1])
            let b2 = Int64(bytes[i + 2])
            let b3 = Int64(bytes[i + 3])
            let ok = (b1 >= 128 && b1 <= 191) && (b2 >= 128 && b2 <= 191) && (b3 >= 128 && b3 <= 191) && !(b0 == 240 && b1 < 144) && !(b0 == 244 && b1 > 143)
            if (ok) {
                out.add(32)
                i += 4
                continue
            }
        }
        out.add(32)
        i += 1
    }
    return String.fromUtf8(out.toArray())
}

func pushI32(data: ArrayList<UInt8>, value: Int32): Unit {
    let v = Int64(value)
    pushByte(data, UInt8(v & 255))
    pushByte(data, UInt8((v >> 8) & 255))
    pushByte(data, UInt8((v >> 16) & 255))
    pushByte(data, UInt8((v >> 24) & 255))
}

main(args: Array<String>): Int64 {
    if (args.size < 1) {
        println("usage: svg_renderer <file.svg>")
        return 1
    }
    let inputArg = normalizeInputArg(args[0])
    let input = Path(inputArg)
    let rawBytes = File.readFrom(input)
    let text = utf8ToAsciiView(rawBytes)
    let parser = XmlParser(text)
    let document = parser.parseDocument()
    let svg = findSvgRoot(document)
    let rootInfo = buildRootInfo(svg)
    let canvas = Canvas(Int64(rootInfo[0]), Int64(rootInfo[1]))
    var style = StyleState()
    style.transform = rootInfo[2]
    let ids = HashMap<String, Node>()
    buildIdMap(svg, ids)
    renderNode(svg, style, canvas, ids, true)
    let output = outputPathFor(input, args[0])
    canvas.saveBmp(output)
    println("done")
    return 0
}













