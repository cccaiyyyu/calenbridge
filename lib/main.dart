import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';

void main() async {
  // 確保 Flutter 元件與底層完全綁定
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. 先讓 Firebase 乖乖初始化完畢（括號在這邊就安全閉合 🎯）
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyAVwy9AvgJsMryr-oILCndXslKv2A16vKw",
        authDomain: "calenbridge.firebaseapp.com",
        projectId: "calenbridge",
        storageBucket: "calenbridge.firebasestorage.app",
        messagingSenderId: "105456248073",
        appId: "1:105456248073:web:c8bbdea3702491b9739fd8",
      ),
    );
    print("【CalenBridge】Firebase 跨平台核心初始化成功！");

    // 2. 獨立出來：Firebase 成功後，再啟動本地通知服務 🎯
    await NotificationService().initNotification();
    print("【CalenBridge】本地通知系統初始化成功！");

  } catch (e) {
    print("【CalenBridge】系統初始化時發生異常: $e");
  }

  runApp(const CalenBridge());
}

class CalenBridge extends StatelessWidget {
  const CalenBridge({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalenBridge',
      debugShowCheckedModeBanner: false, 
      theme: AppTheme.lightTheme, 
      // LoginScreen 內有動態狀態判斷，前方維持不加 const 
      home: const LoginScreen(), // 💡 如果組員的 LoginScreen 改為 const，這邊可以加回去，不影響
    );
  }
}