import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eye_strain/services/auth_service.dart';
import 'package:eye_strain/services/eye_strain_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Profile screen for user settings
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _clearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear History'),
            content: const Text(
              'Are you sure you want to clear all your eye strain check history? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final eyeChecksDir = Directory('${directory.path}/eye_checks');

      if (await eyeChecksDir.exists()) {
        await eyeChecksDir.delete(recursive: true);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History cleared successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error clearing history: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 40,
                    child: Icon(Icons.person, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text('Email', style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    user?.email ?? 'No email',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Settings Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  trailing: Switch(
                    value: true, // TODO: Implement notifications
                    onChanged: (value) {
                      // TODO: Implement notifications toggle
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Check Interval'),
                  subtitle: const Text('Every 30 minutes'),
                  onTap: () {
                    // TODO: Implement check interval settings
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Clear History'),
                  onTap: () => _clearHistory(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Danger Zone
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () => context.read<AuthService>().signOut(),
            ),
          ),
        ],
      ),
    );
  }
}
