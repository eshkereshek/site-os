# Site OS

Site OS — тёмная ретро-оболочка для Linux Mint XFCE (тема, обои, панель, меню). Образ собирается из оригинального ISO Linux Mint XFCE без ручной установки темы.

> Статус: скрипты написаны и синтаксически проверены в Windows-окружении. **Сборка и загрузка ISO не проверены в VM.**

## Что делает сборка

1. `scripts/build_iso.sh <linuxmint-xfce.iso>` распаковывает ISO и squashfs.
2. В chroot запускается `install.sh --step all` (шрифт Unscii, обои, GTK и xfwm4 тема, конфиги в `/etc/skel`, брендинг Site OS, кэши).
3. Очистка chroot, пересборка squashfs (xz), обновление `filesystem.manifest`, `filesystem.size`, `md5sum.txt`.
4. Сборка ISO с BIOS и UEFI загрузкой, на выходе `out/SITEOS.iso` и `out/SITEOS.iso.sha256`.

Оригинальный ISO скрипт не скачивает: путь передаётся аргументом.

## Требования

- Хост: Linux x86_64 (Ubuntu / Linux Mint), права root.
- Место на диске: около 25 ГБ свободно для ISO Mint XFCE (~3 ГБ) и рабочих каталогов (распакованная файловая система ~10 ГБ, новый squashfs ~3–4 ГБ, итоговый ISO ~4 ГБ). Не проверено в VM.
- Время: распаковка и пересборка squashfs с xz занимают от 30 до 90 минут на 4-ядерной машине; `install.sh` в chroot — 5–15 минут (зависит от сети). Не проверено в VM.
- Интернет: нужен для `apt` внутри chroot.

## Пакеты

```bash
sudo apt install squashfs-tools xorriso rsync p7zip-full xz-utils \
  debootstrap qemu-system-x86 qemu-utils ovmf
```

- `squashfs-tools`: `unsquashfs`, `mksquashfs`
- `xorriso`: распаковка и сборка ISO
- `rsync`: копирование репозитория в chroot
- `p7zip-full`: запасной распаковщик ISO
- `debootstrap`: не используется в текущем пути сборки, нужен только если вы строите базу с нуля (не проверено в VM)
- `qemu-system-x86`, `ovmf`: проверка в `scripts/test_iso.sh` (`ovmf` нужен для UEFI)

## Сборка

```bash
git clone https://github.com/eshkereshek/site-os.git ~/RansomOS
cd ~/RansomOS
sudo ./scripts/build_iso.sh ~/Downloads/linuxmint-22-xfce-64bit.iso
```

Рабочие файлы: `build/work/`. Результат: `out/SITEOS.iso`. Скрипт при ошибке размонтирует всё, что смонтировал; каталог `build/work` остаётся для разбора.

## Проверка в QEMU

```bash
./scripts/test_iso.sh              # BIOS
./scripts/test_iso.sh --uefi       # UEFI (нужен ovmf)
```

Скрипт требует `/dev/kvm`. Не проверено в VM.

## Установка темы без сборки ISO

На уже установленной Linux Mint XFCE (в VM или на тестовой машине):

```bash
sudo ./install.sh --help
sudo ./install.sh --step all 2>&1 | tee ~/site-os-install.log
```

Шаги: `fonts`, `wallpaper`, `gtk-theme`, `xfwm4-theme`, `xfce-config`, `branding`, `cache`. Установка идемпотентна. Настройки пишутся в `/etc/skel`, поэтому применяются к новым пользователям; для текущего пользователя скопируйте `~/.config` из `/etc/skel` или выйдите и войдите снова.

## Статус проверки

| Что | Статус |
|-----|--------|
| Синтаксис bash-скриптов | проверено (`bash -n`) |
| Распаковка и сборка ISO | не проверено в VM |
| `install.sh` в chroot | не проверено в VM |
| Шрифт Unscii и кириллица | не проверено в VM (`fc-list :lang=ru`) |
| Прозрачность рамки xfwm4 | не проверено в VM |
| Полосы treeview в GTK 3 | не проверено в VM |
| Загрузка BIOS и UEFI в QEMU | не проверено в VM |
| Брендинг (os-release, GRUB, isolinux) | не проверено в VM |

Оформление, размеры и цвета сверяются с референсами в `assets/reference/` (в репозиторий не входят).

## Лицензии

См. [LICENSES.md](LICENSES.md).
