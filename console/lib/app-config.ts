/**
 * What the console can set about the app (0119) - the same lists the database
 * checks, in one place both the form and the action read. A name here that the
 * app does not know is skipped by the app, never an error.
 */
export const APP_TILES = [
  'book',
  'add_money',
  'bookings',
  'bills',
  'refer',
  'birthday',
  'profile',
  'your_data',
  'search',
] as const;

export const APP_SECTIONS = ['categories', 'quick', 'services', 'wallet'] as const;

export const APP_SWITCHES = ['referrals', 'birthday', 'search', 'wallet_topup', 'announcements'] as const;

export const ANNOUNCEMENT_ICONS = ['campaign', 'event', 'celebration', 'info', 'schedule', 'new'] as const;

export const TILE_LABELS: Record<string, string> = {
  book: 'Book',
  add_money: 'Add money',
  bookings: 'My bookings',
  bills: 'Bills',
  refer: 'Refer & Earn',
  birthday: 'Birthday',
  profile: 'Edit profile',
  your_data: 'Your data',
  search: 'Search',
};

export const SECTION_LABELS: Record<string, string> = {
  categories: 'Categories with photos ("What are you looking for?")',
  quick: 'Tiles ("What would you like to do?")',
  services: 'Services row (photo cards)',
  wallet: 'Wallet balance card',
};

export const SWITCH_LABELS: Record<string, string> = {
  referrals: 'Refer & Earn (also needs the plan)',
  birthday: 'Birthday (tile, card and profile row)',
  search: 'Search bar and tile',
  wallet_topup: 'Adding money in the app',
  announcements: 'Announcements on the home screen',
};
