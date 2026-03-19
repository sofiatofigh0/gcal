import SwiftUI

struct VoiceInputView: View {
    @StateObject private var viewModel = VoiceInputViewModel()
    @State private var pulseAnimation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    recordingButton
                    transcriptionSection
                    parsedEventsSection
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Voice Input")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.indigo)

            Text("Tap to speak your events")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Say something like: \"Meeting with John tomorrow at 3pm, set an alarm\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 20)
    }

    private var recordingButton: some View {
        Button(action: { viewModel.toggleRecording() }) {
            ZStack {
                Circle()
                    .fill(viewModel.isRecording ? Color.red.opacity(0.15) : Color.indigo.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation && viewModel.isRecording ? 1.2 : 1.0)
                    .animation(
                        viewModel.isRecording
                            ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseAnimation
                    )

                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.indigo)
                    .frame(width: 80, height: 80)
                    .shadow(color: (viewModel.isRecording ? Color.red : Color.indigo).opacity(0.4), radius: 10)

                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
        }
        .onChange(of: viewModel.isRecording) { newValue in
            pulseAnimation = newValue
        }
    }

    private var transcriptionSection: some View {
        Group {
            if !viewModel.transcribedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcription", systemImage: "text.quote")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    Text(viewModel.transcribedText)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var parsedEventsSection: some View {
        Group {
            if !viewModel.parsedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Detected Events", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    ForEach(Array(viewModel.parsedEvents.enumerated()), id: \.offset) { index, event in
                        ParsedEventCard(
                            event: event,
                            onUpdate: { title, date, alarm in
                                viewModel.updateParsedEvent(at: index, title: title, date: date, hasAlarm: alarm)
                            },
                            onDelete: {
                                viewModel.removeParsedEvent(at: index)
                            }
                        )
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .foregroundStyle(viewModel.statusMessage.contains("Successfully") ? .green : .secondary)
                    .multilineTextAlignment(.center)
            }

            if !viewModel.parsedEvents.isEmpty {
                Button(action: {
                    Task { await viewModel.confirmAndSync() }
                }) {
                    HStack {
                        if viewModel.isProcessing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.isProcessing ? "Syncing..." : "Add to Calendar & Reminders")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.isProcessing)
            }

            if !viewModel.transcribedText.isEmpty || !viewModel.parsedEvents.isEmpty {
                Button("Reset", role: .destructive) {
                    viewModel.reset()
                }
                .font(.callout)
            }
        }
    }
}

struct ParsedEventCard: View {
    let event: ParsedEvent
    let onUpdate: (String?, Date?, Bool?) -> Void
    let onDelete: () -> Void

    @State private var editingTitle: String = ""
    @State private var editingDate: Date = Date()
    @State private var editingAlarm: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)

                    if let date = event.date {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(formatDate(date))
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if event.hasAlarm {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }

                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: "pencil.circle")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                    }

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
            }

            if isExpanded {
                Divider()

                TextField("Event title", text: $editingTitle)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { editingTitle = event.title }
                    .onChange(of: editingTitle) { newValue in
                        onUpdate(newValue, nil, nil)
                    }

                DatePicker("Date & Time", selection: $editingDate)
                    .onAppear { editingDate = event.date ?? Date() }
                    .onChange(of: editingDate) { newValue in
                        onUpdate(nil, newValue, nil)
                    }

                Toggle("Set Alarm", isOn: $editingAlarm)
                    .onAppear { editingAlarm = event.hasAlarm }
                    .onChange(of: editingAlarm) { newValue in
                        onUpdate(nil, nil, newValue)
                    }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
