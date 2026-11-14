## Projekt erstellen

Aktuell funtioniert vite als bundler am Besten.

``` cmd
npm create vite@latest
```

Dann die folgenden Eintragungen machen:
    - project name = web_barcodescanner
    - type = vanilla - javascript

``` cmd
cd web_barcodescanner
npm install
```

Um die Barcode-Library hinzuzufügen, NPM verwenden:

``` cmd
// https://blog.minhazav.dev/research/html5-qrcode.html
npm i html5-qrcode
```

## Anpassungen

**WICHTIG** Vite erzeugt ein komisches Layout - da muss man ein bisschen was umbiegen.
In Package.json sollte das `build` kommando mit `"vite build --base=/<projektname>/dist/"` geändert werden,
dann kann man in OGS mehrere Webpages parallel bauen!

## zum Testen

Build mit watch und Test-Webserver. Hinweis: man kann im OGS auch die vite-Server-URL eintragen (zum Testen)

``` cmd
npm run dev
```

## Build (für production)

``` cmd
npm run build
```

Das erstellt dann die gebundelten Dateien in ../dist

