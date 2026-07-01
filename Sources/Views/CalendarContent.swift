import SwiftUI

// MARK: - Calendar Content

extension NotchView {

    var calendarContent: some View {
        VStack(spacing: 10) {
            // Header: back + month navigation
            HStack {
                Button(action: { viewModel.closeCalendar() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Text(monthYearString(calendarMonth))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Button(action: { calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()

                // Invisible spacer to balance "返回" width
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .font(.system(size: 11))
                .opacity(0)
            }

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            let days = calendarDays(for: calendarMonth)
            let stats = timer.getDailyStats(for: calendarMonth)
            let statsDict = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0) })

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day = day {
                        let dateId = dayId(day)
                        let stat = statsDict[dateId]
                        calendarDayCell(day: day, stat: stat)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }

            // Monthly summary
            let totalFocus = stats.reduce(0) { $0 + $1.focusMinutes }
            let totalPomodoros = stats.reduce(0) { $0 + $1.completedSessions }
            HStack(spacing: 16) {
                Label("\(totalFocus) 分钟", systemImage: "flame.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Label("\(totalPomodoros) 个番茄", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Calendar Helpers

    func calendarDayCell(day: Date, stat: DailyStats?) -> some View {
        let calendar = Calendar.current
        let dayNum = calendar.component(.day, from: day)
        let isToday = calendar.isDateInToday(day)
        let intensity: Double = stat.map { min(1.0, Double($0.completedSessions) / 4.0) } ?? 0

        return Text("\(dayNum)")
            .font(.system(size: 10, weight: isToday ? .bold : .regular))
            .foregroundColor(isToday ? .white : .white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(intensity > 0 ? accentColor.opacity(0.2 + intensity * 0.6) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isToday ? accentColor : Color.clear, lineWidth: 1)
            )
    }

    func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    func dayId(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Returns array of optional Dates for the calendar grid (nil = empty cell before first day)
    func calendarDays(for month: Date) -> [Date?] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month)!
        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let weekday = calendar.component(.weekday, from: firstDay) - 1 // 0-based, Sunday=0

        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }
}
