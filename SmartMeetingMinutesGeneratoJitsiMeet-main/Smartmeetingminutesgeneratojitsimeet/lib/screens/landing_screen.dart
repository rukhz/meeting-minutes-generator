// Landing screen: Welcome card + Quick Actions.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'meeting_home_page.dart';

class LandingScreen extends StatelessWidget {
  final User? user;
  final bool isLoading;

  const LandingScreen({super.key, this.user, this.isLoading = false});

  String get displayName => user?.displayName ?? user?.email?.split('@').first ?? 'Guest';

  static const Color _headerBlue = Color(0xFF2196F3);
  static const Color _lightBlueGradientStart = Color(0xFFE3F2FD);
  static const Color _lightBlueGradientEnd = Color(0xFFF5F5F5);
  static const Color _quickActionBlue = Color(0xFF64B5F6);
  static const Color _quickActionGreen = Color(0xFF4CAF50);
  static const Color _quickActionOrange = Color(0xFFFF9800);
  static const Color _quickActionPurple = Color(0xFF9C27B0);

  void _goToMeetings(BuildContext context, {bool scrollToRecordings = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeetingHomePage(
          scrollToRecordings: scrollToRecordings,
          currentUser: user,
        ),
      ),
    );
  }

  void _goToLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          onSignInSuccess: (ctx) => Navigator.of(ctx).popUntil((r) => r.isFirst),
          onSignUpTap: (ctx) {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RegisterPage(
                  onRegisterSuccess: (ctx) => Navigator.of(ctx).popUntil((r) => r.isFirst),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _goToRegister(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterPage(
          onRegisterSuccess: (ctx) => Navigator.of(ctx).popUntil((r) => r.isFirst),
        ),
      ),
    );
  }

  void _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
  }


  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
              'Server URLs and recording options are configured on the Meeting screen when you tap "New Meeting".',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Help'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Meeting: Create a meeting and join via Jitsi.'),
              const SizedBox(height: 8),
              const Text('Past Meetings: View and play your recordings.'),
              const SizedBox(height: 8),
              const Text(
                'For bot recording: Start the bot server on your PC, set Server URL to http://PC_IP:3000, enable "Bot recording".',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _headerBlue,
        centerTitle: true,
        title: const Text(
          'Smart Meeting Minutes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => _logout(context),
              tooltip: 'Logout',
            )
          else
            IconButton(
              icon: const Icon(Icons.login, color: Colors.white),
              onPressed: () => _goToLogin(context),
              tooltip: 'Login',
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_lightBlueGradientStart, _lightBlueGradientEnd],
          ),
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _headerBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.menu, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user != null ? 'Welcome back!' : 'Welcome!',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user != null ? displayName : 'Login to sync recordings to cloud',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.black54,
                                      ),
                                ),
                                if (user == null) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () => _goToLogin(context),
                                        child: const Text('Login'),
                                      ),
                                      TextButton(
                                        onPressed: () => _goToRegister(context),
                                        child: const Text('Register'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              const SizedBox(height: 24),
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.add,
                      label: 'New Meeting',
                      color: _quickActionBlue,
                      onTap: () => _goToMeetings(context, scrollToRecordings: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.history,
                      label: 'Past Meetings',
                      color: _quickActionGreen,
                      onTap: () => _goToMeetings(context, scrollToRecordings: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.settings,
                      label: 'Settings',
                      color: _quickActionOrange,
                      onTap: () => _showSettings(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.help_outline,
                      label: 'Help',
                      color: _quickActionPurple,
                      onTap: () => _showHelp(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      shadowColor: Colors.black26,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
