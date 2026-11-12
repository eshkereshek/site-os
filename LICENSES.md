# Лицензии сторонних компонентов

Проект Site OS не распространяет сторонние шрифты и пакеты в репозитории; они устанавливаются из репозиториев Debian/Ubuntu при сборке.

| Компонент | Использование | Лицензия |
|-----------|---------------|----------|
| VT323 (assets/fonts/VT323-Regular.ttf) | основной шрифт тем | SIL Open Font License 1.1 (текст assets/fonts/OFL-VT323.txt) |

| DejaVu Sans Mono (`fonts-dejavu-core`) | запасной шрифт для кириллицы | Bitstream Vera / DejaVu (свободная) |
| Linux Mint XFCE (ISO) | основа образа | GPL и лицензии пакетов Ubuntu/Mint (см. состав ISO) |
| XFCE (xfwm4, xfce4-panel, Thunar) | рабочая среда | GPL-2.0-or-later |
| jgmenu | меню (этап 2) | MIT |
| numpy, scipy, Pillow | генерация обоев | BSD / PIL License (свободные) |

Логотипы Linux Mint удаляются при сборке (`install.sh --step branding`). Сборка Site OS не использует проприетарных шрифтов.

Лицензии перечисленных пакетов не проверены в VM; перед публикацией ISO сверить `copyright`-файлы из `/usr/share/doc/*/copyright` внутри образа.
