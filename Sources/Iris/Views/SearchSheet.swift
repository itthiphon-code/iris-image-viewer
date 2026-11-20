import SwiftUI

/// หน้าต่างค้นหาขั้นสูง (กล้อง เลนส์ วันที่ ISO ดาว ป้าย ชนิดไฟล์) รวมโฟลเดอร์ย่อย
struct SearchSheet: View {
    @Environment(BrowserModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var criteria = SearchCriteria()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ค้นหาขั้นสูง").font(.title3.weight(.semibold))
                    Text("ใน \(model.searchRootName)").foregroundStyle(.secondary)
                }
            }

            Form {
                Section {
                    Toggle("รวมโฟลเดอร์ย่อยทั้งหมด", isOn: $criteria.includeSubfolders)
                    TextField("ชื่อไฟล์มีคำว่า", text: $criteria.name)
                    Picker("ชนิดไฟล์", selection: $criteria.format) {
                        ForEach(SearchCriteria.FormatFilter.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("กล้องและการถ่าย") {
                    TextField("กล้อง", text: $criteria.camera, prompt: Text("เช่น Canon, R6, Z 6"))
                    TextField("เลนส์", text: $criteria.lens, prompt: Text("เช่น 50mm, 24-70"))
                    Toggle("ช่วงวันที่ถ่าย", isOn: $criteria.useDateRange)
                    if criteria.useDateRange {
                        DatePicker("ตั้งแต่", selection: $criteria.dateFrom, displayedComponents: .date)
                        DatePicker("ถึง", selection: $criteria.dateTo, displayedComponents: .date)
                    }
                    Toggle("ช่วง ISO", isOn: $criteria.useISO)
                    if criteria.useISO {
                        HStack {
                            TextField("ต่ำสุด", value: $criteria.isoMin, format: .number)
                            Text("ถึง")
                            TextField("สูงสุด", value: $criteria.isoMax, format: .number)
                        }
                    }
                }

                Section("การจัดระดับ") {
                    Picker("คะแนนดาว", selection: $criteria.minRating) {
                        Text("ไม่กำหนด").tag(0)
                        ForEach(1...5, id: \.self) { n in
                            Text(String(repeating: "★", count: n) + (n < 5 ? " ขึ้นไป" : "")).tag(n)
                        }
                    }
                    Picker("ป้ายสี", selection: $criteria.label) {
                        Text("ไม่กำหนด").tag(ColorLabel?.none)
                        ForEach(ColorLabel.allCases.filter { $0 != .none }) { label in
                            Text(label.title).tag(ColorLabel?.some(label))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 440)

            if criteria.needsEXIF {
                Label("ต้องอ่าน EXIF ทุกไฟล์ อาจใช้เวลาสักครู่ถ้ามีรูปจำนวนมาก (กดหยุดได้)", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("ล้างเงื่อนไข") { criteria = SearchCriteria() }
                Spacer()
                Button("ยกเลิก", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("ค้นหา") {
                    let c = criteria
                    dismiss()
                    model.runSearch(c)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if let last = model.lastSearch { criteria = last }
        }
    }
}
