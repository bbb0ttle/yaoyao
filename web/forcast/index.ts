import { type MeteorShowerForcast } from "../types/forcast";
import { ForecastUI } from "./ForcastUI";
import { MeteoreShowerEvent } from "./MeteoreShowerEvent";

const getForcastDataKey = (): string => {
  const dt = new Date();
  const year = dt.getFullYear();
  const month = String(dt.getMonth() + 1).padStart(2, '0');
  const day = String(dt.getDate()).padStart(2, '0');
  const YYYYMMDD = `${year}${month}${day}`;
  return `meteor_shower_forcast_${YYYYMMDD}`;
};

const randomInt = (min: number, max: number): number =>
  Math.floor(Math.random() * (max - min + 1)) + min;

const randomFutureTimeInToday = (minTimeUtc?: number): string => {
  const nowUtc = Date.now();
  const offsetMs = 8 * 60 * 60 * 1000;

  const shanghaiNow = new Date(nowUtc + offsetMs);
  const year = shanghaiNow.getUTCFullYear();
  const month = shanghaiNow.getUTCMonth();
  const day = shanghaiNow.getUTCDate();

  const startUtc = Date.UTC(year, month, day - 1, 16, 0, 0, 0);
  const endUtc = Date.UTC(year, month, day, 15, 59, 59, 999);

  const minTime = Math.max(startUtc, nowUtc, minTimeUtc || 0);
  if (minTime >= endUtc) {
    const lastMoment = new Date(endUtc + offsetMs).toISOString().replace('Z', '+08:00');
    return lastMoment;
  }

  const randomUtc = minTime + Math.random() * (endUtc - minTime);
  const displayDate = new Date(randomUtc + offsetMs);
  return displayDate.toISOString().replace('Z', '+08:00');
};

export const generateForcastData = (num: number): MeteorShowerForcast => {
  const events: Array<{ dateTime: string; durationMs: number }> = [];
  const nowUtc = Date.now();
  const offsetMs = 8 * 60 * 60 * 1000;

  const shanghaiNow = new Date(nowUtc + offsetMs);
  const year = shanghaiNow.getUTCFullYear();
  const month = shanghaiNow.getUTCMonth();
  const day = shanghaiNow.getUTCDate();
  const endOfTodayUtc = Date.UTC(year, month, day, 15, 59, 59, 999);

  let lastEndUtc: number | null = null;

  for (let i = 0; i < num; i++) {
    const durationMs = randomInt(60_000, 1_800_000);

    let minStartUtc = nowUtc;
    if (lastEndUtc !== null) {
      const gapMs = randomInt(60_000, 300_000);
      minStartUtc = lastEndUtc + gapMs;
    }

    if (minStartUtc + durationMs > endOfTodayUtc) {
      break;
    }

    const dateTimeStr = randomFutureTimeInToday(minStartUtc);
    const startUtc = new Date(dateTimeStr).getTime();

    lastEndUtc = startUtc + durationMs;

    events.push({ dateTime: dateTimeStr, durationMs });
  }

  events.sort((a, b) => new Date(a.dateTime).getTime() - new Date(b.dateTime).getTime());
  return events;
};

const validateAndFixForecast = (
  data: MeteorShowerForcast,
  maxEvents?: number
): MeteorShowerForcast => {
  if (!data || data.length === 0) return [];

  const sorted = [...data].sort(
    (a, b) => new Date(a.dateTime).getTime() - new Date(b.dateTime).getTime()
  );

  const result: MeteorShowerForcast = [];
  let lastEndUtc: number = 0;

  for (const item of sorted) {
    const startUtc = new Date(item.dateTime).getTime();
    const endUtc = startUtc + item.durationMs;

    if (lastEndUtc !== null && startUtc < lastEndUtc) {
      const gapMs = randomInt(60_000, 120_000);
      const newStartUtc = lastEndUtc + gapMs;
      const offsetMs = 8 * 60 * 60 * 1000;
      const shanghaiNow = new Date(Date.now() + offsetMs);
      const year = shanghaiNow.getUTCFullYear();
      const month = shanghaiNow.getUTCMonth();
      const day = shanghaiNow.getUTCDate();
      const endOfTodayUtc = Date.UTC(year, month, day, 15, 59, 59, 999);
      if (newStartUtc + item.durationMs > endOfTodayUtc) {
        continue;
      }
      const newDate = new Date(newStartUtc + offsetMs);
      const newDateTime = newDate.toISOString().replace('Z', '+08:00');
      item.dateTime = newDateTime;
      lastEndUtc = newStartUtc + item.durationMs;
    } else {
      lastEndUtc = endUtc;
    }
    result.push(item);

    if (maxEvents !== undefined && result.length >= maxEvents) break;
  }

  return result;
};

export const ensureForcastData = (
  onFire: () => void,
  count: number = 3
): Array<MeteoreShowerEvent> => {
  const key = getForcastDataKey();
  let forecastData: MeteorShowerForcast | null = null;
  const ret: MeteoreShowerEvent[] = [];

  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      const parsed = JSON.parse(stored);
      if (
        Array.isArray(parsed) &&
        parsed.every(
          (item) =>
            typeof item === 'object' &&
            item !== null &&
            typeof item.dateTime === 'string' &&
            typeof item.durationMs === 'number'
        )
      ) {
        forecastData = validateAndFixForecast(parsed, count);
        if (JSON.stringify(forecastData) !== JSON.stringify(parsed)) {
          try {
            localStorage.setItem(key, JSON.stringify(forecastData));
            console.log('Forecast data was fixed and re-saved.');
          } catch (e) {
            console.error('Failed to save fixed forecast:', e);
          }
        }
      } else {
        console.warn('Stored forecast data has invalid format, will regenerate.');
      }
    }
  } catch (e) {
    console.error('Failed to read forecast from localStorage:', e);
  }

  if (!forecastData || forecastData.length === 0) {
    forecastData = generateForcastData(count);
    try {
      localStorage.setItem(key, JSON.stringify(forecastData));
      console.log(`Generated and saved new forecast (${forecastData.length} events) for today.`);
    } catch (e) {
      console.error('Failed to save forecast to localStorage:', e);
    }
  }

  if (forecastData && forecastData.length > 0) {
    for (const event of forecastData) {
      ret.push(new MeteoreShowerEvent(event.dateTime, event.durationMs, onFire));
    }
    console.log(`Started ${ret.length} meteor shower events.`);
  } else {
    console.warn('No forecast data available to start events.');
  }

  return ret;
};

export const showForcastUI = (containerID: string, onFire: () => void): ForecastUI => {
  return new ForecastUI(containerID, ensureForcastData(onFire))
}
