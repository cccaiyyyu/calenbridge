import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  final _emailController = TextEditingController();

  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;

  // ✅ 每個組員的資料：{ email, canAssignTask }
  final List<Map<String, dynamic>> _members = [];

  @override
  void dispose() {
    _groupNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ✅ 新增組員到暫存列表
  void _addMember() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    if (email == _currentUser?.email) {
      _showSnack('不能邀請自己');
      return;
    }
    if (_members.any((m) => m['email'] == email)) {
      _showSnack('此 Email 已在列表中');
      return;
    }

    // 基本 email 格式驗證
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showSnack('請輸入有效的電子郵件');
      return;
    }

    setState(() {
      _members.add({'email': email, 'canAssignTask': false});
      _emailController.clear();
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ 建立小組並寫入 Firestore，同時對每位組員發送通知
  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final groupName = _groupNameController.text.trim();
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // 1️⃣ 建立 groups 文件
      final groupRef = db.collection('groups').doc();
      batch.set(groupRef, {
  'groupId': groupRef.id,               // ✅ 協議要求存進文件
  'groupName': groupName,               // ✅ 不變
  'creatorUid': _currentUser.uid,      // ✅ 改成 creatorUid
  'createdAt': FieldValue.serverTimestamp(),
  'memberIds': [_currentUser.uid],
  'memberPermissions': {
    _currentUser.uid: {'canAssignTask': true},
  },
  'pendingInvites': _members.map((m) => m['email']).toList(),
});

      // 2️⃣ 更新組長自己的 groupIds
      final ownerRef = db.collection('users').doc(_currentUser.uid);
      batch.update(ownerRef, {
        'groupIds': FieldValue.arrayUnion([groupRef.id]),
      });

      await batch.commit();

      // 3️⃣ 查詢每位受邀組員的 userId（依 email 查找）並發送邀請通知
      for (final member in _members) {
        final email = member['email'] as String;
        final canAssignTask = member['canAssignTask'] as bool;

        final userQuery = await db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          final toUserId = userQuery.docs.first.id;
          // ✅ 寫入 notifications collection
          await db.collection('notifications').add({
            'type': 'groupInvite',
            'toUserId': toUserId,
            'toEmail': email,
            'fromUserId': _currentUser.uid,
            'fromEmail': _currentUser.email,
            'fromName': _currentUser.displayName ?? _currentUser.email,
            'groupId': groupRef.id,
            'groupName': groupName,
            'canAssignTask': canAssignTask, // 組長賦予的權限
            'isRead': false,
            'status': 'pending', // pending / accepted / rejected
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        // 若查無此 email，通知無法送達（可提示組長）
      }

      if (mounted) {
        _showSnack('小組「$groupName」建立成功，邀請已發送！');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('建立失敗：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('建立小組')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ✅ 小組名稱輸入
            const Text('小組名稱', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _groupNameController,
              decoration: const InputDecoration(
                hintText: '請輸入小組名稱',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '請輸入小組名稱' : null,
            ),
            const SizedBox(height: 28),

            // ✅ 邀請組員輸入框
            const Text('邀請組員', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: '輸入組員電子郵件',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                    onFieldSubmitted: (_) => _addMember(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(Icons.add),
                  label: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ✅ 已新增的組員列表（含派發任務權限勾選）
            if (_members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('尚未新增任何組員', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              const Row(
                children: [
                  Expanded(child: Text('組員 Email', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  Text('派發任務權限', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  SizedBox(width: 40),
                ],
              ),
              const Divider(),
              ...List.generate(_members.length, (index) {
                final member = _members[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                  title: Text(member['email'], style: const TextStyle(fontSize: 14)),
                  // ✅ 派發任務權限開關
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: member['canAssignTask'],
                        onChanged: (val) {
                          setState(() => _members[index]['canAssignTask'] = val ?? false);
                        },
                      ),
                      // 刪除按鈕
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.red),
                        onPressed: () => setState(() => _members.removeAt(index)),
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 32),

            // ✅ 建立按鈕
            FilledButton.icon(
              onPressed: _isLoading ? null : _createGroup,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_isLoading ? '建立中...' : '建立小組'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}