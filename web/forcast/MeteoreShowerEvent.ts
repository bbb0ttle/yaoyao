import { IMeteorShowerEvent } from "../types/forcast";

export class MeteoreShowerEvent implements IMeteorShowerEvent {
  // 公共属性
  dateTime: string;
  durationMs: number;
  onFire?: () => void;

  // 私有状态
  private _startTime: number = 0;      // 开始时间戳
  private _endTime: number = 0;        // 结束时间戳
  private _timer: ReturnType<typeof setTimeout> | null = null; // 当前定时器
  private _isActive: boolean = false;  // 是否正在运行

  constructor(dateTime: string, durationMs: number, onFire?: () => void) {
    this.dateTime = dateTime;
    this.durationMs = durationMs;
    this.onFire = onFire;

    const startDate = new Date(dateTime);
    if (isNaN(startDate.getTime())) {
      console.error('Invalid dateTime provided, event will not start.');
      return;
    }

    this._startTime = startDate.getTime();
    this._endTime = this._startTime + durationMs;
    this._scheduleStart();
  }

  /**
   * 计划在开始时间触发第一次启动
   */
  private _scheduleStart(): void {
    const now = Date.now();
    const delay = this._startTime - now;

    if (delay <= 0) {
      // 如果已经开始（或已过期），立即启动（但会检查是否过期）
      this._start();
    } else {
      this._timer = setTimeout(() => this._start(), delay);
    }
  }

  /**
   * 启动事件循环（在开始时间到达时调用）
   */
  private _start(): void {
    // 再次检查是否在有效时间窗口内
    const now = Date.now();
    if (now < this._startTime || now >= this._endTime) {
      // 已经过期或还未开始，停止
      this._stop();
      return;
    }

    // 激活事件
    this._isActive = true;

    // 执行第一次触发（立即）
    this._fire();

    // 开始循环随机触发
    this._scheduleNext();
  }

  /**
   * 调度下一次随机触发
   */
  private _scheduleNext(): void {
    if (!this._isActive) return;

    const now = Date.now();
    const remaining = this._endTime - now;
    if (remaining <= 0) {
      this._stop();
      return;
    }

    // 随机等待时间：例如 0 ~ 5000ms，但不超过剩余时间
    const maxWait = Math.min(2000, remaining);
    const waitTime = Math.random() * maxWait;

    this._timer = setTimeout(() => {
      if (this._isActive) {
        this._fire();
        this._scheduleNext(); // 递归调度下一次
      }
    }, waitTime);
  }

  /**
   * 触发 onFire 回调（如果存在）
   */
  private _fire(): void {
    if (this.onFire) {
      try {
        this.onFire();
      } catch (err) {
        console.error('Error in onFire callback:', err);
      }
    }
  }

  /**
   * 停止所有定时器，结束事件
   */
  private _stop(): void {
    this._isActive = false;
    if (this._timer) {
      clearTimeout(this._timer);
      this._timer = null;
    }
  }

  /**
   * 外部取消事件（可提前停止）
   */
  public cancel(): void {
    this._stop();
    console.log('Event cancelled.');
  }
}