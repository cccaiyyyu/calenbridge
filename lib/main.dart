import 'package:flutter/material.dart';
// 🎯 核心套件引入：徹底解決所有紅線與 Firebase 初始化問題
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart'; // 確保能正確引導到登入畫面

void main() async {
  // 1. 確保 Flutter 引擎組件在非同步執行前完全初始化
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 2. 🎯 明確傳入 Firebase 網頁版的初始化參數，徹底解決 JavaScriptObject 型態異常！
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

  // 3. 啟動 App 根組件
  runApp(const CalenBridge());
}

// 🎯 這是剛剛不小心被洗掉的靈魂根組件！補回來就完全沒錯誤了！
class CalenBridge extends StatelessWidget {
  const CalenBridge({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalenBridge',
      debugShowCheckedModeBanner: false, // 隱藏右上角除錯布條，讓畫面更精緻
      theme: ThemeData(
        primaryColor: const Color(0xFF003366), // 你們的高質感深海藍主色調
        useMaterial3: true,
      ),
      home: const LoginScreen(), // 🚪 專案的第一道大門：引導至登入畫面
    );
  }
}