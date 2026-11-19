import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var selectedMonth = Date()
    @State private var mode: BudgetPeriodMode = .monthly
    @State private var selectedWeekIndex = 0
    @State private var editingWeeklyCategory: TransactionCategory?

    private var weeks: [BudgetWeek] { store.budgetWeeks(in: selectedMonth) }
    private var selectedWeek: BudgetWeek? { weeks.indices.contains(selectedWeekIndex) ? weeks[selectedWeekIndex] : weeks.first }
    private var weeklyBudget: Decimal { store.weeklyFlexibleBudget(weekIndex: selectedWeekIndex, in: selectedMonth) }
    private var weeklySpent: Decimal { store.weeklyFlexibleSpending(weekIndex: selectedWeekIndex, in: selectedMonth) }

    var body: some View {
        List {
            Section {
                Picker("Budget view", selection: $mode) {
                    ForEach(BudgetPeriodMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Month", selection: $selectedMonth, displayedComponents: [.date])
                    .datePickerStyle(.compact)
            }

            if mode == .monthly { monthlyContent } else { weeklyContent }
        }
        .navigationTitle(mode == .monthly ? "Monthly Budget" : "Weekly Budget")
        .onChange(of: selectedMonth) { _, _ in selectedWeekIndex = 0 }
        .sheet(item: $editingWeeklyCategory) { category in
            NavigationStack { WeeklyAllocationEditor(category: category, month: selectedMonth) }
        }
    }

    @ViewBuilder
    private var monthlyContent: some View {
        Section {
            HStack {
                BudgetTotal(title: "Planned", value: store.totalPlannedSpending(in: selectedMonth), color: .budgetBuddyBlue)
                BudgetTotal(title: "Actual", value: store.actualSpending(in: selectedMonth), color: .orange)
            }
        }

        ForEach([BudgetGroup.needs, .wants, .giving]) { group in
            Section(group.rawValue) {
                ForEach(categories(in: group)) { category in
                    BudgetCategoryRow(category: category, month: selectedMonth)
                }
            }
        }

        Section("Savings") {
            LabeledContent("Available after budget") {
                Text(store.plannedSavings, format: .currency(code: currencyCode))
                    .foregroundStyle(store.plannedSavings >= 0 ? Color.budgetBuddyGreen : .red).bold()
            }
            LabeledContent("Savings goal") {
                Text(store.savingsGoal, format: .currency(code: currencyCode)).bold()
            }
            ProgressView(value: savingsProgress)
                .tint(store.plannedSavings >= store.savingsGoal ? .budgetBuddyGreen : .orange)
        }
    }

    @ViewBuilder
    private var weeklyContent: some View {
        Section {
            Picker("Week", selection: $selectedWeekIndex) {
                ForEach(weeks) { week in Text(week.title).tag(week.index) }
            }
            .pickerStyle(.menu)
            HStack {
                BudgetTotal(title: "Weekly goal", value: weeklyBudget, color: .budgetBuddyBlue)
                BudgetTotal(title: "Spent", value: weeklySpent, color: weeklySpent <= weeklyBudget ? .budgetBuddyGreen : .red)
            }
            Label(
                weeklySpent <= weeklyBudget ? "On track · \((weeklyBudget - weeklySpent).currencyText) left" : "Over by \((weeklySpent - weeklyBudget).currencyText)",
                systemImage: weeklySpent <= weeklyBudget ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .foregroundStyle(weeklySpent <= weeklyBudget ? Color.budgetBuddyGreen : .red)
        } header: {
            Text("Flexible spending")
        } footer: {
            Text("Weekly goals cover flexible categories. Rent or mortgage stays a scheduled monthly bill.")
        }

        if let selectedWeek, store.housingIsDue(in: selectedWeek, month: selectedMonth) {
            Section("Scheduled this week") {
                LabeledContent {
                    Text(store.budget(for: .rent, in: selectedMonth), format: .currency(code: currencyCode)).bold()
                } label: {
                    Label(store.housingLabel, systemImage: "house.fill")
                }
                Text("Due on day \(store.settings.housingDueDay)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("Weekly category goals") {
            ForEach(store.flexibleExpenseCategories) { category in
                Button { editingWeeklyCategory = category } label: {
                    HStack {
                        Label(category.rawValue, systemImage: category.symbol)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(store.weeklyBudget(for: category, weekIndex: selectedWeekIndex, in: selectedMonth), format: .currency(code: currencyCode)).bold()
                            Text("Tap to customize weeks").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categories(in group: BudgetGroup) -> [TransactionCategory] {
        store.expenseCategories.filter { $0.group == group && !($0 == .rent && store.settings.housingType == .neither) }
    }

    private var savingsProgress: Double {
        guard store.savingsGoal > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: store.plannedSavings / store.savingsGoal).doubleValue))
    }
}

private enum BudgetPeriodMode: String, CaseIterable, Identifiable {
    case monthly = "Monthly"
    case weekly = "Weekly"
    var id: Self { self }
}

private struct WeeklyAllocationEditor: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    let category: TransactionCategory
    let month: Date
    @State private var values: [Decimal] = []
    @State private var showTotalWarning = false

    private var monthlyBudget: Decimal { store.budget(for: category, in: month) }
    private var enteredTotal: Decimal { values.reduce(0, +) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Monthly budget") { Text(monthlyBudget, format: .currency(code: currencyCode)).bold() }
                LabeledContent("Assigned to weeks") {
                    Text(enteredTotal, format: .currency(code: currencyCode))
                        .foregroundStyle(enteredTotal == monthlyBudget ? Color.budgetBuddyGreen : .orange).bold()
                }
            }
            Section("Weekly goals") {
                ForEach(Array(store.budgetWeeks(in: month).enumerated()), id: \.offset) { index, week in
                    HStack {
                        Text(week.title)
                        Spacer()
                        EditableDecimalField(
                            value: Binding(
                                get: { values.indices.contains(index) ? values[index] : 0 },
                                set: { if values.indices.contains(index) { values[index] = max(0, $0) } }
                            ),
                            width: 120
                        )
                    }
                }
            }
            if showTotalWarning {
                Text("The weekly amounts must add up to the monthly budget of \(monthlyBudget.currencyText).")
                    .foregroundStyle(.red)
            }
            Button("Reset to automatic split") {
                store.setWeeklyAllocations([], for: category, in: month)
                values = store.weeklyAllocations(for: category, in: month)
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if abs(NSDecimalNumber(decimal: enteredTotal - monthlyBudget).doubleValue) < 0.01 {
                        store.setWeeklyAllocations(values, for: category, in: month)
                        dismiss()
                    } else { showTotalWarning = true }
                }
            }
        }
        .onAppear { values = store.weeklyAllocations(for: category, in: month) }
    }
}

private struct BudgetTotal: View {
    let title: String
    let value: Decimal
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.headline).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetCategoryRow: View {
    @EnvironmentObject private var store: TransactionStore
    let category: TransactionCategory
    let month: Date
    @State private var requestFocus = false
    private var budget: Decimal { store.budget(for: category, in: month) }
    private var actual: Decimal { store.actualSpending(for: category, in: month) }
    private var progress: Double {
        guard budget > 0 else { return actual > 0 ? 1 : 0 }
        return min(1, NSDecimalNumber(decimal: actual / budget).doubleValue)
    }

    var body: some View {
        if category == .tithing {
            TithingBudgetRow(month: month)
        } else {
            standardRow
        }
    }

    private var standardRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category == .rent ? store.housingLabel : category.rawValue, systemImage: category.symbol)
                Spacer()
                if category == .debtPayment {
                    Text(budget, format: .currency(code: currencyCode)).bold()
                } else {
                    EditableDecimalField(
                        value: Binding(get: { budget }, set: { store.setBudget($0, for: category) }),
                        width: 100,
                        focusRequest: $requestFocus
                    )
                }
            }
            ProgressView(value: progress).tint(actual > budget && budget > 0 ? .red : .budgetBuddyBlue)
            HStack {
                Text("Spent \(actual, format: .currency(code: currencyCode))")
                Spacer()
                Text(budget > 0 ? "\(max(0, budget - actual), format: .currency(code: currencyCode)) left" : "No budget set")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if category != .debtPayment { requestFocus = true } }
    }
}

