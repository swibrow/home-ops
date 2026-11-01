export const widgets = [
  { id: "dinner", name: "Dinner tonight", description: "Tonight's meal, the next few dinners and a link to plan the week" },
  { id: "shopping", name: "Shopping list", description: "Tick things off or add to the list" },
  { id: "lights", name: "Lights", description: "Switch the lights and scenes" },
  { id: "calendar", name: "This week", description: "What's on the calendar, with a button to add something" },
  { id: "coming", name: "Coming this week", description: "New episodes and films from Sonarr and Radarr", wide: true },
  { id: "photos", name: "On this day", description: "Photos from this day in past years, from Immich" },
  { id: "meals", name: "Meal plan", description: "Every planned meal for the next seven days", wide: true },
] as const;

export type WidgetId = (typeof widgets)[number]["id"];

export const isWidget = (id: unknown): id is WidgetId => widgets.some((w) => w.id === id);
