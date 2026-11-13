#!/usr/bin/env node
// Browserzugang zu SAP Concur (Variante A). Läuft nur auf dem Mac, in einem sichtbaren Fenster mit eigenem Profil.
//
// Feste Regeln:
//   - Die Anmeldung macht der Mensch. Dieses Skript füllt nie Passwort- oder MFA-Felder aus.
//   - Es betätigt nie eine Schaltfläche zum Senden oder Einreichen.
//   - Zugangsdaten werden nicht gespeichert; die Sitzung liegt im Browserprofil.
//
// Aufruf:
//   node concur.js anmelden --instanz https://eu2.concursolutions.com
//   node concur.js erkunden seite.json --instanz https://eu2.concursolutions.com
//
// Die Schritte zum Lesen und Schreiben der Abrechnungen sind noch nicht abgebildet: Dafür muss die echte
// Oberfläche einmal mit „erkunden“ aufgenommen werden. Auswahlpfade werden nicht geraten.
const fs = require('fs');
const os = require('os');
const path = require('path');

const regeln = JSON.parse(fs.readFileSync(path.join(__dirname, 'regeln.json'), 'utf8'));
const norm = (text) => (text || '').replace(/\s+/g, ' ').trim().toLowerCase();

class Verboten extends Error {}

/** Beschriftung eines Elements: sichtbarer Text, aria-label, title, value. */
async function beschriftung(locator) {
  return locator.evaluate((el) => [el.innerText, el.getAttribute('aria-label'), el.getAttribute('title'), el.value]
    .filter(Boolean).join(' | '));
}

/** Klickt nur, wenn die Beschriftung nichts mit Senden oder Einreichen zu tun hat. */
async function sichererKlick(locator) {
  const text = norm(await beschriftung(locator));
  const treffer = regeln.verboteneBeschriftungen.find((v) => text.includes(norm(v)));
  if (treffer) throw new Verboten(`Klick verweigert: „${text}“ enthält „${treffer}“. Eingereicht wird nie von der App.`);
  await locator.click();
}

/** Füllt ein Feld, aber nie Passwort-, Code- oder MFA-Felder. */
async function sicheresFuellen(locator, wert) {
  const merkmale = norm(await locator.evaluate((el) => [el.type, el.name, el.id, el.autocomplete, el.getAttribute('aria-label')]
    .filter(Boolean).join(' ')));
  const treffer = regeln.geheimeFelder.find((v) => merkmale.includes(v));
  if (treffer) throw new Verboten(`Eingabe verweigert: Feld „${merkmale}“ sieht nach Zugangsdaten aus. Die Anmeldung machst du selbst.`);
  await locator.fill(wert);
}

function istAngemeldet(adresse, instanz) {
  let url;
  try { url = new URL(adresse); } catch { return false; }
  if (url.host !== new URL(instanz).host) return false;
  const pfad = (url.pathname + url.search).toLowerCase();
  return !regeln.anmeldepfade.some((p) => pfad.includes(p));
}

/** Wartet, bis der Mensch sich angemeldet hat. Tippt nichts, klickt nichts. */
async function wartenAufAnmeldung(page, instanz, { maxSekunden = 600, schrittMs = 1000 } = {}) {
  let stabil = 0;
  for (let i = 0; i < (maxSekunden * 1000) / schrittMs; i += 1) {
    stabil = istAngemeldet(page.url(), instanz) ? stabil + 1 : 0;
    if (stabil >= 2) return true;
    await page.waitForTimeout(schrittMs);
  }
  return false;
}

/** Nimmt die Bedienelemente der aktuellen Seite auf, damit die Schritte daran abgebildet werden können. */
async function erkunden(page) {
  const elemente = await page.evaluate(() => {
    // Bei Eingabefeldern zählt nur die Beschriftung. Der eingetragene Wert wird nie gelesen.
    const feld = (el) => ['input', 'textarea', 'select'].includes(el.tagName.toLowerCase());
    const text = (el) => ((feld(el) ? '' : el.innerText) || el.getAttribute('aria-label') || el.getAttribute('placeholder')
      || el.getAttribute('title') || '').replace(/\s+/g, ' ').trim();
    return Array.from(document.querySelectorAll('button, a[href], input, select, textarea, [role=button], [role=tab], [role=menuitem]'))
      .filter((el) => el.offsetParent !== null)
      .map((el) => ({
        art: el.tagName.toLowerCase(), rolle: el.getAttribute('role'), typ: el.getAttribute('type'), id: el.id || null,
        name: el.getAttribute('name'), testid: el.getAttribute('data-test') || el.getAttribute('data-testid') || el.getAttribute('data-nuiexp'),
        text: text(el).slice(0, 120),
      }));
  });
  // Eingetragene Werte werden nicht aufgenommen, nur die Struktur.
  return { adresse: page.url().split('?')[0], titel: await page.title(), elemente };
}

async function fensterOeffnen(instanz, profil) {
  const { chromium } = require('playwright');
  const kontext = await chromium.launchPersistentContext(profil, { headless: false, viewport: null });
  const page = kontext.pages()[0] || await kontext.newPage();
  await page.goto(instanz);
  return { kontext, page };
}

async function main() {
  const [befehl, ...rest] = process.argv.slice(2);
  const wert = (name, ersatz) => { const i = rest.indexOf(name); return i >= 0 ? rest[i + 1] : ersatz; };
  const instanz = wert('--instanz', 'https://eu2.concursolutions.com');
  const profil = wert('--profil', path.join(os.homedir(), 'Library', 'Application Support', 'Reisemanager', 'concur-profil'));
  if (!['anmelden', 'erkunden'].includes(befehl)) {
    console.error('Aufruf: node concur.js anmelden|erkunden [Ausgabe.json] [--instanz URL] [--profil Ordner]');
    process.exit(2);
  }
  const { kontext, page } = await fensterOeffnen(instanz, profil);
  console.log('Bitte im Browserfenster selbst anmelden (SSO). Das Skript wartet und gibt nichts ein.');
  if (!await wartenAufAnmeldung(page, instanz)) {
    console.error('Keine Anmeldung innerhalb von 10 Minuten.');
    await kontext.close();
    process.exit(1);
  }
  console.log('Angemeldet.');
  if (befehl === 'erkunden') {
    const ziel = rest.find((a) => a.endsWith('.json')) || 'seite.json';
    console.log('Zur gewünschten Seite wechseln und hier die Eingabetaste drücken.');
    await new Promise((fertig) => process.stdin.once('data', fertig));
    fs.writeFileSync(ziel, JSON.stringify(await erkunden(page), null, 2));
    console.log(`Seitenstruktur gespeichert: ${ziel}`);
  }
  await kontext.close();
}

module.exports = { sichererKlick, sicheresFuellen, istAngemeldet, wartenAufAnmeldung, erkunden, Verboten, regeln };
if (require.main === module) main().catch((fehler) => { console.error(fehler.message); process.exit(1); });