private let tithingVerse = "“Bring ye all the tithes into the storehouse, that there may be meat in mine house, and prove me now herewith, saith the Lord of hosts, if I will not open you the windows of heaven, and pour you out a blessing, that there shall not be room enough to receive it.”"

private struct TithingBudgetRow: View {
    @EnvironmentObject private var store: TransactionStore
    let month: Date
    @State private var showingCelebration = false

    private var goal: Decimal { store.budget(for: .tithing, in: month) }
    private var paid: Decimal { store.tithingPaid(in: month) }
    private var remaining: Decimal { store.tithingRemaining(in: month) }
    private var isPaid: Bool { goal > 0 && remaining < 0.01 }
    private var monthEndText: String {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month),
              let finalDay = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)
        else { return "the end of the month" }
        return finalDay.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tithing", systemImage: "hands.sparkles.fill")
                Spacer()
                if isPaid {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.budgetBuddyGreen)
                        .accessibilityLabel("Paid")
                } else {
                    Text("Due \(monthEndText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if goal == 0 {
                Text("Waiting for income")
                    .font(.headline)
                Text("Your tithing goal will automatically become 10% of the income recorded this month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isPaid {
                Label("The windows of Heaven have been opened!", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.budgetBuddyGreen)
                Text("Malachi 3:10")
                    .font(.caption.weight(.semibold))
                Text(tithingVerse)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showingCelebration = true
                } label: {
                    Label("Replay celebration", systemImage: "party.popper.fill")
                }
                .buttonStyle(.bordered)
                .tint(.budgetBuddyGreen)
            } else {
                Text(remaining, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                    .foregroundStyle(Color.budgetBuddyGreen)
                Text("remaining of your \(goal.currencyText) monthly goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .tint(.budgetBuddyBlue)

                if paid > 0 {
                    Text("\(paid.currencyText) already paid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.markTithingPaid(in: month)
                    showingCelebration = true
                } label: {
                    Label("Mark tithing paid", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.budgetBuddyGreen)
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(isPresented: $showingCelebration) {
            TithingCelebrationSheet()
                .presentationBackground(.clear)
        }
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: paid / goal).doubleValue))
    }
}

private struct TithingCelebrationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.budgetBuddyGreen)

                    Text("The windows of Heaven have been opened!")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    VStack(spacing: 7) {
                        Text("Malachi 3:10")
                            .font(.headline)
                        Text(tithingVerse)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    Button("Continue") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.budgetBuddyGreen)
                        .controlSize(.large)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 30,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 30
                    )
                )
            }
            .ignoresSafeArea(edges: .bottom)

            TithingConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

