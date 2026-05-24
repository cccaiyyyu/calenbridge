import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  // 🎯 修正重點 1：簡化查詢！拔除所有大於/小於與排序，只抓出「登入者」的任務
  // 徹底避開 Firestore 囉嗦的複合索引 (Composite Index) 報錯
  Query _buildDailyTodoQuery() {
    return FirebaseFirestore.instance
        .collection('todos')
        .where('ownerUid', isEqualTo: _currentUser?.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('跨團隊行事曆', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF203764),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 📅 上半部：高質感互動行事曆
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
            ),
            child: TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                if (!isSameDay(_selectedDay, selectedDay)) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                }
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() { _calendarFormat = format; });
                }
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              calendarStyle: const CalendarStyle(
                selectedDecoration: BoxDecoration(color: Color(0xFF203764), shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: Color(0xFF8E9EBE), shape: BoxShape.circle),
                weekendTextStyle: TextStyle(color: Colors.redAccent),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  color: Color(0xFF203764),
                  borderRadius: BorderRadius.all(Radius.circular(12.0)),
                ),
                formatButtonTextStyle: TextStyle(color: Colors.white),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 📝 下半部：動態顯示選中日期的任務清單
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selectedDay!.month}月${_selectedDay!.day}日 待辦事項',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF203764)),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildDailyTodoQuery().snapshots(),
              builder: (context, snapshot) {
                // 1. 讀取中狀態
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                // 2. 錯誤狀態防禦
                if (snapshot.hasError) {
                  return const Center(child: Text('讀取資料發生錯誤', style: TextStyle(color: Colors.red)));
                }

                // 3. 雲端完全沒有任務的空狀態
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                // 🎯 修正重點 2：在前端 (Dart) 進行日期過濾
                final allTodos = snapshot.data!.docs;
                
                final dailyTodos = allTodos.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String startTimeStr = data['startTime'] ?? '';
                  final String endTimeStr = data['endTime'] ?? '';
                  
                  if (startTimeStr.isEmpty) return false;

                  try {
                    final DateTime startTime = DateTime.parse(startTimeStr);
                    final DateTime endTime = endTimeStr.isNotEmpty ? DateTime.parse(endTimeStr) : startTime;
                    
                    // 💡 更貼心：只要「開始時間」或「結束時間」落在選中的這一天，就把它顯示出來！
                    return isSameDay(startTime, _selectedDay) || isSameDay(endTime, _selectedDay);
                  } catch (e) {
                    return false;
                  }
                }).toList();

                // 🎯 修正重點 3：在前端自行按時間排序
                dailyTodos.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  return (dataA['startTime'] ?? '').compareTo(dataB['startTime'] ?? '');
                });

                // 4. 過濾後，當天沒有任務的空狀態
                if (dailyTodos.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: dailyTodos.length,
                  itemBuilder: (context, index) {
                    final todo = dailyTodos[index].data() as Map<String, dynamic>;
                    final int colorValue = todo['color'] ?? 0xFF203764;
                    final startTimeStr = todo['startTime']?.toString().substring(11, 16) ?? '';
                    final endTimeStr = todo['endTime']?.toString().substring(11, 16) ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        leading: Container(
                          width: 4,
                          height: double.infinity,
                          decoration: BoxDecoration(color: Color(colorValue), borderRadius: BorderRadius.circular(4)),
                        ),
                        title: Text(todo['title'] ?? '未命名任務', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('⏰ $startTimeStr - $endTimeStr'),
                        trailing: Chip(
                          label: Text(todo['groupId'] == 'personal' ? '個人' : '小組', style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.grey.shade100,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 將空狀態 UI 獨立成一個小元件，讓程式碼更乾淨
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_rounded, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('這天沒有任何任務喔，可以好好放鬆！', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}