//
//  TimelineSliderView.swift
//  MemoriesApp
//

import SwiftUI

struct TimelineSliderView: View {
    let rangeStart: Date
    let rangeEnd: Date
    @Binding var selectedDate: Date
    var windowDays: Double = 3

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("时间轴")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(rangeStart, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Slider(value: Binding(
                    get: { sliderValue },
                    set: { selectedDate = date(from: $0) }
                ), in: 0...1)
                Text(rangeEnd, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text("窗口: ±\(Int(windowDays)) 天 · \(selectedDate, style: .date)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var date = Date()
        var body: some View {
            TimelineSliderView(
                rangeStart: Calendar.current.date(byAdding: .day, value: -30, to: date)!,
                rangeEnd: date,
                selectedDate: $date
            )
        }
    }
    return PreviewWrapper()
}
