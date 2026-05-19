import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 右下角的新增任務按鈕 (Floating Action Button)
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: 觸發新增任務邏輯
        },
        child: const Icon(Icons.add, size: 30),
      ),
      body: SafeArea(
        child: Row(
          children: [
            // 1. 左側邊欄 (Sidebars)
            Container(
              width: 60,
              color: Colors.grey.shade100,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.home), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
                ],
              ),
            ),
            
            // 分隔線
            VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),

            // 2. 右側主要內容區 (包含 Tab Bar 與 待辦事項)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 上方的頂部標籤列 (Tab Bar 區塊)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.white,
                    child: Row(
                      children: [
                        _buildTabButton('標籤一', isActive: true),
                        const SizedBox(width: 8),
                        _buildTabButton('標籤二'),
                        const SizedBox(width: 8),
                        _buildTabButton('標籤三'),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),

                  // 下方的待辦事項內容區 (待辦事項)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ListView(
                        children: [
                          const Text(
                            '待辦事項',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          _buildTodoItem('這是一項待辦任務卡片...'),
                          _buildTodoItem('這是另一項待辦任務卡片...'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 輔助小元件：Tab 標籤按鈕
  Widget _buildTabButton(String text, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive ? Colors.blue : Colors.transparent),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: isActive ? Colors.blue : Colors.black87,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // 輔助小元件：待辦事項卡片
  Widget _buildTodoItem(String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(24), // 依據你的設計圖，卡片內部有較大留白
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.5), // 依據圖中明顯的黑線外框
      ),
      child: Text(
        content,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}