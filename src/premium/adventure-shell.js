export const HONEYCOMB_ADVENTURE_SHELL_VERSION = "2026.05.25-premium-adventure-v1";

export const ADVENTURE_REGIONS = [
  { id: "creation", name: "Creation", tone: "garden", books: ["Genesis"] },
  { id: "patriarchs", name: "Patriarchs", tone: "desert", books: ["Genesis"] },
  { id: "exodus", name: "Exodus", tone: "sea", books: ["Exodus", "Leviticus", "Numbers", "Deuteronomy"] },
  { id: "kingdom", name: "Kingdom", tone: "gold", books: ["Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles"] },
  { id: "exile", name: "Exile", tone: "night", books: ["Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel"] },
  { id: "gospel", name: "Gospel", tone: "sunrise", books: ["Matthew", "Mark", "Luke", "John"] },
  { id: "church", name: "Church", tone: "fire", books: ["Acts", "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation"] },
];

export function installAdventureShell() {
  document.documentElement.dataset.shell = "premium-adventure";
  document.documentElement.dataset.shellVersion = HONEYCOMB_ADVENTURE_SHELL_VERSION;
}

installAdventureShell();
