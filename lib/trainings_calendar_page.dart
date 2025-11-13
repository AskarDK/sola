import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:table_calendar/table_calendar.dart';
import 'auth_api.dart';
import 'index.dart'; // Для AppColors, KiloCard и т.д.
import 'app_theme.dart'; // Для AppColors

class TrainingsCalendarPage extends StatefulWidget {
  final VoidCallback? onTrainingChanged; // <-- 1. ПРИНИМАЕМ КОЛБЭК

  const TrainingsCalendarPage({
    super.key,
    this.onTrainingChanged, // <-- 2. ДОБАВЛЯЕМ В КОНСТРУКТОР
  });

  @override
  State<TrainingsCalendarPage> createState() => TrainingsCalendarPageState();
}

class TrainingsCalendarPageState extends State<TrainingsCalendarPage> {// ИЗМЕНЕНИЕ
  final _api = AuthApi();

  // Состояние календаря
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Данные
  Map<String, dynamic>? _data;
  String _currentMonthKey = '';

  // События
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  List<Map<String, dynamic>> _selectedEvents = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _currentMonthKey = DateFormat('yyyy-MM').format(_focusedDay);
    _fetchTrainings(_currentMonthKey);
    _selectedEvents = [];
  }

  /// Загрузка данных о тренировках
  Future<void> _fetchTrainings(String monthKey) async {
    if (_data?[monthKey] != null) return; // Уже загружено

    try {
      final List<Map<String, dynamic>> trainings = await _api.getTrainings(monthKey);

      final Map<DateTime, List<Map<String, dynamic>>> eventsMap = {};
      for (final training in trainings) {
        try {
          final date = DateTime.parse(training['date']);
          final dateOnly = DateTime(date.year, date.month, date.day);
          if (eventsMap[dateOnly] == null) {
            eventsMap[dateOnly] = [];
          }
          eventsMap[dateOnly]!.add(training);
        } catch (e) {
          debugPrint('Invalid date for training ${training['id']}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _events = eventsMap;
          _data = {
            ...(Map<String, dynamic>.from(_data ?? {})),
            monthKey: true, // Помечаем, что месяц загружен
          };
          _selectedEvents = _getEventsForDay(_selectedDay!);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки тренировок: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return _events[dateOnly] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedEvents = _getEventsForDay(selectedDay);
      });
    }
  }

  void _onPageChanged(DateTime focusedDay) {
    _focusedDay = focusedDay;
    final monthKey = DateFormat('yyyy-MM').format(focusedDay);
    if (monthKey != _currentMonthKey) {
      _currentMonthKey = monthKey;
      _fetchTrainings(monthKey); // Загружаем данные для нового месяца
    }
  }

  // Обработчик записи на тренировку
  Future<void> _handleSignUp(int trainingId) async {
    try {
      await _api.signupTraining(trainingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы успешно записаны!'), backgroundColor: AppColors.green),
        );
      }
      // Обновляем данные
      await _fetchTrainings(_currentMonthKey);
      widget.onTrainingChanged?.call(); // <-- 3. ВЫЗЫВАЕМ КОЛБЭК
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка записи: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  // Обработчик отмены записи
  Future<void> _handleCancel(int trainingId) async {
    try {
      await _api.cancelSignup(trainingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ваша запись отменена.'), backgroundColor: AppColors.neutral700),
        );
      }
      // Обновляем данные
      await _fetchTrainings(_currentMonthKey);
      widget.onTrainingChanged?.call(); // <-- 4. ВЫЗЫВАЕМ КОЛБЭК
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отмены: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final bottomPad = bottomContentPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь тренировок'),
      ),
      body: Column(
        children: [
          // --- Календарь ---
          KiloCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(8),
            child: TableCalendar(
              locale: 'ru_RU', // Убедитесь, что `intl` настроен для русского
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: _getEventsForDay,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                markerSize: 5,
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              onDaySelected: _onDaySelected,
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() => _calendarFormat = format);
                }
              },
              onPageChanged: _onPageChanged,
            ),
          ),

          // --- Список событий ---
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
              itemCount: _selectedEvents.length,
              itemBuilder: (context, index) {
                final event = _selectedEvents[index];
                return _buildWorkoutCard(event);
              },
            ),
          ),
        ],
      ),
    );
  }

  // Виджет карточки тренировки
  Widget _buildWorkoutCard(Map<String, dynamic> event) {
    final String title = event['title'] ?? 'Тренировка';
    final String trainerName = event['trainer']?['name'] ?? 'Тренер';
    final String startTime = event['start_time'] ?? '00:00';
    final String endTime = event['end_time'] ?? '00:00';
    final int capacity = event['capacity'] ?? 0;
    final int signups = (event['signups'] as List? ?? []).length;
    final bool isFull = signups >= capacity;
    final bool isSignedUp = event['is_signed_up_by_me'] ?? false;

    final canSignUp = !isSignedUp && !isFull;

    return KiloCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: AppColors.neutral500),
              const SizedBox(width: 8),
              Text(trainerName, style: const TextStyle(fontSize: 15, color: AppColors.neutral700)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 16, color: AppColors.neutral500),
              const SizedBox(width: 8),
              Text('$startTime - $endTime', style: const TextStyle(fontSize: 15, color: AppColors.neutral700)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.groups_rounded, size: 16, color: AppColors.neutral500),
              const SizedBox(width: 8),
              Text('Места: $signups / $capacity', style: const TextStyle(fontSize: 15, color: AppColors.neutral700)),
            ],
          ),
          const Divider(height: 24),

          // Кнопка
          SizedBox(
            width: double.infinity,
            child: isSignedUp
                ? OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Вы записаны (Отменить)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.neutral600,
                side: const BorderSide(color: AppColors.neutral300),
              ),
              onPressed: () => _handleCancel(event['id']),
            )
                : ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: Text(isFull ? 'Нет мест' : 'Записаться'),
              style: ElevatedButton.styleFrom(
                backgroundColor: canSignUp ? AppColors.primary : AppColors.neutral300,
              ),
              onPressed: canSignUp ? () => _handleSignUp(event['id']) : null,
            ),
          ),
        ],
      ),
    );
  }
}