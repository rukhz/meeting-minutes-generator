// Widget tests for Smart Meeting Minutes app.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartmeetingminutesgeneratojitsimeet/providers/auth_provider.dart';
import 'package:smartmeetingminutesgeneratojitsimeet/screens/landing_screen.dart';

void main() {
  testWidgets('LandingScreen displays correctly with null user',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: LandingScreen(user: null, isLoading: false),
        ),
      ),
    );

    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Login to sync recordings to cloud'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('New Meeting'), findsOneWidget);
    expect(find.text('Past Meetings'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
  });

  testWidgets('LandingScreen displays correctly with mock signed-in user',
      (WidgetTester tester) async {
    final mockUser = MockUser(
      uid: 'test-uid',
      email: 'test@example.com',
      displayName: 'Test User',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: LandingScreen(user: mockUser, isLoading: false),
        ),
      ),
    );

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Test User'), findsOneWidget);
  });

  testWidgets('LandingScreen handles user with null email and displayName safely',
      (WidgetTester tester) async {
    final mockUser = MockUser(
      uid: 'test-uid',
      email: null,
      displayName: null,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: LandingScreen(user: mockUser, isLoading: false),
        ),
      ),
    );

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('LandingScreen shows loading indicator when isLoading is true',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: LandingScreen(user: null, isLoading: true),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
