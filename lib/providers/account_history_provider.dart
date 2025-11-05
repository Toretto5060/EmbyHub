import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountRecord {
  final String serverUrl;
  final String username;
  final String? lastToken;

  AccountRecord({
    required this.serverUrl,
    required this.username,
    this.lastToken,
  });

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'lastToken': lastToken,
      };

  factory AccountRecord.fromJson(Map<String, dynamic> json) => AccountRecord(
        serverUrl: json['serverUrl'] as String,
        username: json['username'] as String,
        lastToken: json['lastToken'] as String?,
      );
}

class AccountHistoryNotifier extends StateNotifier<List<AccountRecord>> {
  AccountHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('account_history');
    if (json != null) {
      final list = (jsonDecode(json) as List)
          .map((e) => AccountRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    }
  }

  Future<void> addAccount(String serverUrl, String username, String? token) async {
    // Remove existing record with same server+username
    state = state.where((a) => !(a.serverUrl == serverUrl && a.username == username)).toList();
    // Add to front
    state = [
      AccountRecord(serverUrl: serverUrl, username: username, lastToken: token),
      ...state,
    ];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString('account_history', json);
  }

  List<AccountRecord> getAccountsForServer(String serverUrl) {
    return state.where((a) => a.serverUrl == serverUrl).toList();
  }

  Future<void> removeAccount(String serverUrl, String username) async {
    state = state.where((a) => !(a.serverUrl == serverUrl && a.username == username)).toList();
    await _save();
  }
}

final accountHistoryProvider =
    StateNotifierProvider<AccountHistoryNotifier, List<AccountRecord>>((ref) {
  return AccountHistoryNotifier();
});

