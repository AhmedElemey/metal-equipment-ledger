import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'theme.dart';

extension PartyKindLabel on PartyKind {
  String get label => switch (this) {
    PartyKind.buyer => 'عميل (مشتري)',
    PartyKind.seller => 'مورد (بائع)',
    PartyKind.both => 'عميل ومورد',
  };
}

extension OrderKindLabel on OrderKind {
  String get label => switch (this) {
    OrderKind.sale => 'بيع',
    OrderKind.purchase => 'شراء',
  };

  Color get color => switch (this) {
    OrderKind.sale => AppColors.sale,
    OrderKind.purchase => AppColors.purchase,
  };
}

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
    OrderStatus.pending => 'جديد',
    OrderStatus.inProgress => 'قيد التنفيذ',
    OrderStatus.delivered => 'تم التسليم',
    OrderStatus.cancelled => 'ملغي',
    OrderStatus.quotation => 'عرض سعر',
  };

  Color get color => switch (this) {
    OrderStatus.pending => AppColors.orange,
    OrderStatus.inProgress => AppColors.purchase,
    OrderStatus.delivered => AppColors.sale,
    OrderStatus.cancelled => Colors.grey,
    OrderStatus.quotation => Colors.purple,
  };
}

extension ChequeStatusLabel on ChequeStatus {
  String get label => switch (this) {
    ChequeStatus.pending => 'قيد التحصيل',
    ChequeStatus.cleared => 'تم الصرف',
    ChequeStatus.bounced => 'مرتجع',
  };

  Color get color => switch (this) {
    ChequeStatus.pending => AppColors.orange,
    ChequeStatus.cleared => AppColors.sale,
    ChequeStatus.bounced => AppColors.danger,
  };
}
