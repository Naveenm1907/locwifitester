# Contributing to GeoAttendance

Thank you for considering contributing to GeoAttendance! This document provides guidelines and instructions for contributing.

## 🎯 Project Goals

This project aims to provide a production-ready, location-based attendance system that:
- Achieves 99% success rate in marking attendance
- Works reliably in various indoor/outdoor environments
- Provides excellent user experience for both admins and students
- Remains simple to deploy and maintain

## 🏗️ Development Setup

### Prerequisites
- Flutter SDK 3.9.2+
- Android Studio or VS Code with Flutter extensions
- Physical devices for testing (GPS/WiFi required)
- Git for version control

### Setup
```bash
git clone <repository-url>
cd locwifitester
flutter pub get
```

## 📁 Project Structure

```
lib/
├── models/              # Data models
│   ├── user.dart
│   ├── room.dart
│   ├── wifi_router.dart
│   └── attendance.dart
├── services/            # Business logic
│   ├── database_service.dart
│   └── location_service.dart
├── providers/           # State management
│   └── app_state.dart
├── screens/             # UI screens
│   ├── auth/
│   ├── admin/
│   └── student/
├── utils/               # Utility functions
│   └── coordinate_calculator.dart
└── main.dart           # App entry point
```

## 🔧 Code Style

### Dart/Flutter Conventions
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use `flutter analyze` before committing
- Format code with `dart format .`
- Maximum line length: 100 characters

### Naming Conventions
- Classes: `PascalCase` (e.g., `LocationService`)
- Variables/Functions: `camelCase` (e.g., `getCurrentLocation`)
- Constants: `lowerCamelCase` (e.g., `earthRadius`)
- Files: `snake_case` (e.g., `location_service.dart`)

### Comments
```dart
/// Public API documentation (three slashes)
/// 
/// Detailed description with examples
double calculateDistance(double lat1, double lng1) {
  // Implementation comments (two slashes)
  final distance = ...
  return distance;
}
```

## 🧪 Testing

### Manual Testing Checklist
Before submitting a PR, test:
- [ ] Admin can add/edit/delete rooms
- [ ] Admin can add/edit/delete WiFi routers
- [ ] Student can view available rooms
- [ ] Student can mark attendance successfully
- [ ] GPS verification works
- [ ] WiFi fallback works
- [ ] Duplicate attendance is prevented
- [ ] UI is responsive on different screen sizes

### Test on Multiple Scenarios
- Different GPS accuracies (high, medium, low)
- Different environments (outdoor, indoor, basement)
- With and without WiFi
- Edge cases (permissions denied, location disabled)

## 🐛 Bug Reports

When reporting bugs, include:

### Required Information
1. **Device Information**
   - Device model
   - OS version (Android/iOS)
   - App version

2. **Steps to Reproduce**
   - Clear, numbered steps
   - Expected behavior
   - Actual behavior

3. **Logs/Screenshots**
   - Error messages
   - Screenshots of the issue
   - Relevant console output

### Example Bug Report
```markdown
**Bug**: Attendance verification fails in Room 101

**Device**: Samsung Galaxy S21, Android 12

**Steps to Reproduce**:
1. Login as student
2. Navigate to Room 101
3. Tap "Mark Attendance"
4. Wait for verification

**Expected**: Attendance marked successfully
**Actual**: Shows "Location verification failed"

**GPS Accuracy**: 15m
**WiFi**: Enabled, 3 networks detected
**Screenshot**: [attached]
```

## ✨ Feature Requests

When requesting features:

1. **Problem Statement**: What problem does this solve?
2. **Proposed Solution**: How would it work?
3. **Use Case**: Real-world scenario
4. **Impact**: Who benefits and how?

### Example Feature Request
```markdown
**Feature**: Export attendance reports as PDF

**Problem**: Admins need to share attendance with management

**Solution**: Add "Export" button in admin dashboard that generates PDF report

**Use Case**: 
- Monthly attendance reports for management
- Individual student reports for parents
- Archive records for audit

**Impact**: 
- Saves admin time (no manual report creation)
- Professional presentation
- Easy record keeping
```

## 🔄 Pull Request Process

### Before Creating PR

1. **Create Feature Branch**
```bash
git checkout -b feature/your-feature-name
```

2. **Make Changes**
   - Write clean, documented code
   - Follow code style guidelines
   - Test thoroughly

3. **Commit**
```bash
git add .
git commit -m "feat: add PDF export functionality"
```

### Commit Message Format
Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: fix a bug
docs: documentation changes
style: formatting, missing semicolons, etc
refactor: code restructuring
test: adding tests
chore: maintenance tasks
```

### Creating the PR

1. Push your branch
```bash
git push origin feature/your-feature-name
```

2. Create PR on GitHub/GitLab
   - Clear title describing the change
   - Reference any related issues
   - Provide detailed description
   - Add screenshots/videos if UI changes

3. PR Description Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tested on Android
- [ ] Tested on iOS
- [ ] Tested different scenarios

## Screenshots
[If applicable]

## Related Issues
Fixes #123
```

### PR Review Process

1. Automated checks must pass
2. Code review by maintainer
3. Address review comments
4. Maintainer merges PR

## 🎨 UI/UX Guidelines

### Design Principles
1. **Simplicity**: Easy to use for non-technical users
2. **Clarity**: Clear feedback on all actions
3. **Consistency**: Uniform design across screens
4. **Accessibility**: Readable text, good contrast

### Material Design
- Follow Material Design 3 guidelines
- Use consistent spacing (8dp grid)
- Use theme colors from `main.dart`
- Provide loading indicators for async operations

### User Feedback
- Show loading states
- Display success/error messages
- Confirm destructive actions
- Provide helpful error messages

## 🔐 Security Guidelines

### Data Handling
- Never log sensitive user data
- Use parameterized queries (SQLite)
- Validate all user input
- Handle permissions gracefully

### Location Data
- Request minimum necessary permissions
- Explain why permissions are needed
- Handle permission denial gracefully
- Don't store unnecessary location history

## 📚 Documentation

### Code Documentation
- Document all public APIs
- Include parameter descriptions
- Provide usage examples
- Explain complex algorithms

### User Documentation
- Update README.md for new features
- Update SETUP_GUIDE.md if setup changes
- Include screenshots for UI changes
- Explain configuration options

## 🚀 Release Process

### Version Numbering
Follow [Semantic Versioning](https://semver.org/):
- MAJOR.MINOR.PATCH (e.g., 1.2.3)
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes

### Release Checklist
- [ ] Update version in `pubspec.yaml`
- [ ] Update CHANGELOG.md
- [ ] Test on multiple devices
- [ ] Build release APK/IPA
- [ ] Test release build
- [ ] Create GitHub release
- [ ] Update Play Store/App Store

## 💡 Tips for Contributors

### Good First Issues
Look for issues labeled:
- `good-first-issue`: Good for newcomers
- `help-wanted`: Need community help
- `documentation`: Improve docs

### Getting Help
- Check existing issues and PRs
- Read the documentation thoroughly
- Ask in issue comments
- Be patient and respectful

### Code Review
- Reviews improve code quality
- Don't take feedback personally
- Explain your reasoning
- Be open to suggestions

## 🙏 Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Credited in release notes
- Mentioned in project documentation

Thank you for contributing to GeoAttendance! 🎉

