import 'package:flutter/material.dart';
import 'home_screen.dart'; // 確保 home_screen.dart 與此檔案在同一個 screens 資料夾下

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 日曆圖標
              Icon(
                Icons.calendar_month_rounded,
                size: 90,
                color: Theme.of(context).primaryColor, // 自動抓取深海藍
              ),
              const SizedBox(height: 20),
              
              // 2. 專案名稱與副標
              const Text(
                'CalenBridge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '智慧行事曆跨團隊橋樑',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 60), // 拉開跟按鈕的距離，讓畫面呼吸
              
              // 3. 🎯 一鍵登入的高質感 Google 按鈕
              OutlinedButton(
                onPressed: () {
                  // 先顯示提示訊息 (修正了原本少括號的錯誤)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('登入成功，正在導向首頁...')),
                  );

                  // 🎯 核心切換畫面邏輯：
                  // 使用 pushReplacement 跳轉到首頁，這樣登入後使用者「無法」透過返回鍵退回登入畫面
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // 延續圓角語彙
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.g_mobiledata_rounded, size: 30, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      '使用 Google 帳號登入',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}