import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart'; // <-- 1. ДОБАВЛЕННЫЙ ИМПОРТ
import 'dart:convert';

class AuthApi {
  static final AuthApi _instance = AuthApi._internal();
  factory AuthApi() => _instance;
  AuthApi._internal();

  late Dio dio;
  PersistCookieJar? _cookieJar;

  // Укажи здесь адрес твоего Flask
  static const String baseUrl = 'http://192.168.10.3:5000'; // Android эмулятор
  // Для реального девайса в одной сети поставь IP твоей машины, напр. 'http://192.168.0.101:5000'

  Future<void> init() async {
    if (_cookieJar != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(storage: FileStorage('${dir.path}/.cookies/'));
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.acceptHeader: 'application/json',
      },
      // важно: позволяем cookie работать
      validateStatus: (code) => code != null && code < 600,
    ))
      ..interceptors.add(CookieManager(_cookieJar!));
  }

  // (Добавьте это в класс AuthApi в lib/auth_api.dart)

  /// Загружает фото анализа тела и возвращает извлеченные метрики.
  /// Соответствует вызову POST /upload_analysis
  Future<Map<String, dynamic>> uploadBodyAnalysis(File imageFile) async {
    await init();

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });

    final res = await dio.post(
      '/upload_analysis',
      data: formData,
      options: Options(
        headers: {
          HttpHeaders.contentTypeHeader: 'multipart/form-data',
        },
      ),
    );

    // Ожидаем, что бэк вернет {"success": true, "data": {...}}
    if (res.statusCode == 200 && res.data['success'] == true) {
      if (res.data['data'] != null) {
        return Map<String, dynamic>.from(res.data['data']);
      } else {
        throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          error: 'Backend returned success but no data.',
          type: DioExceptionType.badResponse,
        );
      }
    }

    final error = res.data is Map && res.data['error'] != null
        ? res.data['error']
        : 'Failed to upload analysis';
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: error,
      type: DioExceptionType.badResponse,
    );
  }

  /// Управляет подпиской (заморозка/разморозка)
  /// action: 'freeze' или 'unfreeze'
  Future<void> manageSubscription(String action) async {
    await init();
    final res = await dio.post(
      '/subscription/manage', // <-- Эндпоинт из app.py
      data: {'action': action},
      options: Options(
        // Бэкенд ожидает form data, а не JSON
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    // Бэкенд в случае успеха делает редирект (302) или возвращает ошибку
    if (res.statusCode != 302 && res.statusCode != 200) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        error: res.data?['error'] ?? 'Не удалось выполнить действие',
        type: DioExceptionType.badResponse,
      );
    }
  }

  Future<void> completeOnboarding() async {
    await init();
    try {
      // Вызываем эндпоинт, который установит user.onboarding_complete = True
      await dio.post('/api/onboarding/complete');
    } catch (e) {
      // Ошибку можно проигнорировать, в худшем случае онбординг покажется еще раз
      print('Failed to complete onboarding: $e');
    }
  }

  /// Отправляет заявку на подписку
  Future<Map<String, dynamic>> createApplication(String phone) async {
    await init();
    final res = await dio.post(
      '/api/create_application', // <-- Эндпоинт из app.py
      data: {'phone': phone},
    );

    if (res.statusCode == 200) {
      // {"success": true, "message": "..."}
      return Map<String, dynamic>.from(res.data);
    }

    // {"success": false, "message": "..."}
    if (res.statusCode == 400) {
      throw Exception(res.data?['message'] ?? 'Ошибка 400');
    }

    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data?['message'] ?? 'Ошибка сервера',
      type: DioExceptionType.badResponse,
    );
  }

  /// Сохраняет подтвержденный анализ и цели.
  /// Соответствует вызову POST /confirm_analysis
  Future<Map<String, dynamic>> confirmBodyAnalysis({
    required double height,
    double? fatMassGoal,
    double? muscleMassGoal,
  }) async {
    await init();

    final Map<String, dynamic> data = {
      'height': height,
    };

    // Добавляем цели, только если они переданы
    if (fatMassGoal != null) {
      data['fat_mass_goal'] = fatMassGoal;
    }
    if (muscleMassGoal != null) {
      data['muscle_mass_goal'] = muscleMassGoal;
    }

    final res = await dio.post(
      '/confirm_analysis',
      data: data, // Отправляем как JSON (по умолчанию для Map)
      options: Options(
        // contentType: Headers.formUrlEncodedContentType, // <-- УДАЛИТЕ ЭТУ СТРОКУ
      ),
    );

    // Ожидаем, что бэк вернет {"success": true, "ai_comment": "..."}
    if (res.statusCode == 200 && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }

    final error = res.data is Map && res.data['error'] != null
        ? res.data['error']
        : 'Failed to confirm analysis';
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: error,
      type: DioExceptionType.badResponse,
    );
  }

  /// Запускает "магию" - генерацию визуализации
  /// Соответствует вызову POST /visualize/run
  Future<Map<String, dynamic>> runVisualization() async {
    await init();
    final res = await dio.post('/visualize/run');

    if (res.statusCode == 200 && res.data['success'] == true) {
      return Map<String, dynamic>.from(res.data['visualization']);
    }

    final error = res.data is Map && res.data['error'] != null
        ? res.data['error']
        : 'Failed to run visualization';
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: error,
      type: DioExceptionType.badResponse,
    );
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    await init();
    final res = await dio.post('/api/login', data: {'email': email, 'password': password});
    if (res.statusCode == 200 && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['user']);
    }
    final error = res.data is Map && res.data['error'] != null ? res.data['error'] : 'LOGIN_FAILED';
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: error,
      type: DioExceptionType.badResponse,
    );
  }

  Future<void> logout() async {
    await init();
    await dio.post('/api/logout');
  }

  Future<Map<String, dynamic>?> me() async {
    await init();
    final res = await dio.get('/api/me');
    if (res.statusCode == 200 && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['user']);
    }
    return null;
  }

  /// НОВЫЙ МЕТОД
  /// Проверяет email и возвращает публичные данные (имя, аватар)
  Future<Map<String, dynamic>> checkUserEmail(String email) async {
    await init();
    // ПРИМЕЧАНИЕ: /api/check_user_email - это предполагаемый эндпоинт.
    // Убедитесь, что он существует на вашем бэкенде.
    final res = await dio.post('/api/check_user_email', data: {'email': email});

    if (res.statusCode == 200 && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['user_data']);
    }

    // Обрабатываем 404 (не найден) или другие ошибки
    final error = res.data is Map && res.data['error'] != null
        ? res.data['error']
        : 'USER_NOT_FOUND';
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: error,
      type: DioExceptionType.badResponse,
    );
  }
  /// КОНЕЦ НОВОГО МЕТОДА

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String dateOfBirth, // 'YYYY-MM-DD'
    required String sex, // 'male'/'female'
    bool faceConsent = false, // <-- 1. ДОБАВЬТЕ ЭТОТ ПАРАМЕТР
  }) async {
    await init();
    final res = await dio.post('/api/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'date_of_birth': dateOfBirth,
      'sex': sex,
      'face_consent': faceConsent, // <-- 2. ДОБАВЬТЕ ЭТУ СТРОКУ
    });
    if ((res.statusCode == 201 || res.statusCode == 200) && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['user']);
    }
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: (res.data is Map && res.data['errors'] != null) ? res.data['errors'] : 'REGISTER_FAILED',
      type: DioExceptionType.badResponse,
    );
  }

  // ======================
  // -- НАЧАЛО ДОБАВЛЕНИЙ --
  // ======================

  /// Загружает все данные для главной страницы профиля
  Future<Map<String, dynamic>> getProfileData() async {
    await init();
    final res = await dio.get('/api/app/profile_data');
    if (res.statusCode == 200 && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['data']);
    }
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: 'Failed to load profile data',
      type: DioExceptionType.badResponse,
    );
  }

  /// Регистрирует FCM токен устройства на бэкенде
  Future<void> registerDeviceToken(String fcmToken) async {
    await init();
    try {
      await dio.post(
        '/api/app/register_device', // Наш новый эндпоинт
        data: {'fcm_token': fcmToken},
      );
      print('FCM token registered successfully.');
    } catch (e) {
      // Ошибку можно проигнорировать, т.к. это фоновая задача
      print('Failed to register FCM token: $e');
    }
  }

  /// Загружает приемы пищи за сегодня
  Future<Map<String, dynamic>> getTodayMeals() async {
    await init();
    final res = await dio.get('/api/app/meals/today');
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(res.data);
    }
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: 'Failed to load meals',
      type: DioExceptionType.badResponse,
    );
  }

  /// Загружает активность за сегодня
  Future<Map<String, dynamic>> getTodayActivity() async {
    await init();
    final res = await dio.get('/api/app/activity/today');
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(res.data);
    }
    return {}; // Возвращаем пустую карту, если 404
  }

  /// Сохраняет прием пищи
  Future<void> logMeal({
    required String mealType,
    required String name,
    required int calories,
    required double protein,
    required double fat,
    required double carbs,
    String? analysis, // <-- 2. ДОБАВЬТЕ ЭТОТ ПАРАМЕТР
  }) async {
    await init();
    final res = await dio.post('/api/app/log_meal', data: {
      'meal_type': mealType,
      'name': name,
      'calories': calories,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      'analysis': analysis, // <-- 3. ПЕРЕДАЙТЕ ЕГО В ЗАПРОС
    });
    if (res.statusCode != 200) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        error: res.data?['error'] ?? 'Failed to log meal',
        type: DioExceptionType.badResponse,
      );
    }
  }

  /// Анализ фото приема пищи
  Future<Map<String, dynamic>> analyzeMealPhoto(File imageFile) async {
    await init();

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });

    final res = await dio.post(
      '/api/app/analyze_meal_photo',
      data: formData,
      options: Options(
        headers: {
          HttpHeaders.contentTypeHeader: 'multipart/form-data',
        },
      ),
    );

    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(res.data);
    }
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data?['error'] ?? 'Failed to analyze photo',
      type: DioExceptionType.badResponse,
    );
  }

  // --- Настройки Telegram ---

  Future<String> generateTelegramCode() async {
    await init();
    final res = await dio.get('/api/app/telegram_code');
    if (res.statusCode == 200) {
      return res.data['code'];
    }
    throw DioException(requestOptions: res.requestOptions, response: res);
  }

  Future<Map<String, dynamic>> getTelegramSettings() async {
    await init();
    final res = await dio.get('/api/me/telegram/settings');
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(res.data);
    }
    throw DioException(requestOptions: res.requestOptions, response: res);
  }

  Future<Map<String, dynamic>> setTelegramSettings(Map<String, bool> settings) async {
    await init();
    final res = await dio.patch('/api/me/telegram/settings', data: settings);
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(res.data);
    }
    throw DioException(requestOptions: res.requestOptions, response: res);
  }

  /// Сбрасывает цели и начальную точку анализа
  /// Соответствует вызову POST /profile/reset_goals
  Future<void> resetProgress() async {
    await init();
    final res = await dio.post('/profile/reset_goals');

    if (res.statusCode != 200) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        error: res.data?['error'] ?? 'Failed to reset progress',
        type: DioExceptionType.badResponse,
      );
    }
  }

  /// Загружает все тренировки за указанный месяц (YYYY-MM)
  /// Соответствует вызову GET /api/trainings
  Future<List<Map<String, dynamic>>> getTrainings(String monthYyyyMm) async {
    await init();
    final res = await dio.get(
      '/api/trainings',
      queryParameters: {'month': monthYyyyMm},
    );

    if (res.statusCode == 200 && res.data['ok'] == true) {
      // Убедимся, что возвращаем список нужного типа
      return (res.data['data'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data?['error'] ?? 'Failed to load trainings',
      type: DioExceptionType.badResponse,
    );
  }

  /// Записывает текущего пользователя на тренировку
  /// Соответствует вызову POST /api/trainings/<tid>/signup
  Future<Map<String, dynamic>> signupTraining(int trainingId) async {
    await init();
    final res = await dio.post('/api/trainings/$trainingId/signup');

    if (res.statusCode == 200 && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['data']);
    }

    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data?['description'] ?? res.data?['error'] ?? 'Failed to sign up',
      type: DioExceptionType.badResponse,
    );
  }

  /// Отменяет запись текущего пользователя на тренировку
  /// Соответствует вызову DELETE /api/trainings/<tid>/signup
  Future<Map<String, dynamic>> cancelSignup(int trainingId) async {
    await init();
    final res = await dio.delete('/api/trainings/$trainingId/signup');

    if (res.statusCode == 200 && res.data['ok'] == true) {
      return Map<String, dynamic>.from(res.data['data']);
    }

    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data?['description'] ?? res.data?['error'] ?? 'Failed to cancel signup',
      type: DioExceptionType.badResponse,
    );
  }

  /// Загружает сводку по потреблению калорий за неделю
  /// Соответствует вызову GET /api/user/weekly_summary
  Future<Map<String, dynamic>> getWeeklySummary() async {
    await init();
    final res = await dio.get('/api/user/weekly_summary');

    if (res.statusCode == 200 && res.data != null) {
      return Map<String, dynamic>.from(res.data);
    }

    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data?['error'] ?? 'Failed to load weekly summary',
      type: DioExceptionType.badResponse,
    );
  }

  /// Загружает историю чата с AI-ассистентом
  Future<List<Map<String, dynamic>>> getAiChatHistory() async {
    await init();
    // TODO: Уточните URL эндпоинта. Предполагаю '/api/assistant/history'
    final res = await dio.get('/api/assistant/history');

    if (res.statusCode != 200 || res.data == null) {
      return [];
    }

    dynamic data = res.data;

    // ИСПРАВЛЕНИЕ: На случай, если dio вернет сырую строку
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (e) {
        return []; // Не смогли распознать
      }
    }

    // Бэк теперь возвращает {"messages": [...]}
    if (data is Map && data['messages'] != null && data['messages'] is List) {
      return (data['messages'] as List).cast<Map<String, dynamic>>();
    }

    // На случай, если бэк вернул [...] напрямую (старая логика)
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }

    return [];
  }

  /// Отправляет сообщение AI-ассистенту и получает ответ
  Future<Map<String, dynamic>> sendAiChatMessage(String message) async {
    await init();
    // TODO: Уточните URL эндпоинта. Предполагаю '/api/assistant/chat'
    final res = await dio.post(
      '/api/assistant/chat',
      data: {'message': message},
    );

    // --- НАЧАЛО ИСПРАВЛЕНИЯ ---
    // (Логика скопирована из getAiChatHistory)
    dynamic data = res.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (e) {
        // Если не смогли распознать, выбрасываем ошибку
        throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          error: 'Failed to decode JSON string: $e',
          type: DioExceptionType.badResponse,
        );
      }
    }
    // --- КОНЕЦ ИСПРАВЛЕНИЯ ---


    // ИСПРАВЛЕНИЕ: Бэкенд теперь возвращает {"role": "...", "content": "..."}
    // Используем 'data' вместо 'res.data'
    if (res.statusCode == 200 && data != null && data['role'] != null) {
      return Map<String, dynamic>.from(data);
    }

    // Если бэкенд вернул 500 или {"error": ...}
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: data?['error'] ?? data?['content'] ?? 'Некорректный формат ответа от AI',
      type: DioExceptionType.badResponse,
    );
  }
}
