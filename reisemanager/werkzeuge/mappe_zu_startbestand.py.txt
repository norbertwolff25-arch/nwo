#!/usr/bin/env python3
"""Wandelt die Arbeitsmappe Reisen_<Jahr>_vNN.xlsx in den Startbestand (JSON) für den Reisemanager.

Aufruf:
    python3 mappe_zu_startbestand.py Reisen_2026.xlsx startbestand.json

Die Ausgabe enthält persönliche Daten und bleibt lokal. Beträge stehen als ganze Cent.
Ein Betrag von 0,00 in der Mappe ist ein Platzhalter für „fehlt noch“ und wird leer übernommen.
Unbekannte Kostenarten brechen den Lauf ab, statt geraten zu werden.
"""
import json
import re
import sys
from datetime import date, datetime
from decimal import Decimal

from openpyxl import load_workbook


def text(wert):
    if wert is None:
        return None
    s = str(wert).strip()
    return s or None


def tag(wert):
    """Datum als JJJJ-MM-TT oder None (z. B. bei der Jahresangabe „2026“)."""
    if isinstance(wert, (datetime, date)):
        return wert.strftime("%Y-%m-%d")
    s = text(wert)
    if s and re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        return s
    return None


def cent(wert):
    """Betrag in Cent; 0 und leer ergeben None (Betrag fehlt)."""
    if wert is None or wert == "":
        return None
    if isinstance(wert, str):
        s = wert.strip().replace("€", "").replace(" ", "").strip()
        if "," in s and "." in s:
            s = s.replace(".", "").replace(",", ".") if s.rfind(",") > s.rfind(".") else s.replace(",", "")
        else:
            s = s.replace(",", ".")
        wert = Decimal(s)
    else:
        wert = Decimal(str(wert))
    c = int((wert * 100).quantize(Decimal("1")))
    return c or None


def kostenart(wert):
    s = (text(wert) or "").lower()
    if s.startswith("fahrt + unterkunft"):
        return "paket"
    for anfang, art in (("fahrt", "fahrt"), ("unterkunft", "unterkunft"), ("verpflegung", "verpflegung"), ("sonstiges", "sonstiges")):
        if s.startswith(anfang):
            return art
    raise SystemExit(f"Unbekannte Kostenart: {wert!r}")


def tabelle(blatt, kopfspalte):
    """Zeilen unter der Kopfzeile, die mit `kopfspalte` beginnt, als Wörterbücher."""
    zeilen = list(blatt.iter_rows(values_only=True))
    for i, zeile in enumerate(zeilen):
        if zeile and text(zeile[0]) == kopfspalte:
            kopf = [text(z) for z in zeile]
            return [dict(zip(kopf, z)) for z in zeilen[i + 1:] if z and any(v is not None for v in z)], zeilen[:i]
    raise SystemExit(f"Blatt {blatt.title}: Kopfzeile mit „{kopfspalte}“ nicht gefunden")


def beleg_spalte(wert):
    """„NP26-00858“ → Zahlung; „B28, B30“ → Belege; alles andere bleibt Hinweis."""
    s = text(wert)
    if not s:
        return None, [], None
    if re.fullmatch(r"NP\d{2}-\d+", s):
        return s, [], None
    teile = [t.strip() for t in s.split(",")]
    if all(re.fullmatch(r"B\d{2,}", t) for t in teile):
        return None, teile, None
    return None, [], s


def blatt_finden(mappe, anfang):
    for name in mappe.sheetnames:
        if name.startswith(anfang):
            return mappe[name]
    return None


