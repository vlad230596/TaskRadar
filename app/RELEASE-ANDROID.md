# Подпись Android-релиза

Как владельцу завести ключ подписи, чтобы собирался release-APK — локально и в
GitHub Actions. Делается один раз.

Ключа в репозитории нет и быть не может: ни файла, ни паролей, ни алиаса.
`app/android/app/build.gradle.kts` читает конфигурацию из `android/key.properties`
(в `.gitignore`) или из переменных окружения, а без неё **release-сборка падает с
внятным сообщением** вместо того, чтобы тихо подписаться debug-ключом, как было
до F5.

---

## Сначала — про потерю ключа

**Ключ подписи нельзя потерять и нельзя заменить.**

Android опознаёт приложение по паре «application id + ключ подписи». Если
`com.taskradar.app` установлен на телефоне и подписан ключом A, то APK,
подписанный ключом B, установить поверх нельзя — система откажет
(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Единственный выход — удалить приложение
вместе с его локальным состоянием (токен сессии, снимок доски, настройка часа
напоминаний, очередь будильников) и поставить заново.

Отсюда три следствия:

1. **Ключ создаёт владелец, не агент и не CI.** Это долгоживущий секрет, а не
   артефакт сборки.
2. **Ключ и пароли к нему нужно забэкапить** там же, где хранятся остальные
   важные секреты (менеджер паролей, зашифрованный архив на отдельном носителе).
   Бэкап должен пережить переустановку системы и смерть диска.
3. **Срок жизни сертификата — большой.** В команде ниже стоит 10000 дней (~27
   лет). APK, подписанный просроченным сертификатом, Android ставить откажется,
   а продлить сертификат, сохранив ключ, — отдельная морока; проще сразу взять
   заведомо избыточный срок.

Play Store тут ни при чём: TaskRadar ставится sideload'ом (см.
`flutter-migration-plan.md`), Play App Signing с его «восстановлением ключа» не
используется. Резервной копии, кроме вашей, не существует.

---

## 1. Сгенерировать keystore

Нужен `keytool` из JDK; в Android Studio он лежит в
`<студия>/jbr/bin/keytool.exe`, в Flutter-окружении подойдёт любой JDK 17+.

Положите файл **вне репозитория** — например в `%USERPROFILE%\keys\`:

```powershell
keytool -genkeypair -v `
  -keystore "$env:USERPROFILE\keys\taskradar-release.jks" `
  -storetype JKS `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -alias taskradar
```

`keytool` спросит пароль хранилища, затем имя/организацию (для личного
инструмента можно указать что угодно осмысленное) и пароль ключа — можно тот же,
что и у хранилища.

Пароли сразу положите в менеджер паролей. Восстановить их неоткуда.

Проверить, что получилось:

```powershell
keytool -list -v -keystore "$env:USERPROFILE\keys\taskradar-release.jks" -alias taskradar
```

Запишите отпечаток SHA-256 — по нему потом можно убедиться, что собранный APK
подписан именно этим ключом.

## 2. Настроить локальную сборку

Создайте `app/android/key.properties` (файл в `.gitignore`, проверено через
`git check-ignore`):

```properties
storeFile=C:/Users/<вы>/keys/taskradar-release.jks
storePassword=<пароль хранилища>
keyAlias=taskradar
keyPassword=<пароль ключа>
```

Прямые слэши в пути — Java-`Properties` считает `\` экранирующим символом, и
`C:\Users\...` прочитается неправильно. Путь может быть и относительным, тогда он
считается от `app/android/app/`.

Проверка:

```powershell
$env:PATH = "C:\FlutterSdk\flutter\bin;" + $env:PATH
cd D:\Projects\TaskRadar\app
flutter build apk --release --dart-define=TASKRADAR_API_URL=https://<ваш-домен>
```

`--dart-define` здесь обязателен: базовый URL API зашивается в APK на сборке
(`AppConfig.apiBaseUrl`), дефолт `http://localhost:3001` на телефоне бесполезен,
а `http://` в release-сборке не работает вовсе — cleartext разрешён только в
debug-манифесте.

Убедиться, что APK подписан нужным ключом (`apksigner` — из
`<sdk>/build-tools/<версия>/`):

```powershell
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

Отпечаток SHA-256 должен совпасть с тем, что показал `keytool -list -v`.

### Если ключа нет

Сборка остановится сообщением «release signing is not configured», перечислит
недостающие параметры и укажет на этот файл. Это ожидаемое поведение, а не
поломка: молчаливая подпись debug-ключом — ровно тот баг, который здесь
исправлен. `flutter build apk --debug` и `flutter run` при этом работают без
всякой настройки.

## 3. Завести секреты в GitHub Actions

Workflow `.github/workflows/app-release.yml` собирает release-APK и прикладывает
его к GitHub Release. Ему нужны четыре секрета репозитория
(*Settings → Secrets and variables → Actions → New repository secret*):

| Секрет | Что положить |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | сам `.jks`, закодированный в base64 (одной строкой) |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| `ANDROID_KEY_ALIAS` | `taskradar` |
| `ANDROID_KEY_PASSWORD` | пароль ключа |

Base64 из PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\keys\taskradar-release.jks")) `
  | Set-Clipboard
```

Плюс переменная репозитория (*Variables*, не секрет) `TASKRADAR_API_URL` — тот же
origin, что `APP_ORIGIN` в `/opt/taskradar/.env`, обязательно `https://`.

Workflow декодирует keystore во временный файл, экспортирует
`TASKRADAR_ANDROID_KEYSTORE_PATH`, `TASKRADAR_ANDROID_KEYSTORE_PASSWORD`,
`TASKRADAR_ANDROID_KEY_ALIAS`, `TASKRADAR_ANDROID_KEY_PASSWORD` и собирает APK.
Эти четыре имени — то, что читает `build.gradle.kts`; имена секретов GitHub
намеренно другие (секрет хранится в GitHub, переменная попадает в сборку).

Если какой-то секрет не задан, job падает на шаге проверки с именем секрета —
раньше, чем `keytool` успеет сказать «keystore was tampered with, or password was
incorrect», что уводит в поиски несуществующей порчи файла.

## Что где лежит — сводка

| | |
|---|---|
| Keystore | **только у владельца**: рабочая копия вне репозитория + бэкап |
| Пароли и алиас | менеджер паролей владельца; в CI — Actions secrets |
| `app/android/key.properties` | локальная машина, gitignored |
| В репозитории | ничего из перечисленного |
