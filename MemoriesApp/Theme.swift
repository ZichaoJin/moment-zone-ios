//
//  Theme.swift
//  MemoriesApp
//
//  全局统一主题：柔和浅棕色系

import SwiftUI

enum AppTheme {
    // MARK: - 核心色

    /// 主强调色（温暖焦糖棕） — 同 AccentColor
    static let accent = Color.accentColor

    /// 主色的浅底色（用于卡片背景、选中态）
    static let accentSoft = Color(red: 0.651, green: 0.545, blue: 0.420).opacity(0.12)

    /// 面板/工具栏按钮背景（浅棕半透明）
    static let pillBackground = Color(red: 0.78, green: 0.68, blue: 0.56).opacity(0.42)

    /// 面板/工具栏按钮文字
    static let pillForeground = Color(red: 0.22, green: 0.17, blue: 0.12)

    /// 半透明按钮描边（统一玻璃质感）
    static let pillStroke = Color.clear

    /// 浮动按钮背景材质用的 tint
    static let fabTint = Color(red: 0.55, green: 0.44, blue: 0.33).opacity(0.08)

    // MARK: - 日历 Story 色盘（暖色系）

    /// 为 story 按序生成柔和暖色
    static func storyColor(for index: Int) -> Color {
        // 黄金比例在暖色区旋转（色相 0~0.12 橙/棕/金）
        let goldenRatio = 0.61803398875
        let baseHue = 0.07 // 暖棕基准
        let hue = (baseHue + Double(index) * goldenRatio * 0.18)
            .truncatingRemainder(dividingBy: 1.0)
        let sat = index.isMultiple(of: 2) ? 0.50 : 0.40
        let bri = index.isMultiple(of: 3) ? 0.78 : 0.70
        return Color(hue: hue, saturation: sat, brightness: bri)
    }

    // MARK: - 卡片

    /// 卡片背景
    static let cardBackground = Color(red: 0.96, green: 0.93, blue: 0.89)

    /// 卡片圆角
    static let cardRadius: CGFloat = 12

    // MARK: - 辅助

    /// 高亮边框
    static let highlightBorder = accent
    /// 高亮填充
    static let highlightFill = Color(red: 0.651, green: 0.545, blue: 0.420).opacity(0.18)

    /// popover 中被选中 story 的背景
    static let popoverSelectedBg = Color(red: 0.651, green: 0.545, blue: 0.420).opacity(0.10)

    /// 地图聚合气泡颜色
    static let clusterBadge = Color(red: 0.65, green: 0.50, blue: 0.35)
    /// 高亮聚合气泡颜色
    static let clusterBadgeHighlight = Color(red: 0.82, green: 0.58, blue: 0.30)

    /// 成功 banner 颜色
    static let successGreen = Color(red: 0.48, green: 0.70, blue: 0.45)

    // MARK: - Story Category

    static func categoryColor(_ category: StoryCategory) -> Color {
        switch category {
        case .love:
            return Color(red: 0.95, green: 0.44, blue: 0.67)
        case .friendship:
            return Color(red: 0.45, green: 0.66, blue: 0.94)
        case .birthday:
            return Color(red: 0.97, green: 0.63, blue: 0.33)
        case .travel:
            return Color(red: 0.33, green: 0.72, blue: 0.60)
        case .milestone:
            return Color(red: 0.67, green: 0.56, blue: 0.94)
        case .daily:
            return Color(red: 0.86, green: 0.62, blue: 0.33)
        }
    }

    /// 同类型下仍按 story 维持可区分色阶（用于连续同类型故事区分）
    static func storyColor(category: StoryCategory, storyId: UUID) -> Color {
        let palettes: [StoryCategory: [Color]] = [
            .love: [
                Color(red: 0.95, green: 0.44, blue: 0.67),
                Color(red: 0.90, green: 0.36, blue: 0.60),
                Color(red: 0.98, green: 0.55, blue: 0.73)
            ],
            .friendship: [
                Color(red: 0.45, green: 0.66, blue: 0.94),
                Color(red: 0.36, green: 0.58, blue: 0.90),
                Color(red: 0.57, green: 0.75, blue: 0.98)
            ],
            .birthday: [
                Color(red: 0.97, green: 0.63, blue: 0.33),
                Color(red: 0.92, green: 0.54, blue: 0.25),
                Color(red: 0.99, green: 0.71, blue: 0.44)
            ],
            .travel: [
                Color(red: 0.33, green: 0.72, blue: 0.60),
                Color(red: 0.24, green: 0.64, blue: 0.53),
                Color(red: 0.45, green: 0.78, blue: 0.67)
            ],
            .milestone: [
                Color(red: 0.67, green: 0.56, blue: 0.94),
                Color(red: 0.58, green: 0.47, blue: 0.88),
                Color(red: 0.76, green: 0.65, blue: 0.97)
            ],
            .daily: [
                Color(red: 0.86, green: 0.62, blue: 0.33),
                Color(red: 0.79, green: 0.54, blue: 0.27),
                Color(red: 0.91, green: 0.69, blue: 0.42)
            ]
        ]
        let palette = palettes[category] ?? [categoryColor(category)]
        let seed = storyId.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[seed % palette.count]
    }
}
