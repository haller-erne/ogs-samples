## Projekt erstellen

Aktuell funtioniert vite als bundler am Besten.

``` cmd
npm create vite@latest
```

Dann die folgenden Eintragungen machen:
    - project name = web_barcodedetector
    - type = vanilla - javascript

``` cmd
cd web_barcodedetector
npm install
```

Um die Barcode-Library hinzuzufügen, NPM verwenden:

``` cmd
npm install
```

Der Barcode-Detektor und die passende WebAssembly-Version sind in `package.json`
festgelegt. Vite bindet die WebAssembly-Datei lokal ein; eine CDN-Verbindung
ist zur Laufzeit nicht erforderlich.

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

