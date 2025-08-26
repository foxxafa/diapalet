// lib/core/services/pdf_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class PdfService {
  static const String _companyName = 'ROWHUB Warehouse Management';

  /// Generates an enriched filename for PDF export using enriched data
  static Future<String> generateEnrichedPdfFileName(PendingOperation operation) async {
    final effectiveDate = operation.syncedAt ?? operation.createdAt;
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(effectiveDate);
    final typeName = operation.displayTitle.replaceAll(' ', '');

    String identifier = '';

    try {
      switch (operation.type) {
        case PendingOperationType.goodsReceipt:
          final enrichedData = await DatabaseHelper.instance.getEnrichedGoodsReceiptData(
            operation.data,
            operationDate: operation.createdAt,
          );
          final header = enrichedData['header'] as Map<String, dynamic>? ?? {};
          final orderInfo = header['order_info'] as Map<String, dynamic>?;
          identifier = orderInfo?['fisno']?.toString() ?? header['fisno']?.toString() ?? header['po_id']?.toString() ?? '';
          break;
        case PendingOperationType.inventoryTransfer:
          final enrichedData = await DatabaseHelper.instance.getEnrichedInventoryTransferData(operation.data);
          final header = enrichedData['header'] as Map<String, dynamic>? ?? {};
          identifier = header['po_id']?.toString() ?? header['container_id']?.toString() ?? '';
          break;
        case PendingOperationType.forceCloseOrder:
          final dataMap = jsonDecode(operation.data);
          identifier = dataMap['po_id']?.toString() ?? '';
          break;
      }
    } catch (e) {
      debugPrint('Error generating enriched PDF filename: $e');
      // Fallback to original method
      return operation.pdfFileName;
    }

    if (identifier.isNotEmpty) {
      return '${typeName}_${identifier}_$formattedDate.pdf';
    }

    return '${typeName}_$formattedDate.pdf';
  }

  /// Generates a PDF report from pending operation, enriching data internally.
  static Future<Uint8List> generatePendingOperationPdf({
    required PendingOperation operation,
  }) async {
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    // Get enriched data from database with operation date for historical accuracy
    final dbHelper = DatabaseHelper.instance;

    // Data içindeki receipt_date'i kullan, created_at değil (server timing farkı için)
    DateTime operationDate = operation.createdAt;
    try {
      final data = jsonDecode(operation.data) as Map<String, dynamic>;
      final header = data['header'] as Map<String, dynamic>?;
      if (header != null && header['receipt_date'] != null) {
        operationDate = DateTime.parse(header['receipt_date'].toString());
      }
    } catch (e) {
      // Parse hatası durumunda created_at kullan
    }

    final enrichedData = await dbHelper.getEnrichedGoodsReceiptData(operation.data, operationDate: operationDate);

    // Operation type'a göre farklı PDF formatları
    switch (operation.type) {
      case PendingOperationType.goodsReceipt:
        return _generateGoodsReceiptOperationPdf(operation, enrichedData, font, boldFont);
      case PendingOperationType.inventoryTransfer:
        final transferEnrichedData = await dbHelper.getEnrichedInventoryTransferData(operation.data);
        return _generateInventoryTransferOperationPdf(operation, transferEnrichedData, font, boldFont);
      case PendingOperationType.forceCloseOrder:
        // Placeholder for future implementation
        return _generateForceCloseOrderOperationPdf(operation, enrichedData, font, boldFont);
    }
  }

  /// Generates a detailed PDF for goods receipt operations using enriched data
  static Future<Uint8List> _generateGoodsReceiptOperationPdf(
    PendingOperation operation,
    Map<String, dynamic> enrichedData,
    pw.Font font,
    pw.Font boldFont,
  ) async {
    final header = enrichedData['header'] as Map<String, dynamic>? ?? {};
    final items = enrichedData['items'] as List<dynamic>? ?? [];

    // Extract information from the enriched data
    final employeeInfo = header['employee_info'] as Map<String, dynamic>?;
    final warehouseInfo = header['warehouse_info'] as Map<String, dynamic>?;
    final orderInfo = header['order_info'] as Map<String, dynamic>?;

    final employeeName = (employeeInfo != null)
        ? '${employeeInfo['first_name']} ${employeeInfo['last_name']}'
        : 'System User';
    final warehouseName = warehouseInfo?['name'] ?? 'N/A';
    final warehouseCode = warehouseInfo?['warehouse_code'] ?? 'N/A';
    final branchName = warehouseInfo?['branch_name'] ?? 'N/A';
    final warehouseReceivingMode = warehouseInfo?['receiving_mode'] ?? 2; // Default: mixed
    final poId = orderInfo?['fisno']?.toString() ?? header['fisno']?.toString() ?? header['po_id']?.toString() ?? 'N/A';
    final deliveryNoteNumber = header['delivery_note_number']?.toString();
    final invoiceNumber = header['invoice_number']?.toString() ?? 'N/A';

    // Check if this is an order-based receipt or free receipt
    final isOrderBased = header['siparis_id'] != null;

    // Force close kontrolü - sipariş eksiklerle kapatıldı mı?
    bool isForceClosed = false;
    final siparisId = header['siparis_id'] as int?;
    if (siparisId != null) {
      try {
        // Data içindeki receipt_date'i kullan, created_at değil (server timing farkı için)
        DateTime operationDate = operation.createdAt;
        try {
          final data = jsonDecode(operation.data) as Map<String, dynamic>;
          final dataHeader = data['header'] as Map<String, dynamic>?;
          if (dataHeader != null && dataHeader['receipt_date'] != null) {
            operationDate = DateTime.parse(dataHeader['receipt_date'].toString());
          }
        } catch (e) {
          // Parse hatası durumunda created_at kullan
        }

        final db = DatabaseHelper.instance;
        // Bu mal kabul işleminden SONRA force close yapıldı mı kontrol et
        isForceClosed = await db.hasForceCloseOperationForOrder(siparisId, operationDate);
      } catch (e) {
        // Hata durumunda force close bilgisini false olarak bırak
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            _buildHeader('Goods Receipt Report', boldFont),
            pw.SizedBox(height: 20),
            _buildEmployeeWarehouseInfoSection(
              employeeName: employeeName,
              warehouseName: warehouseName,
              warehouseCode: warehouseCode,
              branchName: branchName,
              font: font,
              boldFont: boldFont,
            ),
            pw.SizedBox(height: 15),
            _buildReceiptOperationInfoSection(
              operation: operation,
              poId: poId,
              deliveryNoteNumber: deliveryNoteNumber,
              isOrderBased: isOrderBased,
              invoiceNumber: invoiceNumber,
              date: operation.createdAt,
              isForceClosed: isForceClosed,
              font: font,
              boldFont: boldFont,
            ),
            pw.SizedBox(height: 20),
            _buildDetailedGoodsReceiptItemsTable(items, isOrderBased, warehouseReceivingMode, font, boldFont),
            pw.SizedBox(height: 30),
            _buildFooter(font),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Generates a detailed PDF for inventory transfer operations
  static Future<Uint8List> _generateInventoryTransferOperationPdf(
    PendingOperation operation,
    Map<String, dynamic> enrichedData,
    pw.Font font,
    pw.Font boldFont,
  ) async {
    final pdf = pw.Document();

    // Parse enriched data
    final header = enrichedData['header'] as Map<String, dynamic>? ?? {};
    final items = enrichedData['items'] as List<dynamic>? ?? [];

    // Extract information from enriched data
    final sourceName = header['source_location_name'] ?? 'N/A';
    final sourceCode = header['source_location_code'] ?? '';
    final targetName = header['target_location_name'] ?? 'N/A';
    final targetCode = header['target_location_code'] ?? '';
    final employeeName = header['employee_name'] ?? 'System User';
    final operationType = header['operation_type'] ?? 'transfer';
    final containerId = header['container_id']?.toString();
    final poId = header['po_id']?.toString();
    final warehouseInfo = header['warehouse_info'] as Map<String, dynamic>?;

    // Determine operation type
    final isPutawayOperation = header['source_location_id'] == null || header['source_location_id'] == 0;
    final operationTitle = isPutawayOperation ? 'Putaway Operation Report' : 'Inventory Transfer Report';

    // Location displays
    final sourceDisplay = sourceCode.isNotEmpty ? '$sourceName ($sourceCode)' : sourceName;
    final targetDisplay = targetCode.isNotEmpty ? '$targetName ($targetCode)' : targetName;

    // Calculate totals - not used in transfer report

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader(operationTitle, boldFont),

            pw.SizedBox(height: 20),

            // Employee and Warehouse Info Section
            _buildEmployeeWarehouseInfoSection(
              employeeName: employeeName,
              warehouseName: warehouseInfo?['name'] as String?,
              warehouseCode: warehouseInfo?['warehouse_code'] as String?,
              branchName: warehouseInfo?['branch_name'] as String?,
              font: font,
              boldFont: boldFont,
            ),

            pw.SizedBox(height: 15),

            // Transfer Info Section
            _buildTransferInfoSection(
              operation: operation,
              sourceLocation: sourceDisplay,
              targetLocation: targetDisplay,
              containerId: containerId,
              operationType: operationType,
              employeeName: employeeName,
              poId: poId,
              isPutawayOperation: isPutawayOperation,
              font: font,
              boldFont: boldFont,
            ),

            pw.SizedBox(height: 20),

            // Items Table
            _buildTransferItemsTable(items, font, boldFont),

            pw.SizedBox(height: 30),

            // Footer
            _buildFooter(font),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Generates a detailed PDF for force close order operations
  static Future<Uint8List> _generateForceCloseOrderOperationPdf(
    PendingOperation operation,
    Map<String, dynamic>? enrichedData,
    pw.Font font,
    pw.Font boldFont,
  ) async {
    final pdf = pw.Document();

         // Parse operation data
     final data = enrichedData ?? {};
     final poId = data['po_id'] ?? 'N/A';
     final employeeName = data['employee_name'] ?? 'System User';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader('Force Close Order Report', boldFont),

            pw.SizedBox(height: 20),

                                      // Order Info Section
             _buildForceCloseOrderInfoSection(
               operation: operation,
               poId: poId,
               employeeName: employeeName,
               font: font,
               boldFont: boldFont,
             ),

             pw.SizedBox(height: 20),

             // Order Details if available
             if (data['order_details'] != null)
               _buildOrderDetailsSection(data['order_details'], font, boldFont),

             pw.SizedBox(height: 30),

            // Footer
            _buildFooter(font),
          ];
        },
      ),
    );

    return pdf.save();
  }



  /// Shows a share dialog with options for saving and sharing
  static Future<void> showShareDialog(
    BuildContext context,
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

  /// Saves PDF to a user-selected directory.
  static Future<String?> savePdfWithPicker(Uint8List pdfData, String fileName) async {
    try {
      final String? path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Please select a folder to save'.tr(),
      );

      if (path != null) {
        final file = File('$path/$fileName');
        await file.writeAsBytes(pdfData);
        return file.path;
      }
      return null;
    } catch (e) {
      debugPrint("Error saving PDF with picker: $e");
      rethrow;
    }
  }

  /// Previews PDF using printing package
  static Future<void> previewPdf(Uint8List pdfData) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfData,
    );
  }

  static Future<void> _sharePdf(Uint8List pdfData, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final file = await File('${tempDir.path}/$fileName').create();
    await file.writeAsBytes(pdfData);
    await Share.shareXFiles([XFile(file.path)], text: 'PDF Report');
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

  // This function has been replaced by more detailed sections above

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



  // New specialized info sections



  static pw.Widget _buildTransferInfoSection({
    required PendingOperation operation,
    required String sourceLocation,
    required String targetLocation,
    String? containerId,
    required String operationType,
    required String employeeName,
    String? poId,
    bool isPutawayOperation = false,
    required pw.Font font,
    required pw.Font boldFont,
  }) {
    final infoTitle = isPutawayOperation ? 'Putaway Information' : 'Transfer Information';
    final operationTypeText = isPutawayOperation ? 'Putaway Operation' : 'Stock Transfer';
    final transferModeText = operationType == 'pallet_transfer' ? 'Pallet Transfer' : 'Product Transfer';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            infoTitle,
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          _buildInfoRow('Operation Type', operationTypeText, font, boldFont),
          _buildInfoRow('Created Date', DateFormat('dd/MM/yyyy HH:mm').format(operation.createdAt), font, boldFont),
          _buildInfoRow('From Location', sourceLocation, font, boldFont),
          _buildInfoRow('To Location', targetLocation, font, boldFont),
          if (poId != null)
            _buildInfoRow('Purchase Order', poId, font, boldFont),
          if (containerId != null)
            _buildInfoRow('Container ID', containerId, font, boldFont),
          _buildInfoRow('Transfer Mode', transferModeText, font, boldFont),
          _buildInfoRow('Status', operation.status, font, boldFont),
        ],
      ),
    );
  }

  static pw.Widget _buildForceCloseOrderInfoSection({
    required PendingOperation operation,
    required String poId,
    required String employeeName,
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
          pw.Text(
            'Force Close Order Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
                     _buildInfoRow('Operation Type', operation.displayTitle, font, boldFont),
           _buildInfoRow('Created Date', DateFormat('dd/MM/yyyy HH:mm').format(operation.createdAt), font, boldFont),
           _buildInfoRow('Employee', employeeName, font, boldFont),
           _buildInfoRow('Purchase Order', poId, font, boldFont),
           _buildInfoRow('Status', operation.status, font, boldFont),
        ],
      ),
    );
  }

  static pw.Widget _buildOrderDetailsSection(Map<String, dynamic> orderDetails, pw.Font font, pw.Font boldFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Order Details',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          if (orderDetails['tarih'] != null)
            _buildInfoRow('Order Date', orderDetails['tarih'].toString(), font, boldFont),
          if (orderDetails['invoice'] != null)
            _buildInfoRow('Invoice', orderDetails['invoice'].toString(), font, boldFont),
          if (orderDetails['notlar'] != null && orderDetails['notlar'].toString().isNotEmpty)
            _buildInfoRow('Notes', orderDetails['notlar'].toString(), font, boldFont),
          _buildInfoRow('Status', _getOrderStatusText(orderDetails['status']), font, boldFont),
        ],
      ),
    );
  }

  static String _getOrderStatusText(dynamic status) {
    switch (status) {
      case 0:
        return 'New';
      case 1:
        return 'In Progress';
      case 2:
        return 'Partially Received';
      case 3:
        return 'Manually Closed';
      case 4:
        return 'Completed';
      default:
        return 'Unknown';
    }
  }

  // New specialized item tables



  static pw.Widget _buildTransferItemsTable(List<dynamic> items, pw.Font font, pw.Font boldFont) {
    final totalQuantity = items.fold<double>(0.0, (sum, item) => sum + ((item['quantity_transferred'] as num? ?? item['quantity'] as num?)?.toDouble() ?? 0.0));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Transferred Items',
          style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.5), // Barcode
            1: pw.FlexColumnWidth(3.5), // Product Name + Code
            2: pw.FlexColumnWidth(1.5), // Quantity
            3: pw.FlexColumnWidth(2.5), // Container
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell('Barcode', boldFont, isHeader: true),
                _buildTableCell('Product Name', boldFont, isHeader: true),
                _buildTableCell('Quantity', boldFont, isHeader: true),
                _buildTableCell('Container', boldFont, isHeader: true),
              ],
            ),
            // Data rows
            ...items.map((item) {
              final productName = item['product_name'] ?? 'Unknown Product';
              final productCode = item['product_code'] ?? 'N/A';
              final productBarcode = item['product_barcode'] ?? '';
              final quantity = (item['quantity_transferred'] ?? item['quantity'])?.toString() ?? '0';
              final container = item['pallet_id'] ?? item['pallet_barcode'] ?? 'Product';

              // Product Name + Code birleştirme
              final productNameAndCode = productCode != 'N/A' ? '$productName ($productCode)' : productName;

              return pw.TableRow(
                children: [
                  _buildTableCell(productBarcode.isNotEmpty ? productBarcode : '-', font),
                  _buildTableCell(productNameAndCode, font),
                  _buildTableCell(quantity, font),
                  _buildTableCell(container, font),
                ],
              );
            }),
            // Total row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue50),
              children: [
                _buildTableCell('TOTAL', boldFont, isHeader: true),
                _buildTableCell('', boldFont, isHeader: true),
                _buildTableCell(totalQuantity.toStringAsFixed(0), boldFont, isHeader: true),
                _buildTableCell('', boldFont, isHeader: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildEmployeeWarehouseInfoSection({
    required String employeeName,
    String? warehouseName,
    String? warehouseCode,
    String? branchName,
    required pw.Font font,
    required pw.Font boldFont,
  }) {
    final warehouseDisplay = (warehouseName != null && warehouseName != 'N/A')
        ? '$warehouseName ($warehouseCode)'
        : 'N/A';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Employee & Warehouse Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          _buildInfoRow('Employee Name', employeeName, font, boldFont),
          _buildInfoRow('Warehouse', warehouseDisplay, font, boldFont),
          _buildInfoRow('Branch', branchName ?? 'N/A', font, boldFont),
        ],
      ),
    );
  }

  static pw.Widget _buildReceiptOperationInfoSection({
    required PendingOperation operation,
    required String poId,
    String? deliveryNoteNumber,
    bool isOrderBased = true,
    required String invoiceNumber,
    required DateTime date,
    bool isForceClosed = false,
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
          pw.Text(
            'Receipt Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          _buildInfoRow('Operation Type', operation.displayTitle, font, boldFont),
          _buildInfoRow('Receipt Date', DateFormat('dd/MM/yyyy HH:mm').format(date), font, boldFont),
          if (isOrderBased)
            _buildInfoRow('Purchase Order', poId, font, boldFont)
          else if (deliveryNoteNumber != null)
            _buildInfoRow('Delivery Note Number', deliveryNoteNumber, font, boldFont),
          if (invoiceNumber != 'N/A' && invoiceNumber != poId)
            _buildInfoRow('Invoice Number', invoiceNumber, font, boldFont),
          _buildInfoRow('Status', operation.status, font, boldFont),
          if (isForceClosed)
            _buildInfoRow('Order Status', 'Closed with remainings', font, boldFont),
        ],
      ),
    );
  }

  static pw.Widget _buildDetailedGoodsReceiptItemsTable(
    List<dynamic> items,
    bool isOrderBased,
    int warehouseReceivingMode,
    pw.Font font,
    pw.Font boldFont,
  ) {
    // DÜZELTME: "Sipariş Edilen" toplamını hesaplarken, her ürünün yalnızca bir kez sayılmasını sağlıyoruz.
    // Yinelenen ürün girişlerinden kaynaklanan mükerrer toplamayı önlemek için ürünleri ID'lerine göre grupluyoruz.
    final Map<dynamic, double> uniqueOrderedQuantities = {};
    for (final item in items) {
      final productId = item['urun_key']; // Benzersiz ürün kimliğini kullanıyoruz
      if (productId != null) {
        uniqueOrderedQuantities[productId] = (item['ordered_quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final totalOrdered = uniqueOrderedQuantities.values.fold(0.0, (sum, qty) => sum + qty);

    final isMixedMode = warehouseReceivingMode == 2;

    // Debug log
    debugPrint('PDF DEBUG: warehouseReceivingMode = $warehouseReceivingMode, isMixedMode = $isMixedMode');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Received Items', style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          // Sütun genişlikleri - sipariş bazlı olup olmadığına ve mixed mode olup olmadığına göre
          columnWidths: isOrderBased
            ? (isMixedMode ? const {
                0: pw.FlexColumnWidth(1.5), // Barcode
                1: pw.FlexColumnWidth(2), // Product Name
                2: pw.FlexColumnWidth(1.0), // Ordered
                3: pw.FlexColumnWidth(1.1), // Total Received
                4: pw.FlexColumnWidth(1.0), // This Receipt
                5: pw.FlexColumnWidth(1.2), // Expiry Date
                6: pw.FlexColumnWidth(1.5), // Container
              } : const {
                0: pw.FlexColumnWidth(1.8), // Barcode
                1: pw.FlexColumnWidth(2.5), // Product Name
                2: pw.FlexColumnWidth(1.0), // Ordered
                3: pw.FlexColumnWidth(1.1), // Total Received
                4: pw.FlexColumnWidth(1.0), // This Receipt
                5: pw.FlexColumnWidth(1.6), // Expiry Date
              })
            : (isMixedMode ? const {
                0: pw.FlexColumnWidth(2), // Barcode
                1: pw.FlexColumnWidth(2.5), // Product Name
                2: pw.FlexColumnWidth(1.5), // Quantity
                3: pw.FlexColumnWidth(1.5), // Expiry Date
                4: pw.FlexColumnWidth(2), // Container
              } : const {
                0: pw.FlexColumnWidth(2.5), // Barcode
                1: pw.FlexColumnWidth(3), // Product Name
                2: pw.FlexColumnWidth(1.5), // Quantity
                3: pw.FlexColumnWidth(2), // Expiry Date
              }),
          children: [
            // Header row - sipariş bazlı olup olmadığına ve mixed mode olup olmadığına göre farklı
            if (isOrderBased)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableCell('Barcode', boldFont, isHeader: true),
                  _buildTableCell('Product Name', boldFont, isHeader: true),
                  _buildTableCell('Ordered', boldFont, isHeader: true),
                  _buildTableCell('Total Received', boldFont, isHeader: true),
                  _buildTableCell('This Receipt', boldFont, isHeader: true),
                  _buildTableCell('Expiry Date', boldFont, isHeader: true),
                  if (isMixedMode) _buildTableCell('Container', boldFont, isHeader: true),
                ],
              )
            else
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableCell('Barcode', boldFont, isHeader: true),
                  _buildTableCell('Product Name', boldFont, isHeader: true),
                  _buildTableCell('Quantity', boldFont, isHeader: true),
                  _buildTableCell('Expiry Date', boldFont, isHeader: true),
                  if (isMixedMode) _buildTableCell('Container', boldFont, isHeader: true),
                ],
              ),
            ...items.map((item) {
              final productBarcode = item['product_barcode']?.toString() ?? '';
              final productName = item['product_name'] ?? 'Unknown';
              final productCode = item['product_code'] ?? 'N/A';
              final productNameAndCode = '$productName ($productCode)';
              final containerDisplay = item['pallet_barcode']?.toString() ?? 'Product';
              

              // Get expiry date
              final expiryDate = item['expiry_date'];
              String expiryDisplay = '-';
              if (expiryDate != null && expiryDate.toString().isNotEmpty) {
                try {
                  final parsedDate = DateTime.parse(expiryDate.toString());
                  expiryDisplay = DateFormat('dd/MM/yyyy').format(parsedDate);
                } catch (e) {
                  expiryDisplay = expiryDate.toString();
                }
              }

              if (isOrderBased) {
                // Sipariş bazlı mal kabul - tüm sütunları göster
                final orderedQty = (item['ordered_quantity'] as num?)?.toDouble() ?? 0.0;
                final currentReceived = (item['current_received'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 0.0;
                final previousReceived = (item['previous_received'] as num?)?.toDouble() ?? 0.0;

                // Total received display: "60 + 12" formatında
                String totalReceivedDisplay;
                if (previousReceived > 0) {
                  totalReceivedDisplay = '${previousReceived.toStringAsFixed(0)} + ${currentReceived.toStringAsFixed(0)}';
                } else {
                  totalReceivedDisplay = currentReceived.toStringAsFixed(0);
                }

                return pw.TableRow(
                  children: [
                    _buildTableCell(productBarcode.isNotEmpty ? productBarcode : '-', font),
                    _buildTableCell(productNameAndCode, font),
                    _buildTableCell(orderedQty.toStringAsFixed(0), font),
                    _buildTableCell(totalReceivedDisplay, font),
                    _buildTableCell(currentReceived.toStringAsFixed(0), font),
                    _buildTableCell(expiryDisplay, font),
                    if (isMixedMode) _buildTableCell(containerDisplay, font),
                  ],
                );
              } else {
                // Serbest mal kabul - sadece gerekli sütunları göster
                final currentReceived = (item['current_received'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 0.0;

                return pw.TableRow(
                  children: [
                    _buildTableCell(productBarcode.isNotEmpty ? productBarcode : '-', font),
                    _buildTableCell(productNameAndCode, font),
                    _buildTableCell(currentReceived.toStringAsFixed(0), font),
                    _buildTableCell(expiryDisplay, font),
                    if (isMixedMode) _buildTableCell(containerDisplay, font),
                  ],
                );
              }
            }),
            // Total row - sipariş bazlı olup olmadığına ve mixed mode olup olmadığına göre farklı
            if (isOrderBased)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  _buildTableCell('', boldFont, isHeader: true),
                  _buildTableCell('TOTAL', boldFont, isHeader: true),
                  _buildTableCell(totalOrdered.toStringAsFixed(0), boldFont, isHeader: true),
                  _buildTableCell(items.fold<double>(0.0, (sum, item) => sum + ((item['total_received'] as num?)?.toDouble() ?? 0.0)).toStringAsFixed(0), boldFont, isHeader: true),
                  _buildTableCell(items.fold<double>(0.0, (sum, item) => sum + ((item['current_received'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 0.0)).toStringAsFixed(0), boldFont, isHeader: true),
                  _buildTableCell('', boldFont, isHeader: true),
                  if (isMixedMode) _buildTableCell('', boldFont, isHeader: true),
                ],
              )
            else
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  _buildTableCell('', boldFont, isHeader: true),
                  _buildTableCell('TOTAL', boldFont, isHeader: true),
                  _buildTableCell(items.fold<double>(0.0, (sum, item) => sum + ((item['current_received'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 0.0)).toStringAsFixed(0), boldFont, isHeader: true),
                  _buildTableCell('', boldFont, isHeader: true),
                  if (isMixedMode) _buildTableCell('', boldFont, isHeader: true),
                ],
              ),
          ],
        ),
      ],
    );
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
                                  Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: _ShareOption(
                        icon: Icons.preview,
                        label: 'pdf_report.actions.preview'.tr(),
                        onTap: () async {
                          Navigator.pop(context);
                          await PdfService.previewPdf(pdfData);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ShareOption(
                        icon: Icons.file_download,
                        label: 'pdf_report.share_dialog.save_to_device'.tr(),
                        onTap: () async {
                          Navigator.pop(context);
                          try {
                            final savedPath = await PdfService.savePdfWithPicker(pdfData, fileName);
                            if (context.mounted && savedPath != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'pdf_report.actions.file_saved_to_downloads'.tr(namedArgs: {'path': savedPath}))),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('pdf_report.actions.file_save_failed'.tr())),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ShareOption(
                        icon: Icons.share,
                        label: 'pdf_report.share_dialog.other'.tr(),
                        onTap: () async {
                          Navigator.pop(context);
                          await PdfService._sharePdf(pdfData, fileName);
                        },
                      ),
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