private struct TithingConfettiView: View {
    @State private var startDate = Date()

    private let colors: [Color] = [
        .budgetBuddyBlue,
        .budgetBuddyGreen,
        Color(red: 85 / 255, green: 240 / 255, blue: 68 / 255),
        .yellow,
        .orange,
        .pink,
        .purple
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.58)
                for index in 0..<180 {
                    let seed = Double(index)
                    let burst = Double(index % 3)
                    let delay = burst * 0.24
                    let duration = 1.35 + pseudoRandom(seed * 3.17) * 0.85
                    let localTime = max(0, elapsed - delay)
                    let progress = min(1, localTime / duration)
                    guard localTime > 0, progress < 1 else { continue }

                    let angleDegrees = 185 + pseudoRandom(seed * 7.31) * 170
                    let angle = angleDegrees * .pi / 180
                    let distance = (150 + pseudoRandom(seed * 13.73) * 330) * easeOut(progress)
                    let gravity = 150 * progress * progress
                    let x = origin.x + cos(angle) * distance
                    let y = origin.y + sin(angle) * distance + gravity
                    let width = 4 + pseudoRandom(seed * 5.91) * 7
                    let height = 7 + pseudoRandom(seed * 9.43) * 10
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    let color = colors[index % colors.count]
                    let opacity = max(0, 1 - pow(progress, 3))

                    if index.isMultiple(of: 4) {
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
                    } else {
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 2),
                            with: .color(color.opacity(opacity))
                        )
                    }
                }
            }
        }
        .onAppear { startDate = Date() }
        .accessibilityHidden(true)
    }

    private func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 2.4)
    }

    private func pseudoRandom(_ value: Double) -> Double {
        let raw = sin(value * 12.9898) * 43_758.5453
        return raw - floor(raw)
    }
}
