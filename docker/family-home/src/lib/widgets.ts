export const widgets = [
  { id: "dinner", name: "Dinner tonight", description: "Tonight's meal, the next few dinners and a link to plan the week", size: "1x2" },
  { id: "shopping", name: "Shopping list", description: "Tick things off or add to the list", size: "1x2" },
  { id: "lights", name: "Lights", description: "Switch the lights and scenes", size: "1x2" },
  { id: "calendar", name: "This week", description: "What's on the calendar, with a button to add something", size: "3x1" },
  { id: "coming", name: "Coming this week", description: "New episodes and films from Sonarr and Radarr", size: "2x3" },
  { id: "photos", name: "On this day", description: "Photos from this day in past years, from Immich", size: "1x3" },
  { id: "cameras", name: "Cameras", description: "Live video from the Frigate cameras", size: "2x2" },
  { id: "meals", name: "Meal plan", description: "Every planned meal for the next seven days", size: "3x3" },
] as const;

// Columns by rows on a page's 3 by 3 grid.
export const sizes = ["1x1", "2x1", "3x1", "1x2", "2x2", "3x2", "1x3", "2x3", "3x3"] as const;
export type Size = (typeof sizes)[number];
export const isSize = (value: unknown): value is Size => sizes.includes(value as Size);

export type WidgetId = (typeof widgets)[number]["id"];

export const isWidget = (id: unknown): id is WidgetId => widgets.some((w) => w.id === id);
