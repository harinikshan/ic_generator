import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Model for a single row of patient data.
class PatientData {
  final String patientName;
  final String department;
  final double ic;
  final DateTime billDate;

  PatientData({
    required this.patientName,
    required this.department,
    required this.ic,
    required this.billDate,
  });
}

/// Model for a doctor and all associated patients.
class DoctorData {
  final String doctorName;
  final List<PatientData> patients;

  DoctorData({
    required this.doctorName,
    required this.patients,
  });
}

/// Parses the Excel file into a list of [DoctorData].
/// Excel columns (in order):
///   0: S.No
///   1: Doctor
///   2: Patient Name
///   3: Department
///   4: Service Name
///   5: Price
///   6: Discount
///   7: Total
///   8: IC
///   9: Bill Date
Future<List<DoctorData>> parseExcelFile(Uint8List fileBytes) async {
  var excel = Excel.decodeBytes(fileBytes);
  var sheet = excel.sheets.values.first;

  bool isHeader = true;
  Map<String, List<PatientData>> doctorMap = {};

  for (var row in sheet.rows) {
    // Skip header row
    if (isHeader) {
      isHeader = false;
      continue;
    }
    if (row.isEmpty) continue;

    // Adjust indexes if your columns differ
    final doctorCell = row[1];
    final patientNameCell = row[2];
    final departmentCell = row[3];
    final icCell = row[8];
    final billDateCell = (row.length > 9) ? row[9] : null;

    // Skip row if critical cells are missing
    if (doctorCell == null ||
        patientNameCell == null ||
        departmentCell == null ||
        icCell == null ||
        billDateCell == null) {
      continue;
    }

    // Doctor name
    final doctorName = doctorCell.value.toString().trim();
    // Patient name
    final patientName = patientNameCell.value.toString().trim();
    // Department
    final department = departmentCell.value.toString().trim();
    // IC
    final ic = double.tryParse(icCell.value.toString()) ?? 0.0;

    // Bill date (try dd/MM/yy, fallback dd/MM/yyyy)
    DateTime billDate;
    if (billDateCell.value is DateTime) {
      billDate = billDateCell.value;
    } else {
      String rawDate = billDateCell.value.toString().trim();
      try {
        billDate = DateFormat('dd/MM/yy').parse(rawDate);
      } catch (_) {
        try {
          billDate = DateFormat('dd/MM/yyyy').parse(rawDate);
        } catch (e) {
          billDate = DateTime.now();
        }
      }
    }

    // Create patient object
    final patient = PatientData(
      patientName: patientName,
      department: department,
      ic: ic,
      billDate: billDate,
    );

    // Insert into map
    doctorMap.putIfAbsent(doctorName, () => []);
    doctorMap[doctorName]!.add(patient);
  }

  // Convert map to list
  List<DoctorData> doctors = [];
  doctorMap.forEach((docName, patients) {
    doctors.add(DoctorData(doctorName: docName, patients: patients));
  });

  return doctors;
}

/// Builds the PDF content for a single doctor, half-page style.
/// If <=9 patients => full table, else summary.
pw.Widget buildDoctorPdfBlock(DoctorData doctor) {
  final patients = doctor.patients;
  final totalIC = patients.fold<double>(0.0, (sum, p) => sum + p.ic);
  final mriCount = patients.where((p) => p.department == "MRI").length;
  final ctCount = patients.where((p) => p.department == "CT").length;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Doctor label
      pw.Row(
        children: [
          pw.Text("Doctor: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(doctor.doctorName),
        ],
      ),
      pw.SizedBox(height: 8),
      if (patients.length <= 9)
        _buildPdfPatientTable(patients)
      else
        _buildPdfSummaryBlock(
          patientCount: patients.length,
          mriCount: mriCount,
          ctCount: ctCount,
          totalIC: totalIC,
        ),
      pw.SizedBox(height: 16),
      // Total row
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            "TOTAL (INR) ${totalIC.toStringAsFixed(2)}",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      // Signatures
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text("Prepared by"),
          pw.Text("Receiver's Sign"),
        ],
      ),
    ],
  );
}

