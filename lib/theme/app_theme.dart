import 'package:flutter/material.dart';

class AppTheme {
  // 1. 定義專案核心色彩 (資管專案色彩計畫常數)
  static const Color primaryBlue = Color(0xFF203764); // 主色調：深海藍 (展現專業、沉穩)
  static const Color accentBlue = Color(0xFFD9E1F2);  // 襯托色：淺天藍 (用於微小強調、外框)
  static const Color bgGray = Color(0xFFF9FAFB);      // 背景色：極輕質感灰 (長時間看眼睛不累)
  static const Color textDark = Color(0xFF1F2937);    // 文字主色：深碳灰 (比純黑更有質感)
  static const Color errorRed = Color(0xFFDC2626);    // 錯誤色：警示紅 (用於防呆、刪除提示)

  // 2. 封裝全域 ThemeData 供 main.dart 引入
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true, // 啟用 Google 最新 Material 3 設計規範
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: bgGray,
      
      // 定義全域色彩調色盤
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentBlue,
        surface: bgGray,
        error: errorRed,
      ),

      // AppBar (上方導覽列) 全域樣式設定
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white, // 標題文字與返回按鈕一律亮白
        elevation: 0,                  // 扁平化設計，取消陰影
        centerTitle: true,             // 標題一律強制居中
      ),

      // ElevatedButton (主要按鈕) 全域樣式設定
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // 現代感圓角
          ),
          textStyle: const TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),

      // InputDecoration (輸入框) 全域防破圖與美化設定
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white, // 輸入框內底色為純白
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        labelStyle: const TextStyle(color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
      ),
    );
  }
}