def wandeln(pfad):
    mappe = load_workbook(pfad, data_only=True)
    jahr = int(re.search(r"(20\d\d)", pfad.split("/")[-1]).group(1))
    aus = {"jahr": jahr, "quelle": pfad.split("/")[-1], "reisen": [], "positionen": [], "privat": [],
           "offenePosten": [], "sachkosten": [], "belege": []}

    blatt = blatt_finden(mappe, "B_Belegverzeichnis")
    if blatt:
        for z in tabelle(blatt, "Beleg-Nr")[0]:
            nr = text(z.get("Beleg-Nr"))
            if nr and re.fullmatch(r"B\d{2,}", nr):
                aus["belege"].append({"nr": nr, "dokument": text(z.get("Dokument")) or "", "art": text(z.get("Art")),
                                      "fundort": text(z.get("Fundort / ID")), "belegt": text(z.get("Belegt")),
                                      "status": text(z.get("Status"))})

    blatt = blatt_finden(mappe, "1_Dienstreisen")
    for z in tabelle(blatt, "Nr")[0]:
        nr = text(z.get("Nr"))
        if not nr or not re.fullmatch(r"D\d+", nr):
            continue  # Summenzeile
        aus["reisen"].append({"nr": nr, "anlass": text(z.get("Anlass")) or "", "beginn": tag(z.get("Beginn")),
                              "ende": tag(z.get("Ende")), "verkehrsmittel": text(z.get("Verkehrsmittel")),
                              "unterkunft": text(z.get("Unterkunft")), "offen": text(z.get("Offen"))})

    blatt = blatt_finden(mappe, "2_Positionen")
    for z in tabelle(blatt, "Reise")[0]:
        zahlung, belege, hinweis = beleg_spalte(z.get("Beleg-ID"))
        aus["positionen"].append({"reise": text(z.get("Reise")), "datum": tag(z.get("Datum")), "quelle": text(z.get("Quelle")),
                                  "kostenart": kostenart(z.get("Kostenart")), "kostenartText": text(z.get("Kostenart")),
                                  "haendler": text(z.get("Händler")) or "", "betragCent": cent(z.get("Betrag EUR")),
                                  "zahlungId": zahlung, "belege": belege, "belegHinweis": hinweis})

    blatt = blatt_finden(mappe, "3_Privat")
    if blatt:
        for z in tabelle(blatt, "Nr")[0]:
            aus["privat"].append({"nr": text(z.get("Nr")), "reise": text(z.get("Reise")) or "", "beginn": tag(z.get("Beginn")),
                                  "ende": tag(z.get("Ende")), "hinweis": text(z.get("Hinweis"))})

    blatt = blatt_finden(mappe, "4_Uber_Bolt")
    if blatt:
        for z in tabelle(blatt, "Datum")[0]:
            zahlung, _, hinweis = beleg_spalte(z.get("Beleg-ID"))
            aus["offenePosten"].append({"datum": tag(z.get("Datum")), "quelle": "Uber/Bolt offen", "kostenart": "fahrt",
                                        "haendler": text(z.get("Händler")) or "", "betragCent": cent(z.get("Betrag EUR")),
                                        "zahlungId": zahlung, "belegHinweis": hinweis,
                                        "vorschlag": text(z.get("Vorschlag")) or "offen"})

    for name in mappe.sheetnames:
        treffer = re.match(r"(S\d+)_", name)
        if not treffer:
            continue
        blatt = mappe[name]
        kopfspalte = "Nr" if any(z and text(z[0]) == "Nr" for z in blatt.iter_rows(values_only=True)) else "Datum"
        zeilen, davor = tabelle(blatt, kopfspalte)
        titel = text(davor[0][0]) if davor else name
        hinweis = text(davor[1][0]) if len(davor) > 1 else None
        positionen = []
        for z in zeilen:
            datum = tag(z.get("Datum"))
            haendler = text(z.get("Tankstelle")) or text(z.get("Händler")) or text(z.get("Anbieter"))
            if datum is None and (haendler is None or haendler.lower() in ("summe", "offen")) and cent(z.get("Betrag EUR")) is not None:
                continue  # Summenzeile
            if datum is None and haendler is None:
                continue
            positionen.append({"datum": datum, "quelle": text(z.get("Zahlungsmittel")), "kostenart": "sonstiges",
                               "kostenartText": text(z.get("Leistung")), "haendler": haendler or "offen",
                               "ort": text(z.get("Ort")), "betragCent": cent(z.get("Betrag EUR")),
                               "belegHinweis": text(z.get("Beleg"))})
        aus["sachkosten"].append({"nr": treffer.group(1), "titel": titel or name, "hinweis": hinweis, "positionen": positionen})
    return aus


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    ergebnis = wandeln(sys.argv[1])
    with open(sys.argv[2], "w", encoding="utf-8") as datei:
        json.dump(ergebnis, datei, ensure_ascii=False, indent=2)
    print(f"{len(ergebnis['reisen'])} Reisen, {len(ergebnis['positionen'])} Positionen, {len(ergebnis['privat'])} Privatreisen, "
          f"{len(ergebnis['sachkosten'])} Sachkostenabrechnungen, {len(ergebnis['belege'])} Belege → {sys.argv[2]}")