/// If <=9 patients, build a detailed table.
pw.Widget _buildPdfPatientTable(List<PatientData> patients) {
  return pw.Table(
    border: pw.TableBorder.all(),
    columnWidths: {
      0: const pw.FlexColumnWidth(2), // Patient Name
      1: const pw.FlexColumnWidth(2), // Department
      2: const pw.FlexColumnWidth(2), // Bill Date
      3: const pw.FlexColumnWidth(1), // IC
    },
    children: [
      // Header
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text("Patient Name",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text("Department",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text("Bill Date",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text("IC",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right),
          ),
        ],
      ),
      // Rows
      for (final p in patients)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(p.patientName),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(p.department),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(DateFormat('dd/MM/yy').format(p.billDate)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(
                p.ic.toStringAsFixed(2),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
    ],
  );
}

/// If >9 patients, build a summary only.
pw.Widget _buildPdfSummaryBlock({
  required int patientCount,
  required int mriCount,
  required int ctCount,
  required double totalIC,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        "Patient List Exceeds 9. Showing Summary Only:",
        style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
      ),
      pw.SizedBox(height: 8),
      pw.Text("Total Patients: $patientCount"),
      pw.Text("MRI Count: $mriCount"),
      pw.Text("CT Count: $ctCount"),
      pw.Text("Total IC: ${totalIC.toStringAsFixed(2)}"),
    ],
  );
}

