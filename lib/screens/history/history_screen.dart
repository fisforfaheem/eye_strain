import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:eye_strain/models/eye_check.dart';
import 'package:eye_strain/services/auth_service.dart';
import 'package:eye_strain/services/eye_strain_service.dart';

/// Screen that displays the history of eye strain checks
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _eyeStrainService = EyeStrainService();
  List<EyeCheck> _checks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId == null) return;

    setState(() => _isLoading = true);
    try {
      final checks = await _eyeStrainService.getLocalEyeCheckHistory(userId);
      if (mounted) {
        setState(() {
          _checks = checks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading history: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthService>().currentUser?.uid;

    if (userId == null) {
      return const Center(child: Text('Not logged in'));
    }

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHistory),
        ],
      ),
      body:
          _checks.isEmpty
              ? const Center(child: Text('No eye strain checks yet'))
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _checks.length,
                itemBuilder: (context, index) {
                  final check = _checks[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      leading: Icon(
                        check.needsBreak
                            ? Icons.warning_rounded
                            : Icons.check_circle_rounded,
                        color: check.needsBreak ? Colors.orange : Colors.green,
                        size: 32,
                      ),
                      title: Text(
                        check.needsBreak ? 'Break Needed' : 'Eyes Looking Good',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        DateFormat('MMM d, y - h:mm a').format(check.timestamp),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Delete Check'),
                                  content: const Text(
                                    'Are you sure you want to delete this check?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                          );

                          if (confirmed == true) {
                            await _eyeStrainService.deleteEyeCheck(check);
                            _loadHistory(); // Reload the list
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
