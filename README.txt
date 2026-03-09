HoN RU Pack - инструкция

Быстрый запуск (стандартная установка):
1) Запустите run_hon_full_translation.bat
2) Оставьте окно cmd открытым
3) Запустите Juvio и откройте HoN
4) Не закрывайте окно cmd, пока идет обновление и запуск игры

Обновление перевода одной кнопкой:
1) Запустите update.bat
2) Дождитесь завершения скачивания/обновления
3) Запустите run_hon_full_translation.bat
4) Оставьте окно cmd открытым во время запуска Juvio/HoN

Если игра установлена не в стандартную папку:
1) Скопируйте файл hon_paths_override.example.ps1 в hon_paths_override.ps1

2) Откройте hon_paths_override.ps1 и заполните свои пути:
   - $HoNDocsRoot: папка, где лежит startup.cfg
   - $HoNLocalRoot: папка, где лежит resources0.jz
   - $HoNArchivePath: полный путь до resources0.jz

3) Пример (вставьте и замените под себя):
   $HoNDocsRoot = "D:\Juvio\Heroes of Newerth"
   $HoNLocalRoot = "D:\Juvio\heroes of newerth"
   $HoNArchivePath = "D:\Juvio\heroes of newerth\resources0.jz"

4) Если не знаете пути:
   - откройте проводник и найдите файл resources0.jz
   - путь до папки с этим файлом = $HoNLocalRoot
   - сам полный путь к файлу = $HoNArchivePath
   - папка, где лежит startup.cfg = $HoNDocsRoot

5) Сохраните файл и снова запустите run_hon_full_translation.bat
Проверка обновлений игры:
- Запустите check_hon_translation_update.bat
- Если скрипт покажет изменения в stringtables, обновите bundle и заново запустите deploy

Содержимое папки bundle:
- bundle\entities_en.str
- bundle\interface_en.str
- bundle\client_messages_en.str
- bundle\game_messages_en.str
- bundle\bot_messages_en.str
