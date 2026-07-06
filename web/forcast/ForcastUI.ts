import { MeteoreShowerEvent } from './MeteoreShowerEvent'; // 调整路径

/**
 * 流星雨预报 UI 渲染器
 * 接受容器 ID 和事件数组，展示每个事件的预告信息
 */
export class ForecastUI {
  private container: HTMLElement;
  private events: MeteoreShowerEvent[];
  private listElement: HTMLElement;
  private updateTimer: number | null = null;

  // 流星 SVG 图标（内联，方便着色和缩放）
  private static readonly METEOR_SVG = `
    <svg width="53" height="46" viewBox="0 0 53 46" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M18.5928 45.2861C18.4638 45.4139 18.3401 45.4754 18.2354 45.4873C17.8958 45.5256 17.5817 45.4795 17.3789 45.3428C17.2165 45.2332 17.0305 45.0014 17.0674 44.4121C17.0768 44.2622 17.1634 44.0932 17.333 43.9443L40.167 23.9219L18.5928 45.2861ZM2.86914 44.5078C2.73828 44.6257 2.60375 44.6887 2.48145 44.7021C1.94129 44.7613 1.37629 44.6894 1.00293 44.4209C0.679301 44.1881 0.38323 43.7204 0.545898 42.6816C0.57239 42.5132 0.675695 42.3423 0.84668 42.2061L40.4141 10.6689L2.86914 44.5078ZM5.17383 26.8008C5.02633 26.9163 4.90451 26.9559 4.81543 26.9521C4.57882 26.9417 4.39308 26.8794 4.28711 26.7861C4.2102 26.7183 4.108 26.5773 4.15625 26.2148C4.17334 26.0867 4.26868 25.9351 4.46191 25.8018L21.1348 14.2988L5.17383 26.8008Z" fill="black" stroke="black"/>
    </svg>
  `;

  constructor(containerId: string, events: MeteoreShowerEvent[]) {
    const container = document.getElementById(containerId);
    if (!container) {
      throw new Error(`Container with id "${containerId}" not found.`);
    }
    this.container = container;
    this.events = events;

    // 创建列表容器
    this.listElement = document.createElement('div');
    this.listElement.className = 'forecast-list';
    this.container.appendChild(this.listElement);

    // 初次渲染
    this.render();

    // 每秒更新一次状态（倒计时）
    this.startAutoUpdate();
  }

  /**
   * 渲染所有事件项
   */
  private render(): void {
    this.listElement.innerHTML = '';
    if (this.events.length === 0) {
      this.listElement.innerHTML = '<p class="no-events">暂无流星雨预报</p>';
      return;
    }

    for (const event of this.events) {
      const item = this.createEventItem(event);
      this.listElement.appendChild(item);
    }
  }

  /**
   * 创建一个事件项的 DOM 元素
   */
  private createEventItem(event: MeteoreShowerEvent): HTMLElement {
    const item = document.createElement('div');
    item.className = 'event-item';
    item.dataset.eventId = event.dateTime; // 可用日期作为标识

    // 图标
    const iconWrapper = document.createElement('div');
    iconWrapper.className = 'event-icon';
    iconWrapper.innerHTML = ForecastUI.METEOR_SVG;
    // 使用 currentColor 继承父级颜色

    // 信息区
    const infoWrapper = document.createElement('div');
    infoWrapper.className = 'event-info';

    // 开始时间
    const startTime = document.createElement('div');
    startTime.className = 'event-start';
    const startDate = new Date(event.dateTime);
    startTime.textContent = `${this.formatDateTime(startDate)}`;
    // startTime.title = '会有流星雨!';

    // 持续时间
    const duration = document.createElement('div');
    duration.className = 'event-duration';
    duration.textContent = `持续 ${this.formatDuration(event.durationMs)}`;

    // 状态（倒计时/进行中/已结束）
    const status = document.createElement('div');
    status.className = 'event-status';
    status.dataset.statusKey = event.dateTime; // 用于更新时定位

    infoWrapper.appendChild(startTime);
    // infoWrapper.appendChild(duration);
    infoWrapper.appendChild(status);

    item.appendChild(iconWrapper);
    item.appendChild(infoWrapper);

    // 初始化状态
    this.updateEventStatus(status, event);

    return item;
  }

  /**
   * 更新单个事件的状态显示
   */
  private updateEventStatus(statusElement: HTMLDivElement, event: MeteoreShowerEvent): void {
    const now = Date.now();
    const start = new Date(event.dateTime).getTime();
    const end = start + event.durationMs;

    let statusText = '';
    let className = '';
    if (now < start) {
      const remaining = start - now;
      // statusText = `倒计时：${this.formatTimeRemaining(remaining)}`;
      className = 'status-pending';
    } else if (now >= start && now < end) {
      const elapsed = now - start;
      const total = event.durationMs;
      const remaining = total - elapsed;
      // const progress = Math.min(100, (elapsed / total) * 100);
      statusText = `${this.formatTimeRemaining(remaining)}`;
      // statusText = `${Math.round(progress)}%`;
      className = 'status-active';
    } else {
      // statusText = '已结束';
      className = 'status-ended';
    }
    statusElement.textContent = statusText;
    const targetAncestor = statusElement?.parentElement?.parentElement;
    if ( targetAncestor && targetAncestor.className !== '' && !targetAncestor.classList.contains(className)) {
      targetAncestor.classList.add('event-status');
      targetAncestor.classList.add(className);
    }
  }

  /**
   * 更新所有事件的状态（由定时器触发）
   */
  private updateAllStatuses(): void {
    const items = this.listElement.querySelectorAll('.event-item');
    for (const item of items) {
      const statusEl = item.querySelector('.event-status') as HTMLDivElement;
      if (!statusEl) continue;
      // 通过日期找到对应的事件
      const eventId = statusEl.dataset.statusKey;
      const event = this.events.find(e => e.dateTime === eventId);
      if (event) {
        this.updateEventStatus(statusEl, event);
      }
    }
  }

  /**
   * 开始自动更新（每秒）
   */
  private startAutoUpdate(): void {
    if (this.updateTimer) return;
    this.updateTimer = window.setInterval(() => {
      this.updateAllStatuses();
    }, 1000);
  }

  /**
   * 停止自动更新（可调用以释放资源）
   */
  public stopAutoUpdate(): void {
    if (this.updateTimer) {
      clearInterval(this.updateTimer);
      this.updateTimer = null;
    }
  }

  /**
   * 销毁 UI（清理定时器）
   */
  public destroy(): void {
    this.stopAutoUpdate();
    if (this.container.contains(this.listElement)) {
      this.container.removeChild(this.listElement);
    }
  }

  // ---------- 工具方法 ----------

  private formatDateTime(date: Date): string {
    return date.toLocaleString('zh-CN', {
      // year: 'numeric',
      // month: '2-digit',
      // day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  }

  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) return `${seconds} 秒`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes} 分 ${remainingSeconds} 秒`;
  }

  private padStart = (num: number) => {
    const prefix = num < 10 ? '0' : '';
    return `${prefix}${num}`;

  }

  private formatTimeRemaining(ms: number): string {
    if (ms <= 0) return '';
    const seconds = Math.floor(ms / 1000);

    if (seconds < 60) return `00:00:${this.padStart(seconds)}`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    if (minutes < 60) return `00:${this.padStart(minutes)}:${this.padStart(remainingSeconds)} `;
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return `${this.padStart(hours)}:${this.padStart(remainingMinutes)}:${this.padStart(remainingSeconds)}`;
  }
}