import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupManagementScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupManagementScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final db = FirebaseFirestore.instance;

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── 1. 編輯小組名稱 ──────────────────────────────────────────
  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: widget.groupName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('編輯小組名稱'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '輸入新名稱'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('確認'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;

    await db.collection('groups').doc(widget.groupId).update({'groupName': result});
    if (mounted) {
      _showSnack('小組名稱已更新');
      Navigator.pop(context, true); // 回傳 true 讓首頁刷新
    }
  }

  // ─── 2. 刪除小組 ──────────────────────────────────────────────
  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「${widget.groupName}」嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final currentUid = _currentUser?.uid;
    if (currentUid == null) return;

    // ─── 檢查該小組內是否有自己未完成的任務 ──────────────────────
    final myTodos = await db
        .collection('todos')
        .where('ownerUid', isEqualTo: currentUid)
        .where('groupId', isEqualTo: widget.groupId)
        .get();

    if (myTodos.docs.isNotEmpty && mounted) {
      final moveToPersonal = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('你有未完成的任務'),
          content: Text(
            '此小組內有 ${myTodos.docs.length} 筆你的未完成任務，\n要移到個人待辦事項嗎？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不用，直接刪除'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移到個人'),
            ),
          ],
        ),
      );

      if (moveToPersonal == true) {
        final batch = db.batch();
        final String currentUserId = _currentUser?.uid ?? ''; 
        final String currentUserEmail = _currentUser?.email ?? ''; 

        for (final doc in myTodos.docs) {
          batch.update(db.collection('todos').doc(doc.id), {
            'groupId': 'personal',
            'ownerUid': currentUserId, 
            'assignedToUid': currentUserId, 
            'assignedTo': currentUserId,
            'assignedToEmail': currentUserEmail, 
          });
        }
        await batch.commit();
      }
    }

    // ─── 刪除小組 ────────────────────────────────────────────────
    final groupDoc = await db.collection('groups').doc(widget.groupId).get();
    final groupData = groupDoc.data() as Map<String, dynamic>;
    final List memberIds = groupData['memberIds'] ?? [];

    final batch = db.batch();
    for (final uid in memberIds) {
      batch.update(db.collection('users').doc(uid), {
        'groupIds': FieldValue.arrayRemove([widget.groupId]),
      });
    }
    batch.delete(db.collection('groups').doc(widget.groupId));
    await batch.commit();

    if (mounted) {
      _showSnack('小組已刪除');
      Navigator.pop(context, true);
    }
  }

  // ─── 3. 增加組員 ──────────────────────────────────────────────
  Future<void> _addMember() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('增加組員'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: '輸入組員 Email'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('發送邀請'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    if (email == _currentUser?.email) {
      _showSnack('不能邀請自己');
      return;
    }

    final userQuery = await db
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      if (mounted) _showSnack('找不到該用戶');
      return;
    }
    final toUserId = userQuery.docs.first.id;

    await db.collection('groups').doc(widget.groupId).update({
      'pendingInvites': FieldValue.arrayUnion([email]),
    });

    await db.collection('notifications').add({
      'type': 'groupInvite',
      'toUserId': toUserId,
      'toEmail': email,
      'fromUserId': _currentUser?.uid,
      'fromEmail': _currentUser?.email,
      'fromName': _currentUser?.displayName ?? _currentUser?.email,
      'groupId': widget.groupId,
      'groupName': widget.groupName,
      'canAssignTask': false,
      'isRead': false,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) _showSnack('已發送邀請給 $email');
  }

  // ─── 4. 刪除組員 ──────────────────────────────────────────────
  Future<void> _removeMember() async {
    final groupDoc = await db.collection('groups').doc(widget.groupId).get();
    final groupData = groupDoc.data() as Map<String, dynamic>;
    final List memberIds = List.from(groupData['memberIds'] ?? []);
    memberIds.remove(_currentUser?.uid); 

    final List<Map<String, String>> members = [];
    for (final uid in memberIds) {
      final userDoc = await db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final email = (userDoc.data() as Map<String, dynamic>)['email'] ?? uid;
        members.add({'uid': uid, 'email': email});
      }
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('刪除組員'),
          content: members.isEmpty
              ? const Text('目前沒有其他組員')
              : SizedBox(
                  width: 300,
                  child: ListView(
                    shrinkWrap: true,
                    children: members
                        .map((m) => ListTile(
                              title: Text(m['email']!,
                                  style: const TextStyle(fontSize: 13)),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red),
                                onPressed: () async {
                                  final batch = db.batch();
                                  batch.update(
                                    db.collection('groups').doc(widget.groupId),
                                    {
                                      'memberIds': FieldValue.arrayRemove([m['uid']]),
                                      'memberPermissions.${m['uid']}':
                                          FieldValue.delete(),
                                    },
                                  );
                                  batch.update(
                                    db.collection('users').doc(m['uid']),
                                    {
                                      'groupIds':
                                          FieldValue.arrayRemove([widget.groupId]),
                                    },
                                  );
                                  await batch.commit();
                                  setDialogState(() => members.remove(m));
                                  if (mounted) _showSnack('已移除 ${m['email']}');
                                },
                              ),
                            ))
                        .toList(),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('關閉'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 5. 更改權限 ──────────────────────────────────────────────
  Future<void> _editPermissions() async {
    final groupDoc = await db.collection('groups').doc(widget.groupId).get();
    final groupData = groupDoc.data() as Map<String, dynamic>;
    final List memberIds = List.from(groupData['memberIds'] ?? []);
    final Map permissions = groupData['memberPermissions'] ?? {};
    memberIds.remove(_currentUser?.uid);

    final List<Map<String, dynamic>> members = [];
    for (final uid in memberIds) {
      final userDoc = await db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final email = (userDoc.data() as Map<String, dynamic>)['email'] ?? uid;
        final canAssign = (permissions[uid] as Map?)?['canAssignTask'] ?? false;
        members.add({'uid': uid, 'email': email, 'canAssignTask': canAssign});
      }
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('更改權限'),
          content: members.isEmpty
              ? const Text('目前沒有其他組員')
              : SizedBox(
                  width: 300,
                  child: ListView(
                    shrinkWrap: true,
                    children: members.asMap().entries.map((entry) {
                      final i = entry.key;
                      final m = entry.value;
                      return SwitchListTile(
                        title: Text(m['email'],
                            style: const TextStyle(fontSize: 13)),
                        subtitle: const Text('派發任務權限'),
                        value: m['canAssignTask'],
                        onChanged: (val) =>
                            setDialogState(() => members[i]['canAssignTask'] = val),
                      );
                    }).toList(),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final batch = db.batch();
                for (final m in members) {
                  batch.update(
                    db.collection('groups').doc(widget.groupId),
                    {
                      'memberPermissions.${m['uid']}': {
                        'canAssignTask': m['canAssignTask']
                      }
                    },
                  );
                  await db.collection('notifications').add({
                    'type': 'permissionChanged',
                    'toUserId': m['uid'],
                    'toEmail': m['email'],
                    'fromUserId': _currentUser?.uid,
                    'groupId': widget.groupId,
                    'groupName': widget.groupName,
                    'canAssignTask': m['canAssignTask'],
                    'isRead': false,
                    'status': 'info',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }
                await batch.commit();
                if (mounted) {
                  Navigator.pop(ctx);
                  _showSnack('權限已更新');
                }
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.groupName),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // ─── 1. 編輯小組名稱 ─────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('編輯小組名稱'),
            onTap: _renameGroup,
          ),
          const Divider(indent: 16, endIndent: 16),
          
          // ─── 🎯 順序調整：已將「小組成員名單」成功移到「增加組員」的上方！ ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.groups_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '小組成員名單',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          // 實時雙重 StreamBuilder 成員監聽渲染區
          StreamBuilder<DocumentSnapshot>(
            stream: db.collection('groups').doc(widget.groupId).snapshots(),
            builder: (context, groupSnapshot) {
              if (groupSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
              }
              if (!groupSnapshot.hasData || !groupSnapshot.data!.exists) {
                return const SizedBox();
              }

              final groupData = groupSnapshot.data!.data() as Map<String, dynamic>;
              final List memberIds = groupData['memberIds'] ?? [];

              if (memberIds.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('目前小組內沒有成員', style: TextStyle(color: Colors.grey, fontSize: 13)),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: db.collection('users').where(FieldPath.documentId, whereIn: memberIds).snapshots(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
                  }
                  if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                    return const SizedBox();
                  }

                  final usersDocs = userSnapshot.data!.docs;

                  return ListView.builder(
                    shrinkWrap: true, 
                    physics: const NeverScrollableScrollPhysics(), 
                    itemCount: usersDocs.length,
                    itemBuilder: (context, index) {
                      final userData = usersDocs[index].data() as Map<String, dynamic>;
                      
                      final String nickname = userData['nickname'] ?? userData['displayName'] ?? userData['name'] ?? '未設定暱稱';
                      final String email = userData['email'] ?? '無 Email 資料';
                      final String uid = usersDocs[index].id;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4)),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text(
                              nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                              style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              if (uid == _currentUser?.uid) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('我', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold)),
                                ),
                              ]
                            ],
                          ),
                          subtitle: Text(email, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          
          // ─── 下半部：功能操作按鈕群 ──────────────────────────────────
          const Divider(indent: 16, endIndent: 16, height: 24),
          ListTile(
            leading: const Icon(Icons.person_add_rounded),
            title: const Text('增加組員'),
            onTap: _addMember,
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_rounded),
            title: const Text('刪除組員'),
            onTap: _removeMember,
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_rounded),
            title: const Text('更改權限'),
            onTap: _editPermissions,
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: Colors.red),
            title: const Text('刪除小組', style: TextStyle(color: Colors.red)),
            onTap: _deleteGroup,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}