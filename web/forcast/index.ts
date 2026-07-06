// 假设类型定义在 "../types/forcast" 中
import { type MeteorShowerForcast } from "../types/forcast";
import { ForecastUI } from "./ForcastUI";
import { MeteoreShowerEvent } from "./MeteoreShowerEvent"; // 你的事件类

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

// 假设其他依赖（randomInt, MeteorShowerForcast, MeteoreShowerEvent 等）已定义

/**
 * 生成一个东八区今天内的未来随机时间，但必须 >= minTimeUtc（UTC时间戳）
 * @param minTimeUtc 最小允许的 UTC 时间戳（毫秒），默认为当前时间
 * @returns 格式如 "2026-07-06T14:23:45.678+08:00"
 */
const randomFutureTimeInToday = (minTimeUtc?: number): string => {
  const nowUtc = Date.now();
  const offsetMs = 8 * 60 * 60 * 1000;

  // 东八区当前日期
  const shanghaiNow = new Date(nowUtc + offsetMs);
  const year = shanghaiNow.getUTCFullYear();
  const month = shanghaiNow.getUTCMonth();
  const day = shanghaiNow.getUTCDate();

  // 今天 00:00:00.000 东八区 → UTC 昨天 16:00:00.000
  const startUtc = Date.UTC(year, month, day - 1, 16, 0, 0, 0);
  // 今天 23:59:59.999 东八区 → UTC 今天 15:59:59.999
  const endUtc = Date.UTC(year, month, day, 15, 59, 59, 999);

  const minTime = Math.max(startUtc, nowUtc, minTimeUtc || 0);
  if (minTime >= endUtc) {
    // 如果已无时间余量，返回今天最后一刻
    const lastMoment = new Date(endUtc + offsetMs).toISOString().replace('Z', '+08:00');
    return lastMoment;
  }

  const randomUtc = minTime + Math.random() * (endUtc - minTime);
  const displayDate = new Date(randomUtc + offsetMs);
  return displayDate.toISOString().replace('Z', '+08:00');
};

/**
 * 生成指定数量的流星雨预报事件数据，保证有序且不重叠
 * @param num 期望事件个数（实际可能少于该值，若时间不足）
 * @returns 有序的事件数组（按开始时间升序）
 */
export const generateForcastData = (num: number): MeteorShowerForcast => {
  const events: Array<{ dateTime: string; durationMs: number }> = [];
  const nowUtc = Date.now();
  const offsetMs = 8 * 60 * 60 * 1000;

  // 获取今天结束时间 UTC
  const shanghaiNow = new Date(nowUtc + offsetMs);
  const year = shanghaiNow.getUTCFullYear();
  const month = shanghaiNow.getUTCMonth();
  const day = shanghaiNow.getUTCDate();
  const endOfTodayUtc = Date.UTC(year, month, day, 15, 59, 59, 999);

  let lastEndUtc: number | null = null; // 上一个事件的结束时间（UTC）

  for (let i = 0; i < num; i++) {
    // 随机持续时间：1~30 分钟
    const durationMs = randomInt(60_000, 1_800_000);

    // 计算该事件允许的最早开始时间
    let minStartUtc = nowUtc;
    if (lastEndUtc !== null) {
      // 与前一个事件间隔 1~5 分钟
      const gapMs = randomInt(60_000, 300_000);
      minStartUtc = lastEndUtc + gapMs;
    }

    // 检查是否还有足够时间容纳该事件（至少需要持续时长）
    if (minStartUtc + durationMs > endOfTodayUtc) {
      // 剩余时间不足，停止生成
      break;
    }

    // 生成随机开始时间（保证 >= minStartUtc 且在今天之内）
    const dateTimeStr = randomFutureTimeInToday(minStartUtc);
    const startUtc = new Date(dateTimeStr).getTime(); // 解析带时区字符串得到 UTC 时间戳

    // 更新 lastEndUtc
    lastEndUtc = startUtc + durationMs;

    events.push({ dateTime: dateTimeStr, durationMs });
  }

  // 按开始时间排序（虽然顺序生成已有序，但做一次保险）
  events.sort((a, b) => new Date(a.dateTime).getTime() - new Date(b.dateTime).getTime());
  return events;
};

