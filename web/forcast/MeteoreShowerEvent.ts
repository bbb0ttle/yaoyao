import { IMeteorShowerEvent } from "../types/forcast";

export class MeteoreShowerEvent implements IMeteorShowerEvent {
  dateTime: string;
  durationMs: number;
  onFire?: () => void;

  private _startTime: number = 0;
  private _endTime: number = 0;
  private _timer: ReturnType<typeof setTimeout> | null = null;
  private _isActive: boolean = false;

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

  private _scheduleStart(): void {
    const now = Date.now();
    const delay = this._startTime - now;

    if (delay <= 0) {
      this._start();
    } else {
      this._timer = setTimeout(() => this._start(), delay);
    }
  }

  private _start(): void {
    const now = Date.now();
    if (now < this._startTime || now >= this._endTime) {
      this._stop();
      return;
    }

    this._isActive = true;
    this._fire();
    this._scheduleNext();
  }

  private _scheduleNext(): void {
    if (!this._isActive) return;

    const now = Date.now();
    const remaining = this._endTime - now;
    if (remaining <= 0) {
      this._stop();
      return;
    }

    const maxWait = Math.min(2000, remaining);
    const waitTime = Math.random() * maxWait;

    this._timer = setTimeout(() => {
      if (this._isActive) {
        this._fire();
        this._scheduleNext();
      }
    }, waitTime);
  }

  private _fire(): void {
    if (this.onFire) {
      try {
        this.onFire();
      } catch (err) {
        console.error('Error in onFire callback:', err);
      }
    }
  }

  private _stop(): void {
    this._isActive = false;
    if (this._timer) {
      clearTimeout(this._timer);
      this._timer = null;
    }
  }

  public cancel(): void {
    this._stop();
    console.log('Event cancelled.');
  }
}
