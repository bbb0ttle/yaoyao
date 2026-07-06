export interface IMeteorShowerEvent {
  dateTime: string;
  durationMs: string;
}

export type MeteorShowerForcast = Array<IMeteorShowerEvent>