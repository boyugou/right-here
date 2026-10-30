import Foundation

/// A blank document of Microsoft Office's formats, which a New File template makes instead of a text: an Office Open XML package
/// (ECMA-376) with the fewest parts each format needs. The parts are written here from the standard; no file of another program is in
/// them. The package is a ZIP archive whose entries are stored, not compressed, with a fixed date, so the same format always gives the
/// same bytes.
public enum OfficeFormat: String, Sendable, Codable, CaseIterable {
    case docx, xlsx, pptx
}

public enum OfficeDocument {
    /// The bytes of a blank document of `format`.
    public static func bytes(_ format: OfficeFormat) -> [UInt8] {
        StoredZip.archive(parts(format).map { ($0.name, Array($0.xml.utf8)) })
    }

    private static let declaration = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
    private static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let drawing = "http://schemas.openxmlformats.org/drawingml/2006/main"
    private static let presentation = "http://schemas.openxmlformats.org/presentationml/2006/main"

    private static func types(_ overrides: [(part: String, type: String)]) -> String {
        declaration + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + overrides.map { #"<Override PartName="\#($0.part)" ContentType="\#($0.type)"/>"# }.joined()
            + "</Types>"
    }

    private static func rels(_ targets: [(type: String, target: String)]) -> String {
        declaration + #"<Relationships xmlns="\#(packageRelationships)">"#
            + targets.enumerated().map { #"<Relationship Id="rId\#($0.offset + 1)" Type="\#(relationships)/\#($0.element.type)" Target="\#($0.element.target)"/>"# }.joined()
            + "</Relationships>"
    }

    private static func parts(_ format: OfficeFormat) -> [(name: String, xml: String)] {
        let officeML = "application/vnd.openxmlformats-officedocument"
        switch format {
        case .docx:
            return [
                ("[Content_Types].xml", types([("/word/document.xml", "\(officeML).wordprocessingml.document.main+xml")])),
                ("_rels/.rels", rels([("officeDocument", "word/document.xml")])),
                ("word/document.xml", declaration + #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/></w:body></w:document>"#),
            ]
        case .xlsx:
            return [
                ("[Content_Types].xml", types([("/xl/workbook.xml", "\(officeML).spreadsheetml.sheet.main+xml"),
                                               ("/xl/worksheets/sheet1.xml", "\(officeML).spreadsheetml.worksheet+xml")])),
                ("_rels/.rels", rels([("officeDocument", "xl/workbook.xml")])),
                ("xl/workbook.xml", declaration + #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="\#(relationships)"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"#),
                ("xl/_rels/workbook.xml.rels", rels([("worksheet", "worksheets/sheet1.xml")])),
                ("xl/worksheets/sheet1.xml", declaration + #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>"#),
            ]
        case .pptx:
            let namespaces = #"xmlns:a="\#(drawing)" xmlns:r="\#(relationships)" xmlns:p="\#(presentation)""#
            let emptyTree = #"<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree>"#
            return [
                ("[Content_Types].xml", types([("/ppt/presentation.xml", "\(officeML).presentationml.presentation.main+xml"),
                                               ("/ppt/slides/slide1.xml", "\(officeML).presentationml.slide+xml"),
                                               ("/ppt/slideMasters/slideMaster1.xml", "\(officeML).presentationml.slideMaster+xml"),
                                               ("/ppt/slideLayouts/slideLayout1.xml", "\(officeML).presentationml.slideLayout+xml"),
                                               ("/ppt/theme/theme1.xml", "\(officeML).theme+xml")])),
                ("_rels/.rels", rels([("officeDocument", "ppt/presentation.xml")])),
                ("ppt/presentation.xml", declaration + #"<p:presentation \#(namespaces)><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst><p:sldId id="256" r:id="rId3"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#),
                ("ppt/_rels/presentation.xml.rels", rels([("slideMaster", "slideMasters/slideMaster1.xml"), ("theme", "theme/theme1.xml"), ("slide", "slides/slide1.xml")])),
                // One empty slide, as a new presentation starts with: a presentation of none showed nothing, not even in Quick Look.
                ("ppt/slides/slide1.xml", declaration + #"<p:sld \#(namespaces)><p:cSld>\#(emptyTree)</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"#),
                ("ppt/slides/_rels/slide1.xml.rels", rels([("slideLayout", "../slideLayouts/slideLayout1.xml")])),
                ("ppt/slideMasters/slideMaster1.xml", declaration + #"<p:sldMaster \#(namespaces)><p:cSld>\#(emptyTree)</p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>"#),
                ("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([("slideLayout", "../slideLayouts/slideLayout1.xml"), ("theme", "../theme/theme1.xml")])),
                ("ppt/slideLayouts/slideLayout1.xml", declaration + #"<p:sldLayout \#(namespaces) type="blank" preserve="1"><p:cSld name="Blank">\#(emptyTree)</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"#),
                ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([("slideMaster", "../slideMasters/slideMaster1.xml")])),
                ("ppt/theme/theme1.xml", declaration + theme),
            ]
        }
    }

    /// The colours, fonts and line and fill styles a presentation's theme must name (the schema asks for three of each style). Plain
    /// values of this project's own choosing.
    private static let theme: String = {
        let colors = [("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "303540"), ("lt2", "EDEEF0"), ("accent1", "3A6FD8"), ("accent2", "E0803A"),
                      ("accent3", "8A8F98"), ("accent4", "E8B830"), ("accent5", "4E98D0"), ("accent6", "5AA65A"), ("hlink", "3A6FD8"), ("folHlink", "7A4FB8")]
        let scheme = colors.map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
        let font = { (face: String) in #"<a:latin typeface="\#(face)"/><a:ea typeface=""/><a:cs typeface=""/>"# }
        let fill = #"<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>"#
        let line = #"<a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>"#
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        return #"<a:theme xmlns:a="\#(drawing)" name="Blank"><a:themeElements>"#
            + #"<a:clrScheme name="Blank">\#(scheme)</a:clrScheme>"#
            + #"<a:fontScheme name="Blank"><a:majorFont>\#(font("Arial"))</a:majorFont><a:minorFont>\#(font("Arial"))</a:minorFont></a:fontScheme>"#
            + #"<a:fmtScheme name="Blank"><a:fillStyleLst>\#(String(repeating: fill, count: 3))</a:fillStyleLst>"#
            + "<a:lnStyleLst>\(String(repeating: line, count: 3))</a:lnStyleLst>"
            + "<a:effectStyleLst>\(String(repeating: effect, count: 3))</a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(String(repeating: fill, count: 3))</a:bgFillStyleLst></a:fmtScheme>"
            + "</a:themeElements></a:theme>"
    }()
}

/// A ZIP archive (PKWARE's APPNOTE) of stored entries: no compression, a CRC-32 of each, 1 January 1980 as the date of every entry.
enum StoredZip {
    static func archive(_ entries: [(name: String, data: [UInt8])]) -> [UInt8] {
        var output: [UInt8] = []
        var directory: [UInt8] = []
        let date: UInt16 = (0 << 9) | (1 << 5) | 1
        for entry in entries {
            let name = Array(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)
            output += le32(0x0403_4B50) + le16(10) + le16(0) + le16(0) + le16(0) + le16(date)
                + le32(crc) + le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count)) + le16(UInt16(name.count)) + le16(0) + name + entry.data
            directory += le32(0x0201_4B50) + le16(20) + le16(10) + le16(0) + le16(0) + le16(0) + le16(date)
                + le32(crc) + le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count)) + le16(UInt16(name.count))
                + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let directoryOffset = UInt32(output.count)
        output += directory
        output += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
            + le32(UInt32(directory.count)) + le32(directoryOffset) + le16(0)
        return output
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: [UInt8]) -> UInt32 {
        ~data.reduce(UInt32.max) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }

    private static func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    private static func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
}
