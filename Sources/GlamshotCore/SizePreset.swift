import CoreGraphics
import Foundation

/// A viewport to photograph a page at: a device's default screen size in points and the pixel
/// scale it renders at.
public struct SizePreset: Codable, Hashable, Identifiable, Sendable {
    public enum Group: String, Codable, CaseIterable, Sendable {
        case mac, display, tablet, phone, social, custom

        public var title: String {
            switch self {
            case .mac: "Mac"
            case .display: "Displays"
            case .tablet: "iPad"
            case .phone: "iPhone"
            case .social: "Social"
            case .custom: "Custom"
            }
        }
    }

    public var id: String
    public var name: String
    public var group: Group
    /// Width and height in points (CSS pixels).
    public var width: Int
    public var height: Int
    /// Device pixels per point: 1, 2 or 3.
    public var scale: Int

    public init(id: String = UUID().uuidString, name: String, group: Group, width: Int, height: Int, scale: Int) {
        self.id = id
        self.name = name
        self.group = group
        self.width = width
        self.height = height
        self.scale = scale
    }

    public var size: CGSize { CGSize(width: width, height: height) }

    /// iPhones get the iPhone Safari user agent so sites serve their phone layout. iPad Safari asks
    /// for desktop sites by default, so iPads use the Mac one.
    public var userAgent: UserAgent { group == .phone ? .iPhone : .mac }

    /// “1512 × 982”
    public var dimensions: String { "\(width) × \(height)" }
}

extension SizePreset {
    // Macs: the default “looks like” size macOS picks (Apple's specs list only native pixels).
    // iPhone and iPad: the portrait CSS viewport. iPad mini is the A17 Pro model's 744 × 1133.
    public static let builtIns: [SizePreset] = [
        SizePreset(id: "macbook-air-13", name: "MacBook Air 13\"", group: .mac, width: 1470, height: 956, scale: 2),
        SizePreset(id: "macbook-air-15", name: "MacBook Air 15\"", group: .mac, width: 1710, height: 1107, scale: 2),
        SizePreset(id: "macbook-pro-14", name: "MacBook Pro 14\"", group: .mac, width: 1512, height: 982, scale: 2),
        SizePreset(id: "macbook-pro-16", name: "MacBook Pro 16\"", group: .mac, width: 1728, height: 1117, scale: 2),
        SizePreset(id: "imac-24", name: "iMac 24\"", group: .mac, width: 2240, height: 1260, scale: 2),
        SizePreset(id: "studio-display", name: "Studio Display", group: .mac, width: 2560, height: 1440, scale: 2),
        SizePreset(id: "hd-1080", name: "1080p", group: .display, width: 1920, height: 1080, scale: 1),
        SizePreset(id: "qhd-1440", name: "1440p", group: .display, width: 2560, height: 1440, scale: 1),
        SizePreset(id: "ipad-mini", name: "iPad mini", group: .tablet, width: 744, height: 1133, scale: 2),
        SizePreset(id: "ipad-air-11", name: "iPad Air 11\"", group: .tablet, width: 820, height: 1180, scale: 2),
        SizePreset(id: "ipad-air-13", name: "iPad Air 13\"", group: .tablet, width: 1024, height: 1366, scale: 2),
        SizePreset(id: "ipad-pro-11", name: "iPad Pro 11\"", group: .tablet, width: 834, height: 1210, scale: 2),
        SizePreset(id: "ipad-pro-13", name: "iPad Pro 13\"", group: .tablet, width: 1032, height: 1376, scale: 2),
        SizePreset(id: "iphone-17", name: "iPhone 17", group: .phone, width: 402, height: 874, scale: 3),
        SizePreset(id: "iphone-17-pro", name: "iPhone 17 Pro", group: .phone, width: 402, height: 874, scale: 3),
        SizePreset(id: "iphone-17-pro-max", name: "iPhone 17 Pro Max", group: .phone, width: 440, height: 956, scale: 3),
        SizePreset(id: "iphone-air", name: "iPhone Air", group: .phone, width: 420, height: 912, scale: 3),
        SizePreset(id: "iphone-17e", name: "iPhone 17e", group: .phone, width: 390, height: 844, scale: 3),
        SizePreset(id: "social-square", name: "Square", group: .social, width: 1080, height: 1080, scale: 1),
        SizePreset(id: "social-portrait", name: "Portrait 4:5", group: .social, width: 1080, height: 1350, scale: 1),
        SizePreset(id: "social-story", name: "Story 9:16", group: .social, width: 1080, height: 1920, scale: 1),
        SizePreset(id: "social-landscape", name: "Landscape 16:9", group: .social, width: 1920, height: 1080, scale: 1)
    ]

    public static let macBookPro14 = builtIns[2]
}

public enum UserAgent: String, Codable, CaseIterable, Sendable {
    case mac, iPhone

    /// Safari's own strings, so sites serve what Safari users see.
    public var string: String {
        switch self {
        case .mac:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case .iPhone:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        }
    }
}
