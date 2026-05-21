import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
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
  } catch (e) {
    print("【CalenBridge】Firebase 初始化時發生異常: $e");
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
      // 🎯 重點：這裡的 LoginScreen() 前面「絕對不能」加 const！
      home: LoginScreen(), 
    );
  }
}