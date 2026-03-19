import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import 'local_database_service.dart';

/// Servicio para generar el historial académico en PDF
class AcademicHistoryPdf {
  static Future<void> generateAndShare(BuildContext context) async {
    final db = LocalDatabaseService.instance;
    final user = db.getCurrentUser();
    if (user == null) return;

    final semesters = db.getSemesters(user.uid, includeArchived: true);
    if (semesters.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay semestres para exportar')),
        );
      }
      return;
    }

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy');
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Colors
    const headerColor = PdfColor.fromInt(0xFF6B7FD7);
    const passColor = PdfColor.fromInt(0xFF4CAF50);
    const failColor = PdfColor.fromInt(0xFFEF5350);

    // Gather all data
    int totalSubjects = 0;
    int passedSubjects = 0;
    int failedSubjects = 0;
    int ungradedSubjects = 0;
    double sumGrades = 0;
    int gradedCount = 0;
    int totalCredits = 0;
    int earnedCredits = 0;

    final semesterData = <_SemesterData>[];

    for (final semester in semesters) {
      final subjects = db.getSubjects(semester.syncId);
      final subjectRows = <_SubjectRow>[];

      double semesterSum = 0;
      int semesterGraded = 0;

      for (final subject in subjects) {
        final periods = db.getGradePeriods(subject.syncId);
        double? finalGrade;

        if (periods.isNotEmpty) {
          double totalEarned = 0;
          double totalPercentage = 0;
          bool hasAnyGrade = false;

          for (final period in periods) {
            final grade = period.computedGrade;
            if (grade != null) {
              totalEarned += grade * (period.percentage / 100.0);
              totalPercentage += period.percentage;
              hasAnyGrade = true;
            }
          }

          if (hasAnyGrade && totalPercentage > 0) {
            finalGrade = (totalEarned / totalPercentage) * 100;
            // Scale to 0-5 range (Colombian grading)
            finalGrade = totalEarned / 20.0; // percentage earned → 0-5
            // Actually, just use the weighted sum directly
            finalGrade = totalEarned;
          }
        }

        String status;
        if (finalGrade == null) {
          status = 'Sin calificar';
          ungradedSubjects++;
        } else if (finalGrade >= subject.passingGrade) {
          status = 'Aprobada';
          passedSubjects++;
          earnedCredits += subject.credits ?? 0;
        } else {
          status = 'Reprobada';
          failedSubjects++;
        }

        if (finalGrade != null) {
          sumGrades += finalGrade;
          gradedCount++;
          semesterSum += finalGrade;
          semesterGraded++;
        }

        totalSubjects++;
        totalCredits += subject.credits ?? 0;

        subjectRows.add(
          _SubjectRow(
            name: subject.name,
            professor: subject.professor ?? '',
            credits: subject.credits ?? 0,
            finalGrade: finalGrade,
            passingGrade: subject.passingGrade,
            status: status,
          ),
        );
      }

      semesterData.add(
        _SemesterData(
          semester: semester,
          subjects: subjectRows,
          average: semesterGraded > 0 ? semesterSum / semesterGraded : null,
        ),
      );
    }

    final cumulativeAvg = gradedCount > 0 ? sumGrades / gradedCount : null;

    // ---- Build PDF ----
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildHeader(user, now, headerColor),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Elaborado por UniCal - ${user.name}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
              pw.Text(
                'Página ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          // ---- Stats Summary ----
          _buildStatsBox(
            totalSubjects: totalSubjects,
            passedSubjects: passedSubjects,
            failedSubjects: failedSubjects,
            ungradedSubjects: ungradedSubjects,
            cumulativeAvg: cumulativeAvg,
            totalCredits: totalCredits,
            earnedCredits: earnedCredits,
            headerColor: headerColor,
            passColor: passColor,
            failColor: failColor,
          ),

          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'EL PRESENTE REPORTE NO CONSTITUYE UNA CERTIFICACIÓN DE NOTAS.',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.SizedBox(height: 20),

          // ---- Per-Semester Tables ----
          ...semesterData.map(
            (sd) => _buildSemesterSection(
              sd,
              dateFormat,
              headerColor,
              passColor,
              failColor,
            ),
          ),
        ],
      ),
    );

    // Share/print
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => pdf.save(),
      name: 'historial_academico_unical.pdf',
    );
  }

  static pw.Widget _buildHeader(
    UserModel user,
    String date,
    PdfColor headerColor,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: headerColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Historial Académico',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                user.name,
                style: const pw.TextStyle(fontSize: 13, color: PdfColors.white),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'UniCal',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generado: $date',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStatsBox({
    required int totalSubjects,
    required int passedSubjects,
    required int failedSubjects,
    required int ungradedSubjects,
    required double? cumulativeAvg,
    required int totalCredits,
    required int earnedCredits,
    required PdfColor headerColor,
    required PdfColor passColor,
    required PdfColor failColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Resumen General',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: headerColor,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _statItem('Total Materias', '$totalSubjects', headerColor),
              _statItem('Aprobadas', '$passedSubjects', passColor),
              _statItem('Reprobadas', '$failedSubjects', failColor),
              _statItem(
                'Sin Calificar',
                '$ungradedSubjects',
                PdfColors.grey600,
              ),
              _statItem(
                'Promedio',
                cumulativeAvg != null
                    ? cumulativeAvg.toStringAsFixed(2)
                    : 'N/A',
                headerColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _statItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  static pw.Widget _buildSemesterSection(
    _SemesterData data,
    DateFormat dateFormat,
    PdfColor headerColor,
    PdfColor passColor,
    PdfColor failColor,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Semester header
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: headerColor,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                data.semester.name,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                '${dateFormat.format(data.semester.startDate)} — ${dateFormat.format(data.semester.endDate)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),

        // Subjects table
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FixedColumnWidth(50),
            3: const pw.FixedColumnWidth(55),
            4: const pw.FixedColumnWidth(65),
          },
          children: [
            // Table header
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F5F5),
              ),
              children: [
                _tableHeader('Materia'),
                _tableHeader('Profesor'),
                _tableHeader('Créditos'),
                _tableHeader('Nota'),
                _tableHeader('Estado'),
              ],
            ),
            // Rows
            ...data.subjects.map(
              (s) => pw.TableRow(
                children: [
                  _tableCell(s.name),
                  _tableCell(s.professor),
                  _tableCell(
                    s.credits > 0 ? '${s.credits}' : '-',
                    align: pw.TextAlign.center,
                  ),
                  _tableCell(
                    s.finalGrade != null
                        ? s.finalGrade!.toStringAsFixed(2)
                        : '-',
                    align: pw.TextAlign.center,
                    color: s.finalGrade != null
                        ? (s.finalGrade! >= s.passingGrade
                              ? passColor
                              : failColor)
                        : PdfColors.grey600,
                  ),
                  _tableCell(
                    s.status,
                    align: pw.TextAlign.center,
                    color: s.status == 'Aprobada'
                        ? passColor
                        : s.status == 'Reprobada'
                        ? failColor
                        : PdfColors.grey600,
                  ),
                ],
              ),
            ),
          ],
        ),

        // Semester average
        if (data.average != null)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF5F5F5),
              borderRadius: pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(6),
                bottomRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(
              'Promedio del semestre: ${data.average!.toStringAsFixed(2)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),

        pw.SizedBox(height: 16),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: 9, color: color),
      ),
    );
  }
}

// ---- Helper data classes ----

class _SemesterData {
  final SemesterModel semester;
  final List<_SubjectRow> subjects;
  final double? average;

  _SemesterData({
    required this.semester,
    required this.subjects,
    required this.average,
  });
}

class _SubjectRow {
  final String name;
  final String professor;
  final int credits;
  final double? finalGrade;
  final double passingGrade;
  final String status;

  _SubjectRow({
    required this.name,
    required this.professor,
    required this.credits,
    required this.finalGrade,
    required this.passingGrade,
    required this.status,
  });
}
