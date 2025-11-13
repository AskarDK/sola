// lib/login.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'index.dart' show AuthCheckPage;
import 'app_theme.dart';
import 'auth_api.dart';
import 'package:dio/dio.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _api = AuthApi();
  final _pageController = PageController();

  // --- Контроллеры и ключи ---
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController(); // Date of Birth
  final _regPasswordController = TextEditingController();

  late final AnimationController _shakeController;

  // --- Состояние ---
  bool _isEmailLoading = false;
  bool _isLoggingIn = false;
  bool _isRegistering = false;
  Map<String, dynamic>? _fetchedUserData;
  String _errorMessage = '';

  // --- 1. ИЗМЕНЕНИЕ: Пол теперь nullable ---
  String? _selectedSex;

  bool _consentGiven = false;

  // --- 2. НОВОЕ СОСТОЯНИЕ: Согласие на лицо ---
  bool _faceConsentGiven = false;

  int _registrationStep = 0;
  // (Имя -> ДР -> Пол -> Пароль/Согласие)
  final int _totalRegistrationSteps = 4; // Стало 4 шага

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _shakeController.dispose();
    _nameController.dispose();
    _dobController.dispose();
    _regPasswordController.dispose();
    super.dispose();
  }

  /// Анимированный переход к следующей странице
  void _goToPage(int page) {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Запускает анимацию "встряхивания"
  void _triggerShakeAnimation() {
    _shakeController.forward(from: 0.0);
  }

  /// Шаг 1: Нажата кнопка "Начать" на первом экране
  void _onShowLogin() {
    _goToPage(1);
  }

  /// Шаг 3: Нажата кнопка "Продолжить" с email
  Future<void> _onEmailContinue() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isEmailLoading = true;
      _errorMessage = '';
    });

    try {
      final email = _emailController.text.trim();
      final userData = await _api.checkUserEmail(email);

      // Пользователь НАЙДЕН - переход на экран пароля
      setState(() {
        _fetchedUserData = userData;
        _isEmailLoading = false;
      });

      _goToPage(2);
    } on DioException catch (e) {
      final error = e.response?.data?['error']?.toString() ?? 'UNKNOWN_ERROR';

      if (error == 'USER_NOT_FOUND') {
        // Пользователь НЕ НАЙДЕН - переход на экран регистрации
        setState(() {
          _isEmailLoading = false;
          _errorMessage = '';
          _registrationStep = 0; // Сбрасываем шаги
        });
        _goToPage(3); // <-- ПЕРЕХОД НА НОВЫЙ ЭКРАН РЕГИСТРАЦИИ
      } else {
        // Другая ошибка
        setState(() {
          _errorMessage =
              e.response?.data?['error']?.toString() ?? 'Ошибка сети';
          _isEmailLoading = false;
        });
        _triggerShakeAnimation();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Произошла ошибка: $e';
        _isEmailLoading = false;
      });
      _triggerShakeAnimation();
    }
  }

  /// Шаг 4: Нажата кнопка "Войти" с паролем
  Future<void> _onPasswordLogin() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() {
      _isLoggingIn = true;
      _errorMessage = '';
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      await _api.login(email, password);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthCheckPage()),
      );
    } on DioException catch (e) {
      setState(() {
        _errorMessage =
            e.response?.data?['error']?.toString() ?? 'Неверный пароль';
        _isLoggingIn = false;
      });
      _triggerShakeAnimation();
    } catch (e) {
      setState(() {
        _errorMessage = 'Произошла ошибка: $e';
        _isLoggingIn = false;
      });
      _triggerShakeAnimation();
    }
  }

  /// Шаг 5: Нажата кнопка "Войти с Google"
  void _onGoogleLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Вход через Google скоро появится!')),
    );
  }

  /// Выбор даты
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
      _goToRegistrationStep(_registrationStep + 1);
    }
  }

  /// Переход по шагам регистрации
  void _goToRegistrationStep(int step) {
    if (step < 0) {
      _goToPage(1); // Назад на экран Email
      return;
    }
    // Валидация текущего шага перед переходом
    if (step > _registrationStep) {
      // --- 3. ИЗМЕНЕНИЕ: Добавлена проверка _selectedSex ---
      if (_registrationStep == 2 && _selectedSex == null) {
        setState(() => _errorMessage = 'Пожалуйста, выберите ваш пол');
        _triggerShakeAnimation();
        return;
      }
      if (!_registerFormKey.currentState!.validate()) {
        _triggerShakeAnimation();
        return;
      }
    }
    setState(() => _errorMessage = ''); // Сбрасываем ошибку при переходе
    setState(() {
      _registrationStep = step;
    });
  }

  /// Регистрация
  Future<void> _onRegister() async {
    if (!_registerFormKey.currentState!.validate()) {
      _triggerShakeAnimation();
      return;
    }

    if (!_consentGiven) {
      setState(() => _errorMessage = 'Необходимо принять согласие на обработку данных');
      _triggerShakeAnimation();
      return;
    }
    // (Согласие на лицо _faceConsentGiven опционально)

    setState(() {
      _isRegistering = true;
      _errorMessage = '';
    });

    try {
      // --- 4. ИЗМЕНЕНИЕ: Передаем _faceConsentGiven в API ---
      await _api.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _regPasswordController.text,
        dateOfBirth: _dobController.text.trim(),
        sex: _selectedSex!, // ! - т.к. мы уже проверили на шаге 2
        faceConsent: _faceConsentGiven, // <-- НОВОЕ ПОЛЕ
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthCheckPage()),
      );
    } on DioException catch (e) {
      setState(() {
        _errorMessage =
            e.response?.data?['errors']?.toString() ?? 'Ошибка регистрации';
        _isRegistering = false;
      });
      _triggerShakeAnimation();
    } catch (e) {
      setState(() {
        _errorMessage = 'Произошла ошибка: $e';
        _isRegistering = false;
      });
      _triggerShakeAnimation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildWelcomeScreen(),
            _buildEmailScreen(),
            _buildPasswordScreen(),
            _buildRegisterScreen(), // <-- Главный экран регистрации
          ],
        ),
      ),
    );
  }

  /// ЭКРАН 1: Приветствие
  Widget _buildWelcomeScreen() {
    // ... (код без изменений) ...
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.pageBackground,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            child: Transform.scale(
              scale: 1.15,
              child: Image.asset(
                'assets/sola_visualization.png',
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Добро пожаловать в Sola',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neutral900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ваш помощник для здоровой жизни без лишних трудностей',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.neutral600,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _onShowLogin,
                    child: const Text('Начать'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _onGoogleLogin,
                    icon: Image.asset('assets/google_logo.png',
                        height: 20, width: 20),
                    label: const Text('Войти через Google'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.neutral700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ЭКРАН 2: Ввод Email
  Widget _buildEmailScreen() {
    // ... (код без изменений) ...
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          final double offset =
              math.sin(_shakeController.value * math.pi * 6.0) * 12.0;
          return Transform.translate(
            offset: Offset(offset, 0),
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.neutral500),
              onPressed: () => _goToPage(0),
            ),
            const SizedBox(height: 16),
            const Text(
              'Вход или Регистрация',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.neutral900,
              ),
            ),
            const SizedBox(height: 24),
            Form(
              key: _emailFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Email',
                      style: TextStyle(
                          color: AppColors.neutral600,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: kiloInput('you@example.com'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Введите email';
                      final ok =
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
                      if (!ok) return 'Некорректный email';
                      return null;
                    },
                    onFieldSubmitted: (_) => _onEmailContinue(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isEmailLoading ? null : _onEmailContinue,
                child: _isEmailLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white),
                )
                    : const Text('Продолжить'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                Expanded(child: Divider(color: AppColors.neutral200)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text('ИЛИ',
                      style: TextStyle(
                          color: AppColors.neutral400,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Divider(color: AppColors.neutral200)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _onGoogleLogin,
                icon: Image.asset('assets/google_logo.png',
                    height: 20, width: 20),
                label: const Text('Войти с Google'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.neutral700,
                ),
              ),
            ),
            const Spacer(),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: Center(
                child: _errorMessage.isNotEmpty
                    ? Text(_errorMessage,
                    style: const TextStyle(
                        color: AppColors.red, fontWeight: FontWeight.w600))
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ЭКРАН 3: Ввод Пароля
  Widget _buildPasswordScreen() {
    // ... (код без изменений) ...
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.neutral500),
            onPressed: () {
              setState(() => _errorMessage = '');
              _goToPage(1);
            },
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final double offset =
                  math.sin(_shakeController.value * math.pi * 6.0) * 12.0;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: _buildPasswordForm(),
          ),
          const Spacer(),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: Center(
              child: _errorMessage.isNotEmpty
                  ? Text(_errorMessage,
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w600))
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// Форма ввода пароля
  Widget _buildPasswordForm() {
    // ... (код без изменений) ...
    final String avatarFilename = _fetchedUserData?['avatar_filename'] ?? '';
    final String userName = _fetchedUserData?['name'] ?? 'Пользователь';
    final String placeholder =
    (userName.isNotEmpty ? userName[0] : 'U').toUpperCase();

    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: double.infinity),
        CircleAvatar(
          radius: 40,
          backgroundColor: AppColors.neutral100,
          child: avatarFilename.isNotEmpty
              ? ClipOval(
            child: Image.network(
              '${AuthApi.baseUrl}/files/$avatarFilename',
              fit: BoxFit.cover,
              width: 80,
              height: 80,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Skeleton(width: 80, height: 80, radius: 40);
              },
              errorBuilder: (context, _, __) => Text(placeholder,
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
          )
              : Text(placeholder,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
        ),
        const SizedBox(height: 16),
        Text(
          'С возвращением, $userName!',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.neutral900,
          ),
        ),
        const SizedBox(height: 32),
        Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Пароль',
                  style: TextStyle(
                      color: AppColors.neutral600,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: kiloInput('Ваш пароль'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Введите пароль';
                  return null;
                },
                onFieldSubmitted: (_) => _onPasswordLogin(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoggingIn ? null : _onPasswordLogin,
            child: _isLoggingIn
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Colors.white),
            )
                : const Text('Войти'),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Функция "Забыл пароль" еще не реализована.')),
              );
            },
            child: const Text('Забыл пароль?'),
          ),
        ),
      ],
    );
  }

  /// ЭКРАН 4: Пошаговая регистрация
  Widget _buildRegisterScreen() {
    // Определяем, какой виджет показать в зависимости от шага
    Widget currentStepWidget;
    switch (_registrationStep) {
      case 0:
        currentStepWidget = _buildRegisterStepName();
        break;
      case 1:
        currentStepWidget = _buildRegisterStepDOB();
        break;
    // --- 5. ИЗМЕНЕНИЕ: Новый шаг выбора пола ---
      case 2:
        currentStepWidget = _buildRegisterStepSex();
        break;
    // --- 6. ИЗМЕНЕНИЕ: Шаг пароля и согласия объединен ---
      case 3:
        currentStepWidget = _buildRegisterStepPasswordAndConsent();
        break;
      default:
        currentStepWidget = _buildRegisterStepName();
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Кнопка Назад
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.neutral500),
            onPressed: () {
              setState(() => _errorMessage = '');
              _goToRegistrationStep(_registrationStep - 1);
            },
          ),
          const SizedBox(height: 8),

          // Индикатор прогресса
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_registrationStep + 1) / _totalRegistrationSteps,
                minHeight: 6,
                backgroundColor: AppColors.neutral200,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Обертка для анимаций
          Expanded(
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final double offset =
                    math.sin(_shakeController.value * math.pi * 6.0) * 12.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Form(
                key: _registerFormKey,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child:
                  currentStepWidget, // Показываем текущий шаг
                ),
              ),
            ),
          ),

          // Анимированное появление ошибки
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: Center(
              child: _errorMessage.isNotEmpty
                  ? Text(
                _errorMessage,
                style: const TextStyle(
                    color: AppColors.red, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// Шаг 4.0: Имя
  Widget _buildRegisterStepName() {
    // ... (код без изменений) ...
    return ListView(
      key: const ValueKey('step_name'),
      children: [
        const Text(
          'Как вас зовут?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.neutral900,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Это имя будет отображаться в вашем профиле.',
          style: TextStyle(fontSize: 16, color: AppColors.neutral600),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _nameController,
          decoration: kiloInput('Ваше имя'),
          validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Введите ваше имя' : null,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onFieldSubmitted: (_) => _goToRegistrationStep(_registrationStep + 1),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => _goToRegistrationStep(_registrationStep + 1),
          child: const Text('Продолжить'),
        ),
      ],
    );
  }

  /// Шаг 4.1: Дата Рождения
  Widget _buildRegisterStepDOB() {
    // ... (код без изменений) ...
    return ListView(
      key: const ValueKey('step_dob'),
      children: [
        const Text(
          'Когда вы родились?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.neutral900,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Это поможет нам точнее рассчитывать ваши показатели.',
          style: TextStyle(fontSize: 16, color: AppColors.neutral600),
        ),
        const SizedBox(height: 32),
        InkWell(
          onTap: () => _selectDate(context),
          child: AbsorbPointer(
            child: TextFormField(
              controller: _dobController,
              decoration: kiloInput('ГГГГ-ММ-ДД').copyWith(
                suffixIcon: const Icon(Icons.calendar_today_rounded),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Выберите дату';
                final ok =
                RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v.trim());
                if (!ok) return 'Неверный формат';
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }

  // --- 7. НОВЫЙ "КРАСИВЫЙ" ВЫБОР ПОЛА ---
  Widget _buildRegisterStepSex() {
    return ListView(
      key: const ValueKey('step_sex'),
      children: [
        const Text(
          'Укажите ваш пол',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.neutral900,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Это необходимо для корректного расчета AI-моделями.',
          style: TextStyle(fontSize: 16, color: AppColors.neutral600),
        ),
        const SizedBox(height: 32),

        // "Красивая" кнопка "Мужской"
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration( //
            borderRadius: BorderRadius.circular(18),
            // Эффект тени для выделения
            boxShadow: _selectedSex == 'male' ? [
              BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
            ] : [],
          ),
          child: KiloCard(
            borderColor: _selectedSex == 'male' ? AppColors.primary : AppColors.neutral200,
            color: _selectedSex == 'male' ? AppColors.primary.withOpacity(0.05) : AppColors.cardBackground,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                setState(() => _selectedSex = 'male');
                Future.delayed(const Duration(milliseconds: 200),
                        () => _goToRegistrationStep(_registrationStep + 1));
              },
              borderRadius: BorderRadius.circular(18),
              child: const ListTile(
                title: Text('Мужской', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.male_rounded, color: AppColors.primary, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // "Красивая" кнопка "Женский"
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _selectedSex == 'female' ? [
              BoxShadow(color: AppColors.secondary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
            ] : [],
          ),
          child: KiloCard(
            borderColor: _selectedSex == 'female' ? AppColors.secondary : AppColors.neutral200,
            color: _selectedSex == 'female' ? AppColors.secondary.withOpacity(0.05) : AppColors.cardBackground,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                setState(() => _selectedSex = 'female');
                Future.delayed(const Duration(milliseconds: 200),
                        () => _goToRegistrationStep(_registrationStep + 1));
              },
              borderRadius: BorderRadius.circular(18),
              child: const ListTile(
                title: Text('Женский', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.female_rounded, color: AppColors.secondary, size: 28),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- 8. ОБЪЕДИНЕННЫЙ ШАГ ПАРОЛЯ И СОГЛАСИЙ ---
  Widget _buildRegisterStepPasswordAndConsent() {
    return ListView(
      key: const ValueKey('step_password_consent'),
      children: [
        const Text(
          'Последний шаг',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.neutral900,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Создайте пароль и примите условия.',
          style: TextStyle(fontSize: 16, color: AppColors.neutral600),
        ),
        const SizedBox(height: 32),
        // Пароль
        TextFormField(
          controller: _regPasswordController,
          obscureText: true,
          decoration: kiloInput('Пароль (мин. 6 символов)'),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Введите пароль';
            if (v.length < 6) return 'Пароль должен быть минимум 6 символов';
            return null;
          },
          autofocus: true,
          onFieldSubmitted: (_) => _onRegister(),
        ),
        const SizedBox(height: 24),

        // --- 9. ОБА ЧЕКБОКСА ЗДЕСЬ ---
        // Обязательное согласие
        KiloCard(
          borderColor: _consentGiven ? AppColors.green : AppColors.neutral200,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: CheckboxListTile(
            title: const Text('Я даю согласие на обработку персональных данных',
                style: TextStyle(
                    color: AppColors.neutral600, fontSize: 14)),
            value: _consentGiven,
            onChanged: (val) {
              setState(() => _consentGiven = val ?? false);
            },
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.green,
          ),
        ),
        const SizedBox(height: 12),

        // Опциональное согласие на лицо
        KiloCard(
          borderColor: _faceConsentGiven ? AppColors.primary : AppColors.neutral200,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: CheckboxListTile(
            title: const Text('Разрешить AI-визуализацию',
                style: TextStyle(
                    color: AppColors.neutral600, fontSize: 14)),
            subtitle: const Text('Дает согласие на использование вашего аватара для создания AI-визуализаций тела.',
                style: TextStyle(
                    color: AppColors.neutral500, fontSize: 12)),
            value: _faceConsentGiven,
            onChanged: (val) {
              setState(() => _faceConsentGiven = val ?? false);
            },
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
          ),
        ),

        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _isRegistering ? null : _onRegister,
          child: _isRegistering
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: Colors.white),
          )
              : const Text('Завершить регистрацию'),
        ),
      ],
    );
  }
}