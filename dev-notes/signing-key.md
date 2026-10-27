# Ключ подписи: создание, установка, хранение

Ключ подписывает индексы APT-репозитория. Pi проверяет подпись и без неё
ничего не установит. Поэтому секретная часть ключа должна быть в двух местах:
в секрете GitHub (для workflow) и в резервной копии у вас. Больше нигде.

## 0. Где это делать

На своём компьютере или на самой Pi (`gnupg` в Raspberry Pi OS уже есть),
но не на GitHub. На Windows — в Git Bash (`gpg` входит в Git for Windows)
или в WSL. Все команды выполняются в одном окне терминала: переменная
`GNUPGHOME` действует только в нём.

## 1. Временное хранилище ключей

```sh
export GNUPGHOME="$(mktemp -d)"
```

Ключ создаётся не в вашем личном `~/.gnupg`, а в пустом временном каталоге.
Так он не смешается с личными ключами, и его потом легко удалить целиком.

## 2. Создать ключ

```sh
gpg --batch --passphrase '' --quick-gen-key "remoteplayer APT repository" ed25519 sign never
gpg --list-secret-keys --keyid-format long
```

- `ed25519` — короткий современный ключ, его понимает apt и в bookworm, и в trixie;
- `sign` — ключ годится только для подписи;
- `never` — без срока действия (почему — в [README.md](README.md));
- пустой пароль нужен, потому что workflow подписывает без человека.
  Защита ключа — секрет GitHub и зашифрованная резервная копия (шаг 5).

Вторая команда покажет строку из 40 шестнадцатеричных символов. Это
**отпечаток** (fingerprint). Запишите его: на шаге 9 по нему проверяется,
что на Pi попал именно ваш ключ.

## 3. Выгрузить ключ в файлы

```sh
gpg --armor --export-secret-keys > remoteplayer-apt-signing-key.asc
gpg --armor --export > remoteplayer-apt-public-key.asc
```

Первый файл — секретный ключ, его никому не показывать. Второй — публичный,
его не жалко: workflow и так публикует его на сайте.

## 4. Положить секретный ключ в GitHub

Репозиторий `endownment/remoteplayer-apt` → **Settings** →
**Secrets and variables** → **Actions** → **New repository secret**:

- Name: `APT_SIGNING_KEY`
- Secret: всё содержимое `remoteplayer-apt-signing-key.asc` (`cat
  remoteplayer-apt-signing-key.asc`), включая строки `-----BEGIN PGP PRIVATE
  KEY BLOCK-----` и `-----END ...-----`.

То же одной командой, если установлен GitHub CLI:
`gh secret set APT_SIGNING_KEY --repo endownment/remoteplayer-apt < remoteplayer-apt-signing-key.asc`.

GitHub хранит секрет зашифрованным. Прочитать его обратно нельзя, можно
только заменить. Он доступен workflow этого репозитория и не попадает в
форки и чужие pull request.

## 5. Резервная копия

```sh
gpg --symmetric --cipher-algo AES256 --output remoteplayer-apt-signing-key.asc.gpg remoteplayer-apt-signing-key.asc
```

gpg спросит пароль: придумайте надёжный и сохраните в менеджере паролей.
Файл `remoteplayer-apt-signing-key.asc.gpg` положите туда, где он
переживёт поломку компьютера: на флешку в ящике стола, в менеджер паролей
как вложение, в облако. Без пароля этот файл бесполезен, так что облако
допустимо.

Восстановить ключ из копии: `gpg --decrypt remoteplayer-apt-signing-key.asc.gpg > remoteplayer-apt-signing-key.asc`.

## 6. Убрать следы

```sh
shred -u remoteplayer-apt-signing-key.asc      # на macOS: rm -P, в Git Bash: rm
gpgconf --kill gpg-agent
rm -rf "$GNUPGHOME"
unset GNUPGHOME
```

После этого секретный ключ остаётся только в секрете GitHub и в
зашифрованной копии.

## 7. Включить Pages

Тот же репозиторий → **Settings** → **Pages** → **Build and deployment** →
Source: **GitHub Actions**.

## 8. Первый запуск

**Actions** → **publish** → **Run workflow**. Через пару минут откроется
<https://endownment.github.io/remoteplayer-apt/>. Пока у проектов
нет выпусков (тегов `vX.Y.Z`), репозиторий будет рабочим, но пустым.

Если упал шаг «Import the signing key», значит секрет не задан или вставлен
не целиком.

## 9. Проверка ключа на Pi

После первой команды установки (скачивание keyring) на Pi:

```sh
gpg --show-keys /usr/share/keyrings/remoteplayer-archive-keyring.gpg
```

Отпечаток должен совпасть с записанным на шаге 2. Это единственный момент,
когда приходится доверять скачиванию по сети. Дальше apt сам проверяет
каждый файл по этому ключу.

## 10. Токен для мгновенной публикации (необязательно)

Без него новый выпуск появится в репозитории при ежедневном запуске
(03:17 UTC). С ним — через несколько минут после тега.

1. GitHub → аватар → **Settings** → **Developer settings** → **Personal access
   tokens** → **Fine-grained tokens** → **Generate new token**.
2. Repository access: **Only select repositories** →
   `endownment/remoteplayer-apt`.
3. Permissions → Repository permissions → **Contents: Read and write**.
   Больше ничего не нужно.
4. Expiration — на ваш вкус. Когда токен истечёт, выпуск не сломается: шаг
   уведомления только выдаст предупреждение, а пакеты появятся при
   ежедневном запуске.
5. Скопируйте токен и добавьте его секретом `APT_REPOSITORY_TOKEN` в **оба**
   проекта: `remoteplayer-restservice` и `remoteplayer-mpvwatcher` (Settings →
   Secrets and variables → Actions).

## Если что-то пошло не так

- **Ключ утерян** (нет ни копии, ни пароля). Создайте новый (шаги 1–6) и
  замените секрет `APT_SIGNING_KEY`, затем запустите workflow. На каждой Pi
  заново скачайте keyring (первая команда установки из README) и проверьте
  отпечаток. До этого Pi будут отказываться обновляться с ошибкой подписи.
- **Ключ утёк.** Сделайте то же самое, и как можно скорее: с утёкшим ключом
  можно подсунуть Pi чужой пакет, если удастся подменить и сам сайт.
- **Ежедневный запуск отключён.** GitHub выключает расписание в публичных
  репозиториях без активности 60 дней и присылает письмо. Включается снова в
  Actions → publish → Enable workflow. Уведомления по токену работают
  независимо от расписания.
