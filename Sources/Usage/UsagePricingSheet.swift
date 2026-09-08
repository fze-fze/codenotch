import SwiftUI

struct UsagePricingSheet: View {
    let model: UsageDashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ""
    @State private var price = ModelTokenPrice()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model prices").font(PanelFont.title)
            Text("USD per 1 million tokens. Estimates use standard short-context text prices, excluding premium tiers, tools, storage, and subscription fees. Custom prices apply to all recorded history.")
                .font(PanelFont.note).foregroundStyle(.secondary)
            if model.lifetime.models.isEmpty {
                ContentUnavailableView("No models yet", systemImage: "dollarsign.circle",
                                       description: Text("Import local usage before setting model prices."))
            } else {
                Form {
                    Picker("Model", selection: $selected) {
                        ForEach(model.lifetime.models) { row in Text(row.id).tag(row.id) }
                    }
                    TextField("Input", value: $price.input, format: .number)
                    TextField("Cache read", value: $price.cached, format: .number)
                    TextField("Output (including reasoning)", value: $price.output, format: .number)
                    TextField("Cache write / 5 min", value: $price.cacheWrite, format: .number)
                    TextField("Cache write / 1 hour", value: $price.cacheWriteLong, format: .number)
                }
                .textFieldStyle(.roundedBorder)
                Text(model.prices[selected] == nil ? "Not priced. Enter rates and save to include this model in cost estimates." : "Current price is available. Save to override it, or restore the reference price.")
                    .font(PanelFont.note).foregroundStyle(.secondary)
                if !price.isValid {
                    Text("Enter finite, nonnegative prices up to $1,000,000.").foregroundStyle(.red)
                }
            }
            HStack {
                Link("OpenAI rates", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                Link("Gemini rates", destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
                Spacer()
                Text("Reference: Sep 8, 2026").foregroundStyle(.secondary)
            }
            .font(PanelFont.note)
            Divider()
            HStack {
                Button("Restore reference") {
                    model.resetPrice(model: selected)
                    loadPrice()
                }
                .disabled(selected.isEmpty)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save price") {
                    model.savePrice(model: selected, price: price)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || !price.isValid)
            }
        }
        .padding(24)
        .frame(width: 570)
        .onAppear {
            selected = model.lifetime.models.first?.id ?? ""
            loadPrice()
        }
        .onChange(of: selected) { loadPrice() }
    }

    private func loadPrice() { price = model.prices[selected] ?? ModelTokenPrice() }
}
