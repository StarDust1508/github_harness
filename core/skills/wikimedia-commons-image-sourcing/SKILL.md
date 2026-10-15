---
name: wikimedia-commons-image-sourcing
description: Доставать публичные фото мест/объектов через Wikimedia Commons, когда стоки типа Unsplash режут ботов или не дают прямые ссылки.
version: 1.0.0
author: Hermes
license: MIT
metadata:
  hermes:
    tags: [images, wikimedia, commons, city-photos, sourcing]
---

# Wikimedia Commons image sourcing

Используй, когда нужно быстро прислать пользователю фото города, места, здания, памятника или другого публичного объекта, а обычные фотостоки/поиск блокируют доступ.

## Когда применять

- Пользователь просит: "пришли фото X"
- Нужно найти легально переиспользу��мое публичное изображение
- Unsplash/другие сайты дают anti-bot / access denied
- Нужна прямая ссылка на картинку для отправки в чат

## Рабочий маршрут

1. Открой Wikimedia Commons media search:
   `https://commons.wikimedia.org/w/index.php?search=<QUERY>&title=Special:MediaSearch&go=Go&type=image`

2. Если запрос про город/место, предпочитай `Special:MediaSearch`, а не category page.
   MediaSearch обычно сразу даёт кликабельные результаты с файлами.

3. Кликни по релевантному результату.

4. Сразу вызови `browser_get_images`.
   На странице/оверлее Wikimedia часто уже лежит usable `upload.wikimedia.org` URL.

5. Выбирай:
   - `upload.wikimedia.org/...` вместо декоративных/иконок
   - максимально крупную версию
   - кадр, который действительно представляет объект, а не архивный/случайный

6. Отправляй пользователю изображение markdown-ссылкой:
   `![alt](DIRECT_URL)`

## Что сработало на практике

- Unsplash может вернуть `Access denied` / anti-bot; не трать время, сразу уходи в Commons.
- На Commons после клика по результату `browser_get_images` может вернуть и thumbnail, и большой `upload.wikimedia.org` файл; бери большой.
- Даже если `browser_click` открывает оверлей, а не отдельную file page, `browser_get_images` всё равно часто хватает для получения прямой ссылки.

## Fallback

Если MediaSearch не дал хороший кадр:
1. Открой `Category:<QUERY>` на Commons.
2. Найди визуально/по ссылкам подходящий файл.
3. После клика снова используй `browser_get_images`.

## Проверка

Перед отправкой проверь:
- это реально нужный объект/город
- ссылка ведёт на изображение, а не HTML-страницу
- разрешение не микроскопическое
- нет явных watermark/скриншотов интерфейса
