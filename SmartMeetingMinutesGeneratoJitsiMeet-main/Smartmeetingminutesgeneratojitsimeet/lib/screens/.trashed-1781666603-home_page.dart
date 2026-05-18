import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// Dashboard homepage: welcome card, Quick Actions grid.
class HomePage extends StatelessWidget {
  final void Function(BuildContext context) onGoToMeetings;
  final void Function(BuildContext context) onGoToPastMeetings;
  final void Function(BuildContext context)? onSettings;
  final void Function(BuildContext context)? onHelp;

  const HomePage({
    super.key,
    required this.onGoToMeetings,
    required this.onGoToPastMeetings,
    this.onSettings,
    this.onHelp,
  });

  static const Color _headerBlue = Color(0xFF2196F3);
  static const Color _lightBlueGradientStart = Color(0xFFE3F2FD);
  static const Color _lightBlueGradientEnd = Color(0xFFF5F5F5);
  static const Color _quickActionLightBlue = Color(0xFF64B5F6);
  static const Color _quickActionGreen = Color(0xFF4CAF50);
  static const Color _quickActionOrange = Color(0xFFFF9800);
  static const Color _quickActionPurple = Color(0xFF9C27B0);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _headerBlue,
        centerTitle: true,
        title: const Text(
          'Smart Meeting Minutes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: () {},
            tooltip: 'Profile',
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome card
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
                      child: const Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back!',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.black54,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Quick Actions heading
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              const SizedBox(height: 16),
              // 2x2 grid
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.add,
                      label: 'New Meeting',
                      color: _quickActionLightBlue,
                      onTap: () => onGoToMeetings(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.history,
                      label: 'Past Meetings',
                      color: _quickActionGreen,
                      onTap: () => onGoToPastMeetings(context),
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
                      onTap: () => (onSettings ?? (_) {})(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.help_outline,
                      label: 'Help',
                      color: _quickActionPurple,
                      onTap: () => (onHelp ?? (_) {})(context),
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
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
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
