export interface IMeteorShowerEvent {
  dateTime: string;
  durationMs: number;

  onFire?: () => void;
}

export type MeteorShowerForcast = Array<IMeteorShowerEvent>
