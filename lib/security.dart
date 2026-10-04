import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppSecurityService {
  AppSecurityService._();

  static final AppSecurityService instance = AppSecurityService._();

  static const _pinHashKey = 'app_pin_hash_v1';
  static const _pinSaltKey = 'app_pin_salt_v1';
  static const _biometricEnabledKey = 'biometric_enabled_v1';
  static const _lockTimeoutKey = 'lock_timeout_seconds_v1';

  final FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  final LocalAuthentication _auth = LocalAuthentication();

  final ValueNotifier<int> forceLockSignal = ValueNotifier<int>(0);

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _pinHashKey);
    final salt = await _storage.read(key: _pinSaltKey);
    return hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN должен состоять из 6 цифр.');
    }
    final salt = _newSalt();
    final hash = _hash(pin, salt);
    await _storage.write(key: _pinSaltKey, value: salt);
    await _storage.write(key: _pinHashKey, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _pinSaltKey);
    final expected = await _storage.read(key: _pinHashKey);
    if (salt == null || expected == null) return false;
    return _constantTimeEquals(_hash(pin, salt), expected);
  }

  Future<bool> biometricEnabled() async {
    return (await _storage.read(key: _biometricEnabledKey)) == 'true';
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _storage.write(
      key: _biometricEnabledKey,
      value: value ? 'true' : 'false',
    );
  }

  Future<int> lockTimeoutSeconds() async {
    final raw = await _storage.read(key: _lockTimeoutKey);
    final parsed = int.tryParse(raw ?? '');
    return parsed ?? 30;
  }

  Future<void> setLockTimeoutSeconds(int seconds) async {
    if (![30, 60, 300, 900].contains(seconds)) {
      throw ArgumentError('Недопустимый интервал блокировки.');
    }
    await _storage.write(key: _lockTimeoutKey, value: '$seconds');
  }

  String? lastAuthError;

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty || supported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    lastAuthError = null;
    try {
      // Небольшая пауза помогает некоторым оболочкам Android корректно
      // открыть системный BiometricPrompt после нажатия на переключатель.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return await _auth.authenticate(
        localizedReason: 'Подтвердите вход в приложение «Склад»',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
    } on LocalAuthException catch (error) {
      lastAuthError = _localAuthMessage(error);
      return false;
    } catch (error) {
      lastAuthError = 'Системная аутентификация не запустилась: $error';
      return false;
    }
  }

  String _localAuthMessage(LocalAuthException error) {
    switch (error.code) {
      case LocalAuthExceptionCode.uiUnavailable:
        return 'Android не смог открыть системное окно подтверждения.';
      case LocalAuthExceptionCode.authInProgress:
        return 'Проверка уже запущена. Подождите секунду и попробуйте снова.';
      case LocalAuthExceptionCode.systemCanceled:
        return 'Android отменил системное подтверждение. Попробуйте ещё раз.';
      case LocalAuthExceptionCode.userCanceled:
        return 'Подтверждение отменено.';
      case LocalAuthExceptionCode.noCredentialsSet:
        return 'На телефоне не настроена блокировка экрана.';
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return 'На телефоне не зарегистрирован отпечаток или другая биометрия.';
      case LocalAuthExceptionCode.noBiometricHardware:
        return 'Биометрический датчик недоступен.';
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return 'Биометрический датчик временно недоступен.';
      case LocalAuthExceptionCode.temporaryLockout:
        return 'Биометрия временно заблокирована после неудачных попыток.';
      case LocalAuthExceptionCode.biometricLockout:
        return 'Сначала разблокируйте телефон его PIN-кодом или графическим ключом.';
      case LocalAuthExceptionCode.userRequestedFallback:
        return 'Выбран другой способ подтверждения.';
      case LocalAuthExceptionCode.timeout:
        return 'Время ожидания подтверждения истекло.';
      case LocalAuthExceptionCode.deviceError:
      case LocalAuthExceptionCode.unknownError:
        final details = error.description?.trim();
        return details == null || details.isEmpty
            ? 'Ошибка системной аутентификации Android.'
            : 'Ошибка Android: $details';
    }
  }

  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {
      // Ничего не делаем: остановка нужна только как очистка состояния.
    }
  }

  void lockNow() {
    forceLockSignal.value++;
  }

  String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final _security = AppSecurityService.instance;

  bool _loading = true;
  bool _hasPin = false;
  bool _locked = true;
  int _timeoutSeconds = 30;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _security.forceLockSignal.addListener(_forceLock);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _security.forceLockSignal.removeListener(_forceLock);
    _security.stopAuthentication();
    super.dispose();
  }

  Future<void> _load() async {
    final hasPin = await _security.hasPin();
    final timeout = await _security.lockTimeoutSeconds();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _locked = hasPin;
      _timeoutSeconds = timeout;
      _loading = false;
    });
  }

  void _forceLock() {
    if (!mounted || !_hasPin) return;
    setState(() => _locked = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasPin) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since == null) return;
      final seconds = DateTime.now().difference(since).inSeconds;
      if (seconds >= _timeoutSeconds && mounted) {
        setState(() => _locked = true);
      }
    }
  }

  Future<void> _configured() async {
    final timeout = await _security.lockTimeoutSeconds();
    if (!mounted) return;
    setState(() {
      _hasPin = true;
      _locked = false;
      _timeoutSeconds = timeout;
    });
  }

  void _unlocked() {
    if (!mounted) return;
    setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPin) {
      return SecuritySetupScreen(onConfigured: _configured);
    }

    if (_locked) {
      return UnlockScreen(onUnlocked: _unlocked);
    }

    return widget.child;
  }
}

