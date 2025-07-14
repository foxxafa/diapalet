// lib/core/services/pdf_service.dart
import 'dart:io';
import 'package:diapalet/core/local/database_helper.dart';
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

class PdfService {
  static const String _companyName = 'ROWHUB Warehouse Management';
  
  /// Generates a comprehensive PDF report for goods receipt operation
  static Future<Uint8List> generateGoodsReceiptPdf({
    required List<ReceiptItemDraft> items,
    required bool isOrderBased,
    PurchaseOrder? order,
    String? invoiceNumber,
    required String employeeName,
    required DateTime date,
    Map<String, dynamic>? employeeInfo,
    Map<String, dynamic>? orderInfo,
    Map<String, dynamic>? warehouseInfo,
  }) async {
    final pdf = pw.Document();
    
    // Load font for better text rendering
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    final title = isOrderBased 
        ? 'Order-based Goods Receipt Report'
        : 'Free Goods Receipt Report';
    
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
            
            // Employee and Warehouse Info Section
            _buildEmployeeWarehouseInfoSection(
              employeeName: employeeName,
              employeeInfo: employeeInfo,
              warehouseInfo: warehouseInfo,
              font: font,
              boldFont: boldFont,
            ),
            
            pw.SizedBox(height: 15),
            
            // Order Info Section (if order-based)
            if (isOrderBased && (order != null || orderInfo != null))
              _buildOrderInfoSection(
                order: order,
                orderInfo: orderInfo,
                invoiceNumber: invoiceNumber,
                font: font,
                boldFont: boldFont,
              ),
            
            if (isOrderBased) pw.SizedBox(height: 15),
            
            // Receipt Info Section
            _buildReceiptInfoSection(
              date: date,
              invoiceNumber: invoiceNumber,
              isOrderBased: isOrderBased,
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
            _buildDetailedItemsTable(items, font, boldFont),
            
            pw.SizedBox(height: 30),
            
            // Footer
            _buildFooter(font),
          ];
        },
      ),
    );
    
    return pdf.save();
  }

  /// Generates a PDF report from pending operation
  static Future<Uint8List> generatePendingOperationPdf({
    required PendingOperation operation,
  }) async {
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    // Get enriched data from database
    final dbHelper = DatabaseHelper.instance;
    final enrichedData = await dbHelper.getEnrichedGoodsReceiptData(operation.data);
    
    // Operation type'a göre farklı PDF formatları
    switch (operation.type) {
      case PendingOperationType.goodsReceipt:
        return _generateGoodsReceiptOperationPdf(operation, enrichedData, font, boldFont);
      case PendingOperationType.inventoryTransfer:
        return _generateInventoryTransferOperationPdf(operation, enrichedData, font, boldFont);
      case PendingOperationType.forceCloseOrder:
        return _generateForceCloseOrderOperationPdf(operation, enrichedData, font, boldFont);
    }
  }
  
  /// Generates a detailed PDF for goods receipt operations
  static Future<Uint8List> _generateGoodsReceiptOperationPdf(
    PendingOperation operation,
    Map<String, dynamic>? enrichedData,
    pw.Font font,
    pw.Font boldFont,
  ) async {
    
    // Parse operation data
    final data = enrichedData ?? {};
    final header = data['header'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];
    
         // Extract information
     final poId = header['po_id'] ?? 'N/A';
     final invoiceNumber = header['invoice_number'] ?? 'N/A';
     final employeeName = header['employee_name'] ?? 'System User';
     final operationDate = operation.createdAt;
    
         // Calculate totals
     final totalItems = items.fold<int>(0, (sum, item) => sum + (item['quantity'] as num? ?? 0).toInt());
     final uniqueProducts = items.map((item) => item['product_id'] ?? item['urun_id']).toSet().length;
     
     final pdf = pw.Document();
     
     pdf.addPage(
       pw.MultiPage(
         pageFormat: PdfPageFormat.a4,
         margin: const pw.EdgeInsets.all(20),
         build: (pw.Context context) {
           return [
             // Header
             _buildHeader('Goods Receipt Report', boldFont),
             
             pw.SizedBox(height: 20),
             
             // Operation Info Section
             _buildSpecializedOperationInfoSection(
               operation: operation,
               poId: poId,
               invoiceNumber: invoiceNumber,
               employeeName: employeeName,
               date: operationDate,
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
             _buildGoodsReceiptItemsTable(items, font, boldFont),
             
             pw.SizedBox(height: 30),
             
             // Footer
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
    Map<String, dynamic>? enrichedData,
    pw.Font font,
    pw.Font boldFont,
  ) async {
    final pdf = pw.Document();
    
    // Parse operation data
    final data = enrichedData ?? {};
    final header = data['header'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];
    
         // Extract information
     final sourceLocationName = header['source_location_name'] ?? 'Receiving Area';
     final targetLocationName = header['target_location_name'] ?? 'Unknown Location';
     final containerId = header['container_id']?.toString();
     final operationType = header['operation_type'] ?? 'transfer';
     final employeeName = header['employee_name'] ?? 'System User';
     final poId = header['po_id'];
    
    // Calculate totals
    final totalItems = items.fold<int>(0, (sum, item) => sum + (item['quantity_transferred'] as num? ?? item['quantity'] as num? ?? 0).toInt());
    final uniqueProducts = items.map((item) => item['product_id'] ?? item['urun_id']).toSet().length;
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader('Inventory Transfer Report', boldFont),
            
            pw.SizedBox(height: 20),
            
                         // Transfer Info Section
             _buildTransferInfoSection(
               operation: operation,
               sourceLocation: sourceLocationName,
               targetLocation: targetLocationName,
               containerId: containerId,
               operationType: operationType,
               employeeName: employeeName,
               poId: poId,
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
  

  
  /// Shows PDF preview first, then allows user to save or share
  static Future<void> showPdfPreviewDialog(
    BuildContext context, 
    Uint8List pdfData, 
    String fileName,
  ) async {
    // First show preview
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('pdf_report.preview.title'.tr()),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: PdfPreview(
            build: (format) => pdfData,
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common_labels.close'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              showShareDialog(context, pdfData, fileName);
            },
            child: Text('pdf_report.actions.save_share'.tr()),
          ),
        ],
      ),
    );
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
  
  // This function has been replaced by more detailed sections above
  
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
  
  // This function has been replaced by _buildDetailedItemsTable above
  

  
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
  
  static pw.Widget _buildSpecializedOperationInfoSection({
    required PendingOperation operation,
    required String poId,
    required String invoiceNumber,
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
          pw.Text(
            'Operation Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          _buildInfoRow('Operation Type', operation.displayTitle, font, boldFont),
          _buildInfoRow('Created Date', DateFormat('dd/MM/yyyy HH:mm').format(date), font, boldFont),
          _buildInfoRow('Employee', employeeName, font, boldFont),
          _buildInfoRow('Purchase Order', poId, font, boldFont),
          if (invoiceNumber != 'N/A' && invoiceNumber != poId)
            _buildInfoRow('Invoice Number', invoiceNumber, font, boldFont),
          _buildInfoRow('Status', operation.status, font, boldFont),
        ],
      ),
    );
  }
  
  static pw.Widget _buildTransferInfoSection({
    required PendingOperation operation,
    required String sourceLocation,
    required String targetLocation,
    String? containerId,
    required String operationType,
    required String employeeName,
    String? poId,
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
            'Transfer Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
                     _buildInfoRow('Operation Type', operation.displayTitle, font, boldFont),
           _buildInfoRow('Created Date', DateFormat('dd/MM/yyyy HH:mm').format(operation.createdAt), font, boldFont),
           _buildInfoRow('Employee', employeeName, font, boldFont),
           _buildInfoRow('From Location', sourceLocation, font, boldFont),
           _buildInfoRow('To Location', targetLocation, font, boldFont),
           if (containerId != null)
             _buildInfoRow('Container ID', containerId, font, boldFont),
           if (poId != null)
             _buildInfoRow('Purchase Order', poId, font, boldFont),
           _buildInfoRow('Transfer Type', operationType, font, boldFont),
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
      case 5:
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }
  
  // New specialized item tables
  
  static pw.Widget _buildGoodsReceiptItemsTable(List<dynamic> items, pw.Font font, pw.Font boldFont) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Received Items',
          style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(2),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell('Code', boldFont, isHeader: true),
                _buildTableCell('Product Name', boldFont, isHeader: true),
                _buildTableCell('Quantity', boldFont, isHeader: true),
                _buildTableCell('Container', boldFont, isHeader: true),
              ],
            ),
            // Data rows
            ...items.map((item) {
              final productName = item['product_name'] ?? 'Unknown Product';
              final productCode = item['product_code'] ?? 'N/A';
              final quantity = item['quantity']?.toString() ?? '0';
              final container = item['pallet_barcode'] ?? 'Box Mode';
              
              return pw.TableRow(
                children: [
                  _buildTableCell(productCode, font),
                  _buildTableCell(productName, font),
                  _buildTableCell(quantity, font),
                  _buildTableCell(container, font),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }
  
  static pw.Widget _buildTransferItemsTable(List<dynamic> items, pw.Font font, pw.Font boldFont) {
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
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(2),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell('Code', boldFont, isHeader: true),
                _buildTableCell('Product Name', boldFont, isHeader: true),
                _buildTableCell('Quantity', boldFont, isHeader: true),
                _buildTableCell('Container', boldFont, isHeader: true),
              ],
            ),
            // Data rows
            ...items.map((item) {
              final productName = item['product_name'] ?? 'Unknown Product';
              final productCode = item['product_code'] ?? 'N/A';
              final quantity = (item['quantity_transferred'] ?? item['quantity'])?.toString() ?? '0';
              final container = item['pallet_id'] ?? item['pallet_barcode'] ?? 'Box Mode';
              
              return pw.TableRow(
                children: [
                  _buildTableCell(productCode, font),
                  _buildTableCell(productName, font),
                  _buildTableCell(quantity, font),
                  _buildTableCell(container, font),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildEmployeeWarehouseInfoSection({
    required String employeeName,
    Map<String, dynamic>? employeeInfo,
    Map<String, dynamic>? warehouseInfo,
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
            'Employee & Warehouse Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          _buildInfoRow('Employee Name', employeeName, font, boldFont),
          if (employeeInfo != null) ...[
            _buildInfoRow('Employee ID', employeeInfo['id']?.toString() ?? 'N/A', font, boldFont),
            _buildInfoRow('Username', employeeInfo['username']?.toString() ?? 'N/A', font, boldFont),
            _buildInfoRow('Role', employeeInfo['role']?.toString() ?? 'N/A', font, boldFont),
            _buildInfoRow('Warehouse Name', employeeInfo['warehouse_name']?.toString() ?? 'N/A', font, boldFont),
            _buildInfoRow('Warehouse Code', employeeInfo['warehouse_code']?.toString() ?? 'N/A', font, boldFont),
            _buildInfoRow('Branch ID', employeeInfo['warehouse_branch_id']?.toString() ?? 'N/A', font, boldFont),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildOrderInfoSection({
    PurchaseOrder? order,
    Map<String, dynamic>? orderInfo,
    String? invoiceNumber,
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
            'Order Information',
            style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 8),
          if (order != null) ...[
            _buildInfoRow('Purchase Order ID', order.poId ?? 'N/A', font, boldFont),
            _buildInfoRow('Order Date', order.date != null ? DateFormat('dd/MM/yyyy').format(order.date!) : 'N/A', font, boldFont),
            _buildInfoRow('Status', _getOrderStatusText(order.status), font, boldFont),
          ],
          if (orderInfo != null) ...[
            _buildInfoRow('Order ID', orderInfo['id']?.toString() ?? 'N/A', font, boldFont),
            _buildInfoRow('Purchase Order ID', orderInfo['po_id']?.toString() ?? 'N/A', font, boldFont),
            if (orderInfo['tarih'] != null)
              _buildInfoRow('Order Date', orderInfo['tarih'].toString(), font, boldFont),
            _buildInfoRow('Status', _getOrderStatusText(orderInfo['status']), font, boldFont),
            if (orderInfo['notlar'] != null && orderInfo['notlar'].toString().isNotEmpty)
              _buildInfoRow('Notes', orderInfo['notlar'].toString(), font, boldFont),
            _buildInfoRow('Branch ID', orderInfo['branch_id']?.toString() ?? 'N/A', font, boldFont),
          ],
          if (invoiceNumber != null && invoiceNumber.isNotEmpty)
            _buildInfoRow('Invoice Number', invoiceNumber, font, boldFont),
        ],
      ),
    );
  }

  static pw.Widget _buildReceiptInfoSection({
    required DateTime date,
    String? invoiceNumber,
    required bool isOrderBased,
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
          _buildInfoRow('Receipt Date', DateFormat('dd/MM/yyyy HH:mm').format(date), font, boldFont),
          if (isOrderBased)
            _buildInfoRow('Purchase Order', invoiceNumber ?? 'N/A', font, boldFont),
          if (!isOrderBased)
            _buildInfoRow('Invoice Number', invoiceNumber ?? 'N/A', font, boldFont),
        ],
      ),
    );
  }

  static pw.Widget _buildDetailedItemsTable(List<ReceiptItemDraft> items, pw.Font font, pw.Font boldFont) {
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
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(2),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell('Code', boldFont, isHeader: true),
                _buildTableCell('Product Name', boldFont, isHeader: true),
                _buildTableCell('Quantity', boldFont, isHeader: true),
                _buildTableCell('Container', boldFont, isHeader: true),
              ],
            ),
            // Data rows
            ...items.map((item) {
              final productName = item.product.name;
              final productCode = item.product.stockCode;
              final quantity = item.quantity.toStringAsFixed(0);
              final container = item.palletBarcode != null 
                  ? 'Pallet: ${item.palletBarcode}'
                  : 'Box Mode';
              
              return pw.TableRow(
                children: [
                  _buildTableCell(productCode, font),
                  _buildTableCell(productName, font),
                  _buildTableCell(quantity, font),
                  _buildTableCell(container, font),
                ],
              );
            }),
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
                          await PdfService.savePdfToDevice(pdfData, fileName);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('pdf_report.actions.file_saved'.tr())),
                            );
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
                          await PdfService.savePdfToDevice(pdfData, fileName);
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