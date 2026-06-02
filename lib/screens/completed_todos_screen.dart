import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// 🎯 記得引入 GoogleCalendarService 服務確保恢復時行事曆連動
import 'package:calenbridge/services/google_calendar_service.dart';

class CompletedTodosScreen extends StatelessWidget {
  const CompletedTodosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('請先登入')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('已完成的任務')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('completedTodos')
            .where('ownerUid', isEqualTo: currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('錯誤：${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('還沒有完成的任務', style: TextStyle(color: Colors.grey)),
            );
          }

          // 1. 先抓出所有資料並轉成 List
          final docs = snapshot.data!.docs;
          
          // 2. 進行排序
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['completedAt'];
            final bTime = bData['completedAt'];
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });

          // 3. 正確回傳 ListView 且 docs 完全包裹在 builder 內部
          return ListView(
            padding: const EdgeInsets.all(16),
            children: docs.map((doc) {
              final todo = doc.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  // 🎯 補回功能：綠色已完成打勾圖示
                  leading: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                  // 🎯 補回功能：刪除線文字排版
                  title: Text(
                    todo['title'] ?? '未命名',
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey,
                    ),
                  ),
                  // 🎯 補回功能：顯示格式化後的完成時間
                  subtitle: Text(
                    '完成時間：${_formatTime(todo['completedAt'])}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  // 🎯 補回功能：按鈕文字一律顯示「確認」，並綁定復原邏輯
                  trailing: TextButton(
                    onPressed: () => _restoreTodo(context, doc.id, todo),
                    child: const Text(
                      '確認', 
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF203764)),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = (timestamp as Timestamp).toDate();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  // 🎯 功能全面升級：串接 Google 行事曆防禦補建與參數維護
  Future<void> _restoreTodo(
      BuildContext context, String docId, Map<String, dynamic> todo) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⏳ 正在確保行程與 Google 行事曆完全同步中...'), duration: Duration(seconds: 1)),
    );

    try {
      // 1. 提取原本這筆待辦事項存在 Firestore 的 googleEventId
      final String? originalGoogleId = todo['googleEventId'];

      // 2. 執行 Google Calendar 恢復火箭：如果 Google 日曆上被刪了，就自動補建！
      final String? finalGoogleEventId = await GoogleCalendarService().restoreEventToGoogleCalendar(
        googleEventId: originalGoogleId,
        title: todo['title'] ?? '已恢復任務',
        startTime: DateTime.parse(todo['startTime'] ?? DateTime.now().toIso8601String()),
        endTime: DateTime.parse(todo['endTime'] ?? DateTime.now().add(const Duration(hours: 1)).toIso8601String()),
        reminderSetting: todo['reminderSetting'] ?? "不提醒",
        repeatSetting: todo['repeatSetting'] ?? "不要",
        note: todo['note'] ?? '自已完成的任務恢復',
      );

      // 3. 移轉資料到 todos 待辦清單中
      final newTodoRef = db.collection('todos').doc();
      final restoredData = Map<String, dynamic>.from(todo)
        ..remove('completedAt')
        ..remove('originalTodoId');
      
      // 🎯 把最新的安全 Google ID 存回任務欄位中，確保以後修改聯動正常
      if (finalGoogleEventId != null) {
        restoredData['googleEventId'] = finalGoogleEventId;
      }

      batch.set(newTodoRef, restoredData);
      
      // 4. 將原本在 completedTodos 集合裡的舊檔案刪除
      batch.delete(db.collection('completedTodos').doc(docId));

      // 5. 批次寫入資料庫
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 任務已成功恢復！行程已百分之百同步至 Google 日曆！'),
            backgroundColor: Color(0xFF203764),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 恢復失敗，錯誤: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}