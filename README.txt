HoN RU Pack - Русификатор для Heroes of Newerth (Juvio)

=== Быстрый запуск ===

1) Запустите run_hon_full_translation.bat
2) Оставьте окно cmd открытым
3) Запустите Juvio и откройте HoN
4) Не закрывайте окно cmd, пока идет обновление и запуск игры

Скрипт автоматически найдет папки HoN на вашем компьютере.
В консоли вы увидите:
   Auto-detected DocsRoot: ...
   Auto-detected LocalRoot: ...

=== Обновление перевода ===

1) Запустите update.bat
2) Дождитесь завершения скачивания/обновления
3) Запустите run_hon_full_translation.bat
4) Оставьте окно cmd открытым во время запуска Juvio/HoN

=== Если автообнаружение не сработало ===

Скрипт ищет startup.cfg и resources0.jz в типичных папках:
   - Documents\Juvio\Heroes of Newerth
   - AppData\Local\Juvio\heroes of newerth
   - C:\Games\Juvio, D:\Games\Juvio
   - Program Files\Juvio, Program Files (x86)\Juvio
   - Корень каждого диска (E:\Juvio, F:\Juvio и т.д.)

Если ваша установка не найдена автоматически:

1) Скопируйте hon_paths_override.example.ps1 -> hon_paths_override.ps1
2) Откройте hon_paths_override.ps1 блокнотом и укажите свои пути:

   $HoNDocsRoot    = "C:\Users\ВашеИмя\Documents\Juvio\Heroes of Newerth"
   $HoNLocalRoot   = "C:\Games\Juvio\heroes of newerth"
   $HoNArchivePath = "C:\Games\Juvio\heroes of newerth\resources0.jz"

   $HoNDocsRoot    = папка, где лежит startup.cfg
   $HoNLocalRoot   = папка, где лежит resources0.jz
   $HoNArchivePath = полный путь до resources0.jz

3) Если не знаете пути:
   Откройте PowerShell и выполните:

   Get-ChildItem "$env:USERPROFILE" -Recurse -Filter "startup.cfg" -ErrorAction SilentlyContinue | Select FullName
   Get-ChildItem "C:\","D:\" -Recurse -Filter "resources0.jz" -ErrorAction SilentlyContinue | Select FullName

4) Сохраните файл и запустите run_hon_full_translation.bat

=== Проверка обновлений игры ===

Запустите check_hon_translation_update.bat
Если скрипт покажет изменения в stringtables, обновите bundle
и заново запустите run_hon_full_translation.bat

=== Содержимое bundle ===

bundle\entities_en.str
bundle\interface_en.str
bundle\client_messages_en.str
bundle\game_messages_en.str
bundle\bot_messages_en.str
