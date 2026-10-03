---
name: aladhan-times
description: Aladhan Prayer Times API integration with calculation methods, schools, and Hijri calendar.
---

# Aladhan Prayer Times Skill

## Endpoint
`GET https://api.aladhan.com/v1/timings/{DD-MM-YYYY}?latitude={lat}&longitude={lon}&method={m}&school={s}`

## Parameters
- `latitude`: User latitude (e.g. 55.75 for Moscow)
- `longitude`: User longitude (e.g. 37.61 for Moscow)
- `method`: Calculation method:
  - `2`: Muslim World League (MWL) - default
  - `14`: Spiritual Administration of Muslims of Russia (ДУМ РФ)
  - `3`: Egyptian General Authority of Survey
  - `13`: Diyanet İşleri Başkanlığı (Turkey)
  - `1`: University of Islamic Sciences, Karachi
- `school`: Asr juristic calculation:
  - `1`: Hanafi (shadow factor 2) - default
  - `0`: Shafi'i / Standard (shadow factor 1)

## Response Parsing
- Timings:
  - `timings.Fajr`: Dawn prayer
  - `timings.Sunrise`: Sunrise time (end of Fajr)
  - `timings.Dhuhr`: Midday prayer
  - `timings.Asr`: Afternoon prayer
  - `timings.Maghrib`: Sunset prayer
  - `timings.Isha`: Night prayer
- Hijri Date:
  - `date.hijri.day`: Day of Islamic lunar month
  - `date.hijri.month.en` / `date.hijri.month.ar`: Islamic month name
  - `date.hijri.year`: Islamic year (AH)
  - `date.gregorian.date`: Gregorian date DD-MM-YYYY
