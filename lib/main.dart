import 'package:flutter/material.dart';
import 'theme/app_theme.dart';       // 引入你的全域深海藍色彩計畫
import 'screens/login_screen.dart';   // 引入你剛剛補好的精美登入畫面

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalenBridge',
      debugShowCheckedModeBanner: false, // 關閉右上角 DEBUG 布條
      theme: AppTheme.lightTheme,        // 注入色彩計畫
      home: const LoginScreen(),         // 🎯 關鍵修改：首頁改走你的 LoginScreen！
    );
  }
}