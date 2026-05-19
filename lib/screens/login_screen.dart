import 'package:flutter/material.dart';

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
              // 1. 你們超好看的日曆圖標
              Icon(
                Icons.calendar_month_rounded,
                size: 90,
                color: Theme.of(context).primaryColor, // 自動抓取你們的深海藍
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
              
              // 3. 🎯 換成一鍵登入的高質感 Google 按鈕
              OutlinedButton(
                onPressed: () {
                  // TODO: 未來在這裡觸發 Firebase Google Sign-In 邏輯！
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('正在連線至 Google 驗證服務...')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // 延續你們的圓角語彙
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 這裡先用內建圖標代替，未來可以換成彩色的 Google Logo 圖片
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