class SecuritySetupScreen extends StatefulWidget {
  const SecuritySetupScreen({super.key, required this.onConfigured});

  final Future<void> Function() onConfigured;

  @override
  State<SecuritySetupScreen> createState() => _SecuritySetupScreenState();
}

class _SecuritySetupScreenState extends State<SecuritySetupScreen> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin.text.trim();
    final repeat = _repeat.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN должен состоять ровно из 6 цифр.');
      return;
    }
    if (pin != repeat) {
      setState(() => _error = 'PIN-коды не совпадают.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppSecurityService.instance.setPin(pin);
      await AppSecurityService.instance.setLockTimeoutSeconds(30);
      await widget.onConfigured();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось сохранить PIN: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Icon(Icons.shield_outlined, size: 72),
                  const SizedBox(height: 18),
                  Text(
                    'Защита приложения',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Создай шестизначный PIN. Он будет нужен для входа, '
                    'если отпечаток недоступен.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _PinField(
                    controller: _pin,
                    label: 'Новый PIN',
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  _PinField(
                    controller: _repeat,
                    label: 'Повтори PIN',
                    onSubmitted: (_) => _saving ? null : _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_outline),
                      label: const Text('Включить защиту'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pin = TextEditingController();
  final _security = AppSecurityService.instance;

  bool _checking = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricAttempted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareBiometric();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _prepareBiometric() async {
    final enabled = await _security.biometricEnabled();
    final available = await _security.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _biometricAvailable = available;
    });
    if (enabled && available && !_biometricAttempted) {
      _biometricAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _useBiometric();
      });
    }
  }

  Future<void> _checkPin() async {
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _error = 'Введи 6 цифр.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await _security.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    _pin.clear();
    setState(() {
      _checking = false;
      _error = 'Неверный PIN.';
    });
  }

  Future<void> _useBiometric() async {
    if (_checking || !_biometricAvailable || !_biometricEnabled) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await _security.authenticateBiometric();
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = _security.lastAuthError ??
          'Не удалось выполнить системное подтверждение. Можно ввести PIN.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Icon(Icons.lock_outline, size: 72),
                  const SizedBox(height: 18),
                  Text(
                    'Склад заблокирован',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Введи PIN или используй биометрию.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _PinField(
                    controller: _pin,
                    label: 'PIN-код',
                    autofocus: !_biometricEnabled,
                    onSubmitted: (_) => _checking ? null : _checkPin(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _checking ? null : _checkPin,
                      child: _checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Разблокировать'),
                    ),
                  ),
                  if (_biometricAvailable && _biometricEnabled) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _checking ? null : _useBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Отпечаток / системная защита'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _security = AppSecurityService.instance;
  bool _loading = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  int _timeout = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _security.biometricEnabled();
    final available = await _security.canUseBiometrics();
    final timeout = await _security.lockTimeoutSeconds();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _biometricAvailable = available;
      _timeout = timeout;
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await _security.authenticateBiometric();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _security.lastAuthError ??
                  'Системная защита не включена: подтверждение не прошло.',
            ),
          ),
        );
        return;
      }
    }
    await _security.setBiometricEnabled(value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
  }

  Future<void> _changePin() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const ChangePinDialog(),
    );
    if (changed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN-код изменён.')),
    );
  }

  Future<void> _changeTimeout(int? value) async {
    if (value == null) return;
    await _security.setLockTimeoutSeconds(value);
    if (!mounted) return;
    setState(() => _timeout = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Защита приложения')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.pin_outlined),
                        title: Text('PIN-код'),
                        subtitle: Text('Шестизначный код используется всегда как запасной способ входа.'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _changePin,
                            icon: const Icon(Icons.password),
                            label: const Text('Сменить PIN'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: SwitchListTile(
                    value: _biometricEnabled,
                    onChanged: _biometricAvailable ? _toggleBiometric : null,
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Отпечаток / системная защита'),
                    subtitle: Text(
                      _biometricAvailable
                          ? 'Android предложит отпечаток, лицо или системный PIN/графический ключ.'
                          : 'На устройстве недоступна системная защита.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<int>(
                      initialValue: _timeout,
                      decoration: const InputDecoration(
                        labelText: 'Автоблокировка после сворачивания',
                        prefixIcon: Icon(Icons.timer_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 30, child: Text('Через 30 секунд')),
                        DropdownMenuItem(value: 60, child: Text('Через 1 минуту')),
                        DropdownMenuItem(value: 300, child: Text('Через 5 минут')),
                        DropdownMenuItem(value: 900, child: Text('Через 15 минут')),
                      ],
                      onChanged: _changeTimeout,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    _security.lockNow();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.lock),
                  label: const Text('Заблокировать сейчас'),
                ),
                const SizedBox(height: 12),
                Text(
                  'PIN хранится только в защищённом хранилище телефона. '
                  'Резервная копия склада PIN не содержит.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

class ChangePinDialog extends StatefulWidget {
  const ChangePinDialog({super.key});

  @override
  State<ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<ChangePinDialog> {
  final _current = TextEditingController();
  final _newPin = TextEditingController();
  final _repeat = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _newPin.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = _current.text.trim();
    final next = _newPin.text.trim();
    final repeat = _repeat.text.trim();

    if (!await AppSecurityService.instance.verifyPin(current)) {
      if (!mounted) return;
      setState(() => _error = 'Текущий PIN указан неверно.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(next)) {
      setState(() => _error = 'Новый PIN должен состоять из 6 цифр.');
      return;
    }
    if (next != repeat) {
      setState(() => _error = 'Новые PIN-коды не совпадают.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    await AppSecurityService.instance.setPin(next);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сменить PIN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinField(controller: _current, label: 'Текущий PIN'),
            const SizedBox(height: 10),
            _PinField(controller: _newPin, label: 'Новый PIN'),
            const SizedBox(height: 10),
            _PinField(
              controller: _repeat,
              label: 'Повтори новый PIN',
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      obscuringCharacter: '●',
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.pin_outlined),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
