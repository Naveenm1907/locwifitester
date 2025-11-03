import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../services/firebase_service.dart';
import '../admin/admin_home_screen.dart';
import '../student/student_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _departmentController = TextEditingController();
  
  UserRole _selectedRole = UserRole.student;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingAuth();
  }

  Future<void> _checkExistingAuth() async {
    final firebaseAuthUser = FirebaseService.instance.currentFirebaseUser;
    if (firebaseAuthUser != null) {
      // User is already authenticated, try to load user data
      try {
        final user = await FirebaseService.instance.getUser(firebaseAuthUser.uid);
        if (user != null && mounted) {
          final appState = Provider.of<AppState>(context, listen: false);
          appState.setCurrentUser(user);
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => user.role == UserRole.admin
                  ? const AdminHomeScreen()
                  : const StudentHomeScreen(),
            ),
          );
        }
      } catch (e) {
        // User document doesn't exist, stay on login screen
        // User can create account
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _studentIdController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final name = _nameController.text.trim();
      
      // Try to sign in with Firebase Auth (temporary password = email for demo)
      // In production, implement proper password handling
      User? user;
      auth.User? firebaseAuthUser;
      
      try {
        // Try to sign in first
        firebaseAuthUser = await FirebaseService.instance.signInWithEmailPassword(email, email);
        
        // Get user from Firestore using Firebase Auth UID
        if (firebaseAuthUser != null) {
          user = await FirebaseService.instance.getUser(firebaseAuthUser.uid);
        }
        
        // If user doesn't exist in Firestore but exists in Auth, create Firestore document
        if (user == null && firebaseAuthUser != null) {
          user = User(
            id: firebaseAuthUser.uid, // Use Firebase Auth UID!
            name: name,
            email: email,
            studentId: _selectedRole == UserRole.student 
                ? _studentIdController.text.trim() 
                : null,
            role: _selectedRole,
            department: _departmentController.text.trim().isEmpty 
                ? null 
                : _departmentController.text.trim(),
            createdAt: DateTime.now(),
          );
          await FirebaseService.instance.createUser(user);
        }
      } catch (e) {
        // User doesn't exist, create new account
        try {
          // Create Firebase Auth account
          firebaseAuthUser = await FirebaseService.instance.signUpWithEmailPassword(email, email);
          
          if (firebaseAuthUser == null) {
            throw Exception('Failed to create Firebase Auth account');
          }
          
          // Create user document in Firestore using Firebase Auth UID
          user = User(
            id: firebaseAuthUser.uid, // Use Firebase Auth UID instead of UUID!
            name: name,
            email: email,
            studentId: _selectedRole == UserRole.student 
                ? _studentIdController.text.trim() 
                : null,
            role: _selectedRole,
            department: _departmentController.text.trim().isEmpty 
                ? null 
                : _departmentController.text.trim(),
            createdAt: DateTime.now(),
          );

          await FirebaseService.instance.createUser(user);
        } catch (signUpError) {
          throw Exception('Failed to create account: $signUpError');
        }
      }

      if (user == null) {
        throw Exception('User not found after authentication');
      }

      if (mounted) {
        // Set current user in app state
        final appState = Provider.of<AppState>(context, listen: false);
        appState.setCurrentUser(user);

        // Navigate to appropriate home screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => user!.role == UserRole.admin
                ? const AdminHomeScreen()
                : const StudentHomeScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade700,
              Colors.blue.shade400,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 64,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'GeoAttendance',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Location-based Attendance System',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Select Role',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<UserRole>(
                                title: const Text('Student'),
                                value: UserRole.student,
                                groupValue: _selectedRole,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedRole = value!;
                                  });
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<UserRole>(
                                title: const Text('Admin'),
                                value: UserRole.admin,
                                groupValue: _selectedRole,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedRole = value!;
                                  });
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_selectedRole == UserRole.student) ...[
                          TextFormField(
                            controller: _studentIdController,
                            decoration: const InputDecoration(
                              labelText: 'Student ID / Roll Number',
                              prefixIcon: Icon(Icons.badge),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (_selectedRole == UserRole.student) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your student ID';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _departmentController,
                          decoration: const InputDecoration(
                            labelText: 'Department (Optional)',
                            prefixIcon: Icon(Icons.school),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Note: Existing users will be logged in automatically using their email.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

