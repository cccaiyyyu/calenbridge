import 'package:flutter/foundation.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // 🎯 核心防禦：如果是在網頁端測試，直接回傳一個虛擬空方法，完全不調用任何手機原生功能！
  Future<void> initNotification() async {
    print("【CalenBridge 通知服務】Web 環境下自動繞過原生手機通知模組。");
    return;
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDateTime, 
  }) async {
    print("【CalenBridge 網頁模擬通知】任務 ID: $id 已完成虛擬排程預約！");
    return;
  }
}