/// Builds a Flutter UI preview block for a single doctor,
/// side by side in the main screen. Same logic: if <=9 patients => table, else summary.
Widget buildDoctorPreviewUI(DoctorData doctor) {
  final patients = doctor.patients;
  final totalIC = patients.fold<double>(0.0, (sum, p) => sum + p.ic);
  final mriCount = patients.where((p) => p.department == "MRI").length;
  final ctCount = patients.where((p) => p.department == "CT").length;

  return Card(
    elevation: 4,
    margin: const EdgeInsets.all(8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doctor name
          Text(
            "Doctor: ${doctor.doctorName}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          if (patients.length <= 9)
            _buildPreviewPatientTable(doctor.patients)
          else
            _buildPreviewSummaryBlock(
              patientCount: patients.length,
              mriCount: mriCount,
              ctCount: ctCount,
              totalIC: totalIC,
            ),
          const SizedBox(height: 12),
          // Total row
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "TOTAL (INR) ${totalIC.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          // Signatures
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("Prepared by"),
              Text("Receiver's Sign"),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Detailed table in the Flutter UI if <=9 patients
Widget _buildPreviewPatientTable(List<PatientData> patients) {
  return Table(
    border: TableBorder.all(color: Colors.grey.shade300),
    columnWidths: const {
      0: FlexColumnWidth(2), // Patient Name
      1: FlexColumnWidth(2), // Department
      2: FlexColumnWidth(2), // Bill Date
      3: FlexColumnWidth(1), // IC
    },
    children: [
      // Header
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade200),
        children: const [
          Padding(
            padding: EdgeInsets.all(4),
            child: Text("Patient Name", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(4),
            child: Text("Department", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(4),
            child: Text("Bill Date", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(4),
            child: Text("IC", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      // Rows
      for (final p in patients)
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(p.patientName),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(p.department),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(DateFormat('dd/MM/yy').format(p.billDate)),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(p.ic.toStringAsFixed(2)),
            ),
          ],
        ),
    ],
  );
}

/// Summary-only Flutter UI if >9 patients
Widget _buildPreviewSummaryBlock({
  required int patientCount,
  required int mriCount,
  required int ctCount,
  required double totalIC,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Patient List Exceeds 9. Showing Summary Only:",
        style: TextStyle(fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 8),
      Text("Total Patients: $patientCount"),
      Text("MRI Count: $mriCount"),
      Text("CT Count: $ctCount"),
      Text("Total IC: ${totalIC.toStringAsFixed(2)}"),
    ],
  );
}

/// Generates a single PDF page with two half-page blocks side by side
/// if both doctors are selected. If only one is selected, it takes the full page.
Future<void> generatePdfForTwoDoctors(
    DoctorData? doctorA,
    DoctorData? doctorB,
    ) async {
  if (doctorA == null && doctorB == null) return;

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) {
        final selected = <DoctorData>[];
        if (doctorA != null) selected.add(doctorA);
        if (doctorB != null) selected.add(doctorB);

        if (selected.isEmpty) {
          // Edge case: no doctors at all
          return pw.Center(child: pw.Text("No doctors selected."));
        } else if (selected.length == 1) {
          // Only one doctor => take the full page
          return buildDoctorPdfBlock(selected[0]);
        } else {
          // Two doctors => side by side, each half page
          return pw.Column(
            children: [
              pw.Expanded(child: buildDoctorPdfBlock(selected[0])),
              pw.SizedBox(height: 10),
              pw.Expanded(child: buildDoctorPdfBlock(selected[1])),
            ],
          );
        }
      },
    ),
  );

  // Show the print/save dialog
  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
  );
}

/// Main widget: pick Excel, select two doctors, show UI preview, and print PDF.
class TwoDoctorExcelDemo extends StatefulWidget {
  const TwoDoctorExcelDemo({Key? key}) : super(key: key);

  @override
  State<TwoDoctorExcelDemo> createState() => _TwoDoctorExcelDemoState();
}

class _TwoDoctorExcelDemoState extends State<TwoDoctorExcelDemo> {
  List<DoctorData> allDoctors = [];
  DoctorData? selectedDoctorA;
  DoctorData? selectedDoctorB;

  /// Pick and parse Excel
  Future<void> pickAndProcessExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result != null && result.files.isNotEmpty) {
      Uint8List? fileBytes = result.files.first.bytes;
      if (fileBytes != null) {
        final parsedDoctors = await parseExcelFile(fileBytes);
        setState(() {
          allDoctors = parsedDoctors;
          selectedDoctorA = null;
          selectedDoctorB = null;
        });
      }
    }
  }

  /// Print/Save PDF for the two selected doctors
  Future<void> onPrintPdf() async {
    await generatePdfForTwoDoctors(selectedDoctorA, selectedDoctorB);
  }

  @override
  Widget build(BuildContext context) {
    // Sort for nicer dropdown listing
    allDoctors.sort((a, b) => a.doctorName.compareTo(b.doctorName));

    return Scaffold(
      appBar: AppBar(
        title: const Text("IC Generator"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: allDoctors.isEmpty
            ? Center(
          child: ElevatedButton(
            onPressed: pickAndProcessExcel,
            child: const Text("Select Excel File"),
          ),
        )
            : Column(
          children: [
            // Upload new Excel
            Row(
              children: [
                ElevatedButton(
                  onPressed: pickAndProcessExcel,
                  child: const Text("Upload New Excel File"),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: (selectedDoctorA != null || selectedDoctorB != null)
                      ? onPrintPdf
                      : null,
                  child: const Text("Print/Save PDF"),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Doctor A dropdown
            Align(
              alignment: Alignment.centerLeft,
              child: const Text("Select Doctor A:"),
            ),
            DropdownButton<DoctorData>(
              isExpanded: true,
              value: selectedDoctorA,
              hint: const Text("Choose Doctor A"),
              items: allDoctors.map((doctor) {
                return DropdownMenuItem<DoctorData>(
                  value: doctor,
                  child: Text(doctor.doctorName),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedDoctorA = value;
                  // If B is the same as A, reset B
                  if (selectedDoctorB == value) {
                    selectedDoctorB = null;
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            // Doctor B dropdown
            Align(
              alignment: Alignment.centerLeft,
              child: const Text("Select Doctor B:"),
            ),
            DropdownButton<DoctorData>(
              isExpanded: true,
              value: selectedDoctorB,
              hint: const Text("Choose Doctor B"),
              items: allDoctors
                  .where((doc) => doc != selectedDoctorA)
                  .map((doctor) {
                return DropdownMenuItem<DoctorData>(
                  value: doctor,
                  child: Text(doctor.doctorName),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedDoctorB = value;
                });
              },
            ),
            const SizedBox(height: 24),
            // Show side-by-side UI preview if both are selected,
            // or single preview if only one is selected.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedDoctorA != null)
                    Expanded(
                      child: SingleChildScrollView(
                        child: buildDoctorPreviewUI(selectedDoctorA!),
                      ),
                    ),
                  if (selectedDoctorA != null && selectedDoctorB != null)
                    const SizedBox(width: 16),
                  if (selectedDoctorB != null)
                    Expanded(
                      child: SingleChildScrollView(
                        child: buildDoctorPreviewUI(selectedDoctorB!),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(
    MaterialApp(
      home: const TwoDoctorExcelDemo(),
      debugShowCheckedModeBanner: false,
    ),
  );
}
