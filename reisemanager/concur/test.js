// Prüft die Sicherheitsregeln des Browserzugangs an einer nachgestellten Seite. Kein Zugriff auf Concur.
const test = require('node:test');
const assert = require('node:assert');
const { chromium } = require('playwright');
const { sichererKlick, sicheresFuellen, istAngemeldet, wartenAufAnmeldung, erkunden, Verboten } = require('./concur.js');

const seite = `<html><head><title>Abrechnung Test</title></head><body>
  <button id="speichern" onclick="document.body.dataset.gespeichert = '1'">Position speichern</button>
  <button id="senden" onclick="document.body.dataset.gesendet = '1'">Abrechnung senden</button>
  <button id="symbol" aria-label="Submit Report" onclick="document.body.dataset.gesendet = '1'">➤</button>
  <a id="link" href="#x" title="Einreichen">weiter</a>
  <input id="lieferant" name="vendor" value="geheim"><input id="pw" type="password" name="password">
  <input id="mfa" name="otpCode" autocomplete="one-time-code"><button style="display:none">Unsichtbar</button>
</body></html>`;

test('Sicherheitsregeln des Browserzugangs', async (t) => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setContent(seite);
  t.after(() => browser.close());

  await t.test('erlaubte Schaltfläche wird geklickt', async () => {
    await sichererKlick(page.locator('#speichern'));
    assert.equal(await page.evaluate(() => document.body.dataset.gespeichert), '1');
  });

  await t.test('Senden wird nie geklickt, auch nicht über aria-label oder title', async () => {
    for (const id of ['#senden', '#symbol', '#link']) {
      await assert.rejects(sichererKlick(page.locator(id)), Verboten);
    }
    assert.equal(await page.evaluate(() => document.body.dataset.gesendet), undefined);
  });

  await t.test('Passwort- und MFA-Felder werden nie ausgefüllt', async () => {
    await sicheresFuellen(page.locator('#lieferant'), 'Hotel Muster');
    assert.equal(await page.inputValue('#lieferant'), 'Hotel Muster');
    await assert.rejects(sicheresFuellen(page.locator('#pw'), 'x'), Verboten);
    await assert.rejects(sicheresFuellen(page.locator('#mfa'), '123456'), Verboten);
    assert.equal(await page.inputValue('#pw'), '');
    assert.equal(await page.inputValue('#mfa'), '');
  });

  await t.test('Anmeldung wird nur erkannt, nicht ausgeführt', async () => {
    const instanz = 'https://eu2.concursolutions.com';
    assert.equal(istAngemeldet('https://eu2.concursolutions.com/home', instanz), true);
    assert.equal(istAngemeldet('https://eu2.concursolutions.com/nui/signin', instanz), false);
    assert.equal(istAngemeldet('https://login.example.com/saml/sso', instanz), false);
    assert.equal(istAngemeldet('about:blank', instanz), false);
    assert.equal(await wartenAufAnmeldung(page, instanz, { maxSekunden: 1, schrittMs: 200 }), false, 'ohne Anmeldung läuft die Wartezeit ab');
  });

  await t.test('Erkunden nimmt die Struktur auf, aber keine eingetragenen Werte', async () => {
    const bild = await erkunden(page);
    assert.equal(bild.titel, 'Abrechnung Test');
    assert.ok(bild.elemente.some((e) => e.text === 'Position speichern'));
    assert.ok(!bild.elemente.some((e) => e.text === 'Unsichtbar'));
    assert.ok(!JSON.stringify(bild).includes('Hotel Muster'), 'Feldinhalte gehören nicht in die Aufnahme');
  });
});
