import 'package:calenbridge/screens/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:calenbridge/screens/login_screen.dart';
import 'package:calenbridge/widgets/add_todo_bottom_sheet.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  String _selectedTab = "所有"; 
  List<Map<String, String>> _groupTabs = [
    {"id": "all", "name": "所有"},
    {"id": "personal", "name": "個人"},
  ];

  bool _isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _fetchUserGroups();
  }

  Future<void> _fetchUserGroups() async {
    if (_currentUser == null) return;
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data() as Map<String, dynamic>;
        List<dynamic> groupIds = userData['groupIds'] ?? [];

        List<Map<String, String>> fetchedTabs = [
          {"id": "all", "name": "所有"},
          {"id": "personal", "name": "個人"},
        ];

        if (groupIds.isNotEmpty) {
          QuerySnapshot groupDocs = await FirebaseFirestore.instance
              .collection('groups')
              .where(FieldPath.documentId, whereIn: groupIds)
              .get();

          for (var doc in groupDocs.docs) {
            final groupData = doc.data() as Map<String, dynamic>;
            fetchedTabs.add({
              "id": doc.id,
              "name": groupData['groupName'] ?? "未命名小組",
            });
          }
        }

        if (mounted) {
          setState(() {
            _groupTabs = fetchedTabs;
            _isLoadingGroups = false;
          });
        }
      } else {
        if (mounted) setState(() { _isLoadingGroups = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoadingGroups = false; });
    }
  }

  Query _buildTodoQuery() {
    Query query = FirebaseFirestore.instance
        .collection('todos')
        .where('ownerUid', isEqualTo: _currentUser?.uid);

    if (_selectedTab == "個人") {
      query = query.where('groupId', isEqualTo: 'personal');
    } else if (_selectedTab != "所有") {
      final targetGroup = _groupTabs.firstWhere(
        (t) => t['name'] == _selectedTab,
        orElse: () => {"id": ""},
      );
      query = query.where('groupId', isEqualTo: targetGroup['id']);
    }

    return query;
  }

  void _openTodoBottomSheet({String? todoId, Map<String, dynamic>? initialData}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return AddTodoBottomSheet(
          currentSelectedTab: _selectedTab,
          groupTabs: _groupTabs,
          todoId: todoId,                
          initialData: initialData,       
          onTodoAdded: () {
            setState(() {}); 
          },
        );
      },
    );
  }

  Future<void> _handleSignOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    // 🎯 解除魔咒 1：拿掉 const LoginScreen() 的 const
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
  }

  String _formatDateTimeString(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '未設定截止時間';
    try {
      final dateTime = DateTime.parse(isoString);
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '${dateTime.year}-$month-$day $hour:$minute';
    } catch (e) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTodoBottomSheet(), 
        backgroundColor: const Color(0xFFE6E0F8), 
        child: const Icon(Icons.add, color: Color(0xFF1D1B20), size: 30),
      ),
      body: Row(
        children: [
          // 🗂️ 1. 側邊導覽列
          NavigationRail(
            selectedIndex: 0,
            onDestinationSelected: (int index) {
              if (index == 1) {
                // 🎯 解除魔咒 2：拿掉 const CalendarScreen() 的 const
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CalendarScreen()),
                );
              } else if (index == 2) {
                _handleSignOut(); 
              }
            },
            labelType: NavigationRailLabelType.none,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.home_rounded), label: Text('首頁')),
              NavigationRailDestination(icon: Icon(Icons.calendar_month_rounded), label: Text('行事曆')),
              NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text('設定')),
            ],
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Icon(Icons.menu_rounded, size: 28),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _isLoadingGroups
                        ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()))
                        : SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _groupTabs.length,
                              itemBuilder: (context, index) {
                                final tabName = _groupTabs[index]['name']!;
                                final isSelected = _selectedTab == tabName;
                                return Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(tabName),
                                    selected: isSelected,
                                    onSelected: (bool selected) {
                                      if (selected) {
                                        setState(() { _selectedTab = tabName; });
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 24),
                    const Text(
                      '待辦事項',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _buildTodoQuery().snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Center(child: Text('目前沒有待辦事項喔！', style: TextStyle(color: Colors.grey)));
                          }

                          List<QueryDocumentSnapshot> todos = List.from(snapshot.data!.docs);
                          todos.sort((a, b) {
                            final Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
                            final Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
                            final String timeA = dataA['endTime'] ?? '';
                            final String timeB = dataB['endTime'] ?? '';
                            return timeA.compareTo(timeB); 
                          });

                          return ListView.builder(
                            itemCount: todos.length,
                            itemBuilder: (context, index) {
                              final doc = todos[index];
                              final todo = doc.data() as Map<String, dynamic>;
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  side: BorderSide(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _openTodoBottomSheet(
                                    todoId: doc.id, 
                                    initialData: todo
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      width: 12, height: 12,
                                      decoration: BoxDecoration(
                                        color: Color(todo['color'] ?? 0xFF203764),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    title: Text(
                                      todo['title'] ?? '未命名', 
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      '截止時間: ${_formatDateTimeString(todo['endTime'])}',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                    trailing: Chip(
                                      label: Text(todo['groupId'] == 'personal' ? '個人' : '小組', style: const TextStyle(fontSize: 12)),
                                    ),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}