/**
 * 校验并修复预报数据：排序、移除重叠（后移或丢弃）
 * @param data 原始数据
 * @param maxEvents 最多保留事件数（可选）
 * @returns 修复后的数据（有序且不重叠）
 */
const validateAndFixForecast = (
  data: MeteorShowerForcast,
  maxEvents?: number
): MeteorShowerForcast => {
  if (!data || data.length === 0) return [];

  // 1. 按开始时间排序
  const sorted = [...data].sort(
    (a, b) => new Date(a.dateTime).getTime() - new Date(b.dateTime).getTime()
  );

  const result: MeteorShowerForcast = [];
  let lastEndUtc: number = 0;

  for (const item of sorted) {
    const startUtc = new Date(item.dateTime).getTime();
    const endUtc = startUtc + item.durationMs;

    // 若与上一个事件重叠，则调整开始时间到上一个事件结束 + 小间隔
    if (lastEndUtc !== null && startUtc < lastEndUtc) {
      // 将开始时间推后到 lastEndUtc + 随机间隔（1~2分钟）
      const gapMs = randomInt(60_000, 120_000);
      const newStartUtc = lastEndUtc + gapMs;
      // 检查新时间是否超出今天结束，若是则丢弃该事件
      const offsetMs = 8 * 60 * 60 * 1000;
      const shanghaiNow = new Date(Date.now() + offsetMs);
      const year = shanghaiNow.getUTCFullYear();
      const month = shanghaiNow.getUTCMonth();
      const day = shanghaiNow.getUTCDate();
      const endOfTodayUtc = Date.UTC(year, month, day, 15, 59, 59, 999);
      if (newStartUtc + item.durationMs > endOfTodayUtc) {
        continue; // 无法调整，丢弃
      }
      // 重新生成时间字符串
      const newDate = new Date(newStartUtc + offsetMs);
      const newDateTime = newDate.toISOString().replace('Z', '+08:00');
      item.dateTime = newDateTime;
      // 更新 end
      lastEndUtc = newStartUtc + item.durationMs;
    } else {
      lastEndUtc = endUtc;
    }
    result.push(item);

    // 若达到了最大事件数，停止
    if (maxEvents !== undefined && result.length >= maxEvents) break;
  }

  return result;
};

/**
 * 确保今天已经生成预报数据，如果没有则生成并存入 localStorage，
 * 然后启动所有事件（实例化 MeteorShowerEvent）
 * @param onFire 所有事件共享的回调函数（流星出现时调用）
 * @param count 期望生成的事件数量（若时间不足实际可能更少）
 * @returns 实例化的事件数组
 */
export const ensureForcastData = (
  onFire: () => void,
  count: number = 3
): Array<MeteoreShowerEvent> => {
  const key = getForcastDataKey();
  let forecastData: MeteorShowerForcast | null = null;
  const ret: MeteoreShowerEvent[] = [];

  // 1. 尝试从 localStorage 读取
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
        // 校验并修复（排序、去重叠）
        forecastData = validateAndFixForecast(parsed, count);
        // 若修复后数据与原始不同，可以重新保存（可选）
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

  // 2. 如果没有有效数据，生成新的并保存
  if (!forecastData || forecastData.length === 0) {
    forecastData = generateForcastData(count);
    try {
      localStorage.setItem(key, JSON.stringify(forecastData));
      console.log(`Generated and saved new forecast (${forecastData.length} events) for today.`);
    } catch (e) {
      console.error('Failed to save forecast to localStorage:', e);
    }
  }

  // 3. 实例化所有事件并启动（构造函数会自动调度）
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