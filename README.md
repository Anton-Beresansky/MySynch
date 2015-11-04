# MySynch
Task#1.
Приложение для сохранения данных с одного сервера на другой.
Сервер хранящий копии данных (ведущий) по расписанию инициирует процесс сбора данных на ряде серверов (ведомые).
Сервера которые хранят сами данные, по запросу от ведущего передают ему копии запрошенного файла или папки (если это папка то ее копирование происходит рекурсивно).

1. Список ведомых серверов записан в скрипте который выполняется по расписанию на ведущем.
2. Папка подлежащая копированию задается как аргумент командной строки для скрипта сбора данных.
3. После получения копии ведущий проверяет все ли данные были скопированы и их целостность.
4. Использовать можно ssh с ключами, имя пользователя и пароль нигде не должны фигурировать, только ключи.
5. Копии данных сохраняются на ведущем в месте, которое указано как переменная в скрипте сбора данных.
6. Скрипты как на ведущем так и на ведомом должны выполнятся от имени отдельного пользователя.
7. Если копирование занимает больше 5 минут оно должно быть прервано.
