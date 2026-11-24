// SplatNative - Components.swift
import SwiftUI

struct CategoryLabel: View {
    let title: String
    let icon: String
    let color: Color
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: iconSize * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous))
            Text(title)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        24
        #else
        30
        #endif
    }
}

/// A settings page pushed from the launcher's list.
struct CategoryPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.headline)
                HStack {
                    Button { dismiss() } label: { Label("Back", systemImage: "chevron.left") }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Form { content }.formStyle(.grouped)
        }
        .navigationBarBackButtonHidden()
        #else
        Form { content }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct CheckRow: View {
    let title: String
    let ok: Bool
    let optional: Bool
    let detail: String

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : optional ? "minus.circle" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : optional ? .secondary : .red)
            Text(title)
            Spacer()
            Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
    }
}

func labeled(_ title: String, _ detail: String?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
    }
}

struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text("\(Int((value * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
