---
name: qibla-math
description: Spherical trigonometry calculations for Qibla bearing direction and Haversine distance to the Kaaba.
---

# Qibla Math Skill

## Constants
- Kaaba coordinates:
  - Latitude: `21.422487` (°N)
  - Longitude: `39.826206` (°E)
- Earth mean radius: `6371` km

## Formulas

### 1. Initial Bearing (Forward Azimuth)
To compute the true initial direction (bearing) towards the Kaaba from observer coordinates (`lat`, `lon`):

```js
const toR = d => d * Math.PI / 180;
const toD = r => r * 180 / Math.PI;

const lat1 = toR(lat);
const lon1 = toR(lon);
const lat2 = toR(21.422487);
const lon2 = toR(39.826206);

const dLon = lon2 - lon1;

const y = Math.sin(dLon) * Math.cos(lat2);
const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);

const bearing = (toD(Math.atan2(y, x)) + 360) % 360;
```

### 2. Great-Circle Distance (Haversine Formula)
Distance in kilometers:

```js
const dLat = lat2 - lat1;
const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
const distance = Math.round(2 * 6371 * Math.asin(Math.sqrt(a)));
```

### 3. Compass Relative Angle
Given phone compass heading `heading` (degrees clockwise from North, 0° = N, 90° = E):
- Relative deviation to Qibla: `delta = (qibla - heading + 360) % 360`
- Aligned threshold: `delta < 8 || delta > 352` (within ±8° of Kaaba).
