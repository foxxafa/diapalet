// lib/core/services/pdf_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PdfService {
  static const String _companyName = 'ROWHUB Warehouse Management';
  
  /// Generates a PDF report for goods receipt operation
  static Future<Uint8List> generateGoodsReceiptPdf({
    required List<ReceiptItemDraft> items,
    required bool isOrderBased,
    PurchaseOrder? order,
    String? invoiceNumber,
    required String employeeName,
    required DateTime date,
  }) async {
    final pdf = pw.Document();
    
    // Load font for better text rendering
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    final title = isOrderBased 
        ? 'Order-based Goods Receipt'
        : 'Free Goods Receipt';
    
    // Calculate totals
    final totalItems = items.fold<int>(0, (sum, item) => sum + item.quantity.toInt());
    final uniqueProducts = items.map((item) => item.product.id).toSet().length;
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader(title, boldFont),
            
            pw.SizedBox(height: 20),
            
            // Info Section
            _buildInfoSection(
              isOrderBased: isOrderBased,
              order: order,
              invoiceNumber: invoiceNumber,
              employeeName: employeeName,
              date: date,
              font: font,
              boldFont: boldFont,
            ),
            
            pw.SizedBox(height: 20),
            
            // Summary Section
            _buildSummarySection(
              totalItems: totalItems,
              uniqueProducts: uniqueProducts,
              font: font,
              boldFont: boldFont,
            ),
            
            pw.SizedBox(height: 20),
            
            // Items Table
            _buildItemsTable(items, font, boldFont),
            
            pw.SizedBox(height: 30),
            
            // Footer
            _buildFooter(font),
          ];
        },
      ),
    );
    
    return pdf.save();
  }
  
  /// Generates a PDF report for pending operation
  static Future<Uint8List> generatePendingOperationPdf({
    required PendingOperation operation,
    Map<String, dynamic>? enrichedData,
  }) async {
    final pdf = pw.Document();
    
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader('Operation Details Report', boldFont),
            
            pw.SizedBox(height: 20),
            
            // Operation Info
            _buildOperationInfoSection(operation, font, boldFont),
            
            pw.SizedBox(height: 20),
            
            // Operation Data
            if (enrichedData != null)
              _buildOperationDataSection(enrichedData, operation.type, font, boldFont),
            
            pw.SizedBox(height: 30),
            
            // Footer
            _buildFooter(font),
          ];
        },
      ),
    );
    
    return pdf.save();
  }
  
  /// Shows a share dialog with options for WhatsApp, Telegram, etc.
  static Future<void> showShareDialog(
    context, 
    Uint8List pdfData, 
    String fileName,
  ) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _ShareBottomSheet(
          pdfData: pdfData,
          fileName: fileName,
        );
      },
    );
  }
  
  /// Saves PDF to device and optionally shares
  static Future<void> savePdfToDevice(Uint8List pdfData, String fileName) async {
    try {
      final output = await getApplicationDocumentsDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(pdfData);
      
      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Share PDF Report',
      );
    } catch (e) {
      throw Exception('Error saving PDF: $e');
    }
  }
  
  /// Previews PDF using printing package
  static Future<void> previewPdf(Uint8List pdfData) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfData,
    );
  }
  
  // Private helper methods
  
  static pw.Widget _buildHeader(String title, pw.Font boldFont) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _companyName,
          style: pw.TextStyle(font: boldFont, fontSize: 24, color: PdfColors.blue700),
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          width: double.infinity,
          height: 2,
          color: PdfColors.blue700,
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          title,
          style: pw.TextStyle(font: boldFont, fontSize: 18),
        ),
      ],
    );
  }
  
  static pw.Widget _buildInfoSection({
    required bool isOrderBased,
    PurchaseOrder? order,
    String? invoiceNumber,
    required String employeeName,
    required DateTime date,
    required pw.Font font,
    required pw.Font boldFont,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Employee', employeeName, font, boldFont),
          _buildInfoRow('Date', DateFormat('dd/MM/yyyy HH:mm').format(date), font, boldFont),
          if (isOrderBased && order != null) ...[
            _buildInfoRow('Purchase Order', order.poId ?? 'N/A', font, boldFont),
            if (invoiceNumber != null && invoiceNumber.isNotEmpty)
              _buildInfoRow('Invoice Number', invoiceNumber, font, boldFont),
          ],
        ],
      ),
    );
  }
  
  static pw.Widget _buildSummarySection({
    required int totalItems,
    required int uniqueProducts,
    required pw.Font font,
    required pw.Font boldFont,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Summary',
            style: pw.TextStyle(font: boldFont, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          _buildInfoRow('Total Items', totalItems.toString(), font, boldFont),
          _buildInfoRow('Unique Products', uniqueProducts.toString(), font, boldFont),
        ],
      ),
    );
  }
  
  static pw.Widget _buildItemsTable(List<ReceiptItemDraft> items, pw.Font font, pw.Font boldFont) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Items List',
          style: pw.TextStyle(font: boldFont, fontSize: 14),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell('Product', boldFont, isHeader: true),
                _buildTableCell('Quantity', boldFont, isHeader: true),
                _buildTableCell('Type', boldFont, isHeader: true),
              ],
            ),
            // Data rows
            ...items.map((item) => pw.TableRow(
              children: [
                _buildTableCell('${item.product.name} (${item.product.stockCode})', font),
                _buildTableCell(item.quantity.toStringAsFixed(0), font),
                _buildTableCell(
                  item.palletBarcode != null 
                      ? 'Pallet: ${item.palletBarcode}'
                      : 'Box Mode',
                  font,
                ),
              ],
            )),
          ],
        ),
      ],
    );
  }
  
  static pw.Widget _buildOperationInfoSection(PendingOperation operation, pw.Font font, pw.Font boldFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Operation Type', operation.displayTitle, font, boldFont),
          _buildInfoRow('Created at', DateFormat('dd/MM/yyyy HH:mm').format(operation.createdAt), font, boldFont),
          _buildInfoRow('Status', operation.status, font, boldFont),
          if (operation.errorMessage != null && operation.errorMessage!.isNotEmpty)
            _buildInfoRow('Error Details', operation.errorMessage!, font, boldFont),
        ],
      ),
    );
  }
  
  static pw.Widget _buildOperationDataSection(
    Map<String, dynamic> data, 
    PendingOperationType type, 
    pw.Font font, 
    pw.Font boldFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Operation Data',
          style: pw.TextStyle(font: boldFont, fontSize: 14),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          ),
          child: pw.Text(
            _formatOperationData(data, type),
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
        ),
      ],
    );
  }
  
  static pw.Widget _buildInfoRow(String label, String value, pw.Font font, pw.Font boldFont) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(font: boldFont, fontSize: 11),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: font, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
  
  static pw.Widget _buildTableCell(String text, pw.Font font, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
  
  static pw.Widget _buildFooter(pw.Font font) {
    return pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          height: 1,
          color: PdfColors.grey400,
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          '${'pdf_report.goods_receipt.generated_at'.tr()}: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    );
  }
  
  static String _formatOperationData(Map<String, dynamic> data, PendingOperationType type) {
    // Simple JSON formatting for operation data
    final buffer = StringBuffer();
    data.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }
}

class _ShareBottomSheet extends StatelessWidget {
  final Uint8List pdfData;
  final String fileName;
  
  const _ShareBottomSheet({
    required this.pdfData,
    required this.fileName,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'pdf_report.share_dialog.title'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                
                // Share options grid
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _ShareOption(
                      icon: Icons.preview,
                      label: 'pdf_report.actions.preview'.tr(),
                      onTap: () async {
                        Navigator.pop(context);
                        await PdfService.previewPdf(pdfData);
                      },
                    ),
                    _ShareOption(
                      icon: Icons.file_download,
                      label: 'pdf_report.share_dialog.save_to_device'.tr(),
                      onTap: () async {
                        Navigator.pop(context);
                        await PdfService.savePdfToDevice(pdfData, fileName);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('pdf_report.actions.file_saved'.tr())),
                          );
                        }
                      },
                    ),
                    _ShareOption(
                      icon: Icons.share,
                      label: 'pdf_report.share_dialog.other'.tr(),
                      onTap: () async {
                        Navigator.pop(context);
                        await PdfService.savePdfToDevice(pdfData, fileName);
                      },
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('common_labels.close'.tr()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
} 