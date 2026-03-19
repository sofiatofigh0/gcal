import SwiftUI

struct TaskListView: View {
    @StateObject private var viewModel = TaskListViewModel()
    @State private var showDateFilter = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("My Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showDateFilter.toggle() }) {
                            Label("Filter by Date", systemImage: "calendar")
                        }
                        if viewModel.filterDate != nil {
                            Button("Clear Filter", role: .destructive) {
                                viewModel.filterDate = nil
                            }
                        }
                        if !viewModel.pastTasks.isEmpty {
                            Button("Clear Past Tasks", role: .destructive) {
                                Task { await viewModel.clearAllPast() }
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.filterDate != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showDateFilter) {
                DateFilterSheet(selectedDate: $viewModel.filterDate)
                    .presentationDetents([.medium])
            }
            .onAppear { viewModel.loadTasks() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No Tasks Yet")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Use the Voice tab to add tasks\nby speaking naturally.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var taskList: some View {
        List {
            if !viewModel.upcomingTasks.isEmpty || viewModel.filterDate != nil {
                Section("Upcoming") {
                    ForEach(viewModel.filterDate != nil ? viewModel.filteredTasks : viewModel.upcomingTasks) { task in
                        TaskRow(task: task)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.deleteTask(task) }
                                }
                            }
                    }
                }
            }

            if !viewModel.pastTasks.isEmpty && viewModel.filterDate == nil {
                Section("Past") {
                    ForEach(viewModel.pastTasks) { task in
                        TaskRow(task: task)
                            .opacity(0.6)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.deleteTask(task) }
                                }
                            }
                    }
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: VoiceTask

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))

                Text(task.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(destinationLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(task.destination == .reminderOnly ? .green : .indigo)
            }

            Spacer()

            HStack(spacing: 8) {
                if task.hasAlarm && task.hasExplicitDate {
                    Image(systemName: "alarm.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if task.googleCalendarEventId != nil {
                    Image(systemName: "g.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                if task.reminderIdentifier != nil {
                    Image(systemName: "checklist")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var destinationLabel: String {
        switch task.destination {
        case .calendarAndReminder:
            return "Calendar + Reminders"
        case .reminderOnly:
            return "Reminders"
        }
    }

    private var statusIcon: some View {
        Group {
            switch task.status {
            case .synced:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .pending:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.title3)
    }
}

struct DateFilterSheet: View {
    @Binding var selectedDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Date", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.indigo)

                Button("Apply Filter") {
                    selectedDate = pickerDate
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            .padding()
            .navigationTitle("Filter by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
