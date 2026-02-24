//
//  TimelineWindowView.swift
//  MemoriesApp
//

import SwiftUI
import UIKit

/// 时间轴窗口视图：支持窗口过滤、事件点吸附、触觉反馈与前后步进
struct TimelineWindowView: View {
    let rangeStart: Date
    let rangeEnd: Date
    @Binding var selectedDate: Date
    @Binding var windowHours: Double
    /// 事件点（如某天有照片）：拖动后可吸附，并显示为时间轴上的点
    var eventDates: [Date] = []
    /// 是否显示前一/后一事件按钮
    var showStepButtons: Bool = false
    var onStepBack: (() -> Void)?
    var onStepForward: (() -> Void)?
    var canStepBack: Bool = false
    var canStepForward: Bool = false
    
    private var sliderValue: Double {
        let start = rangeStart.timeIntervalSince1970
        let end = rangeEnd.timeIntervalSince1970
        let current = selectedDate.timeIntervalSince1970
        guard end > start else { return 0 }
        return (current - start) / (end - start)
    }
    
    private func date(from value: Double) -> Date {
        let start = rangeStart.timeIntervalSince1970
        let end = rangeEnd.timeIntervalSince1970
        let t = start + value * (end - start)
        return Date(timeIntervalSince1970: t)
    }
    
    /// 吸附到最近的事件点（阈值约 2% 时间轴长度）
    private func snapToNearestEvent(_ date: Date) -> Date {
        guard !eventDates.isEmpty else { return date }
        let range = rangeEnd.timeIntervalSince1970 - rangeStart.timeIntervalSince1970
        let threshold = range * 0.02
        let t = date.timeIntervalSince1970
        let nearest = eventDates.min(by: { abs($0.timeIntervalSince1970 - t) < abs($1.timeIntervalSince1970 - t) })
        guard let n = nearest, abs(n.timeIntervalSince1970 - t) <= threshold else { return date }
        return n
    }
    
    /// 当前选中的是否为此事件日（用于高亮圆点）
    private func isSelectedEvent(_ eventDate: Date) -> Bool {
        guard !eventDates.isEmpty else { return false }
        let t = selectedDate.timeIntervalSince1970
        let nearest = eventDates.min(by: { abs($0.timeIntervalSince1970 - t) < abs($1.timeIntervalSince1970 - t) })
        return nearest.map { abs($0.timeIntervalSince1970 - t) < 60 } ?? false
    }
    
    /// 计算时间窗口
    var timeWindow: DateInterval {
        let halfWindow = windowHours * 3600 / 2
        return DateInterval(
            start: selectedDate.addingTimeInterval(-halfWindow),
            end: selectedDate.addingTimeInterval(halfWindow)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("时间轴")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                // 窗口大小选择器
                Menu {
                    Button("±6 小时") { windowHours = 6 }
                    Button("±12 小时") { windowHours = 12 }
                    Button("±1 天") { windowHours = 24 }
                    Button("±3 天") { windowHours = 72 }
                    Button("±1 周") { windowHours = 168 }
                } label: {
                    HStack {
                        Image(systemName: "clock")
                        Text(windowHoursText)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Text(rangeStart, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ZStack(alignment: .leading) {
                    Slider(value: Binding(
                        get: { sliderValue },
                        set: { newVal in
                            let snapped = snapToNearestEvent(date(from: newVal))
                            let crossedEvent = snapped != selectedDate
                            selectedDate = snapped
                            if crossedEvent {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    ), in: 0...1)
                    if !eventDates.isEmpty {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let start = rangeStart.timeIntervalSince1970
                            let end = rangeEnd.timeIntervalSince1970
                            ForEach(Array(eventDates.enumerated()), id: \.offset) { _, d in
                                let v = end > start ? (d.timeIntervalSince1970 - start) / (end - start) : 0
                                let x = 6 + (w - 12) * CGFloat(v)
                                Circle()
                                    .fill(isSelectedEvent(d) ? Color.accentColor : Color.secondary.opacity(0.5))
                                    .frame(width: 8, height: 8)
                                    .position(x: x, y: geo.size.height / 2)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                Text(rangeEnd, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if showStepButtons {
                HStack(spacing: 16) {
                    Button {
                        onStepBack?()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canStepBack ? .primary : .tertiary)
                    }
                    .disabled(!canStepBack)
                    Spacer()
                    Button {
                        onStepForward?()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canStepForward ? .primary : .tertiary)
                    }
                    .disabled(!canStepForward)
                }
            }
            if !eventDates.isEmpty {
                Text("拖动时间轴会吸附到有照片的时间点，可点前后按钮切换")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // 显示当前窗口范围
            HStack {
                Text("窗口:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeWindow.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(timeWindow.end.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var windowHoursText: String {
        if windowHours < 24 {
            return "±\(Int(windowHours))h"
        } else {
            let days = Int(windowHours / 24)
            return "±\(days)天"
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var date = Date()
        @State var windowHours: Double = 6
        var body: some View {
            TimelineWindowView(
                rangeStart: Calendar.current.date(byAdding: .day, value: -30, to: date)!,
                rangeEnd: date,
                selectedDate: $date,
                windowHours: $windowHours
            )
        }
    }
    return PreviewWrapper()
}
