import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var state: PanelState
    @EnvironmentObject private var settings: AppSettings

    private let swatches: [String?] = [nil, "#FFFFFF", "#1C1C1E", "#FFD60A", "#FF375F", "#BF5AF2", "#0A84FF", "#30D158"]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        PanelScaffold {
            CircleButton(systemName: "chevron.left", help: "กลับ (Esc)") {
                state.isShowingSettings = false
            }
            .padding(.leading, -6)
            Text("ตั้งค่า")
                .font(.system(size: 18, weight: .bold))
            Spacer()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appearanceSection
                    panelSection
                    shortcutSection
                    generalSection
                }
                .padding(14)
            }
        } toolbar: {
            PinButton()
            Spacer()
            Text("My SideNotes \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            CircleButton(systemName: "xmark", size: 30, help: "ปิดการตั้งค่า") {
                state.isShowingSettings = false
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        SettingsSection("รูปลักษณ์") {
            SettingsRow("โหมดสี") {
                SegmentedPicker(selection: $settings.prefs.appearance)
            }
            if #available(macOS 26.0, *) {
                SettingsRow("สไตล์กระจก") {
                    SegmentedPicker(selection: $settings.prefs.glassStyle)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("สีพื้นหลัง")
                    .font(.system(size: 13))
                colorSwatches
            }
            SliderRow(title: "ความเข้มของสี", value: $settings.prefs.tintOpacity, range: 0.05...0.95)
                .disabled(settings.prefs.tintHex == nil)
                .opacity(settings.prefs.tintHex == nil ? 0.5 : 1)
            SliderRow(title: "ความทึบของแผง", value: $settings.prefs.panelOpacity, range: 0.4...1)
        }
    }

    private var panelSection: some View {
        SettingsSection("แผง") {
            SettingsRow("ตำแหน่ง") {
                SegmentedPicker(selection: $settings.prefs.panelEdge)
            }
            SettingsRow("แสดงแถบที่ขอบจอ") {
                Toggle("", isOn: $settings.prefs.showsEdgeHandle)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            SettingsRow("เรียงโน้ต") {
                SegmentedPicker(selection: $settings.prefs.noteSort)
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection("คีย์ลัด") {
            SettingsRow("เปิด/ปิดแผง") {
                ShortcutRecorder(
                    shortcut: $settings.prefs.toggleShortcut,
                    failed: state.failedHotKeyIDs.contains(HotKeyID.toggle)
                )
            }
            SettingsRow("จดโน้ตด่วน") {
                ShortcutRecorder(
                    shortcut: $settings.prefs.quickNoteShortcut,
                    failed: state.failedHotKeyIDs.contains(HotKeyID.quickNote)
                )
            }
            SettingsRow("จดด่วนลงโฟลเดอร์") {
                Picker("", selection: $settings.prefs.quickNoteFolderID) {
                    Text("ที่เปิดอยู่").tag(UUID?.none)
                    ForEach(store.folders) { folder in
                        Text(folder.name).tag(UUID?.some(folder.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var generalSection: some View {
        SettingsSection("ทั่วไป") {
            SettingsRow("เปิดอัตโนมัติเมื่อเข้าสู่ระบบ") {
                Toggle("", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            HStack {
                Button("เปิดโฟลเดอร์เก็บข้อมูล") { state.revealDataFile() }
                Spacer()
                Button("ออกจากแอป", role: .destructive) { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }

    // MARK: Colors

    private var colorSwatches: some View {
        HStack(spacing: 5) {
            ForEach(swatches, id: \.self) { hex in
                Button {
                    settings.prefs.tintHex = hex
                } label: {
                    swatch(hex)
                }
                .buttonStyle(.plain)
                .help(hex == nil ? "ไม่มีสี (ตามระบบ)" : hex ?? "")
            }
            ColorPicker("", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .help("เลือกสีเอง")
        }
    }

    private func swatch(_ hex: String?) -> some View {
        let isSelected = settings.prefs.tintHex == hex
        return ZStack {
            if let hex, let color = NSColor(hex: hex) {
                Circle().fill(Color(nsColor: color))
            } else {
                Circle().fill(Color.primary.opacity(0.04))
                Image(systemName: "nosign")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
        .padding(2)
        .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
    }

    private var customColor: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: settings.prefs.tintHex.flatMap(NSColor.init(hex:)) ?? .white)
            },
            set: { settings.prefs.tintHex = NSColor($0).hexString }
        )
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            control
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

private struct SegmentedPicker<Option: TitledOption>: View where Option.AllCases: RandomAccessCollection {
    @Binding var selection: Option

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Option.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Shortcut recorder

final class ShortcutRecorderModel: ObservableObject {
    @Published var isRecording = false
    var monitor: Any?
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var failed = false

    @EnvironmentObject private var state: PanelState
    @StateObject private var model = ShortcutRecorderModel()

    var body: some View {
        HStack(spacing: 6) {
            if failed, !model.isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("ใช้คีย์ลัดนี้ไม่ได้ อาจซ้ำกับแอปอื่นหรือคีย์ลัดอีกตัว")
            }
            Button(action: toggleRecording) {
                Text(model.isRecording ? "กดคีย์ลัด…" : shortcut.display)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 76)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(model.isRecording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        Capsule().strokeBorder(model.isRecording ? Color.accentColor : Color.primary.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .help(model.isRecording ? "กด Esc เพื่อยกเลิก" : "คลิกแล้วกดคีย์ลัดใหม่")
        }
        .onDisappear(perform: stop)
    }

    private func toggleRecording() {
        model.isRecording ? stop() : start()
    }

    private func start() {
        model.isRecording = true
        state.isRecordingShortcut = true
        model.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor = model.monitor {
            NSEvent.removeMonitor(monitor)
        }
        model.monitor = nil
        if model.isRecording {
            model.isRecording = false
            state.isRecordingShortcut = false
        }
    }
}
