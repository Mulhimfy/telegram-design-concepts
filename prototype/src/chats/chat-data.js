// The chats on the demo list: invented, neutral (no real people, no faces). Letter avatars
// use Telegram's gradients (AvatarNode.gradientColors: dark → light, light at the top);
// photo avatars reuse the back-photo picker's Unsplash images (objects and places).

export const AVATAR_GRADIENTS = [
  ['#ff516a', '#ff885e'], // red
  ['#ffa85c', '#ffcd6a'], // orange
  ['#665fff', '#82b1ff'], // violet
  ['#54cb68', '#a0de7e'], // green
  ['#4acccd', '#00fcfd'], // cyan
  ['#2a9ef1', '#72d5fd'], // blue
  ['#d669ed', '#e0a2f3'], // pink
];

export const CHATS = [
  { id: 'design', title: 'Design Crew', kind: 'group', photo: 'pick-2.jpg', author: 'Max', text: 'The new swipe feels unreal, letters actually have depth now 🔥', date: '9:41', unread: 3, pinned: true },
  { id: 'telegram', title: 'Telegram', kind: 'service', verified: true, text: 'Your login code: 41-207. Do not give this code to anyone, even if they say they are from Telegram!', date: '9:12', pinned: true },
  { id: 'alex', title: 'Alex Turner', kind: 'user', avatar: 5, text: 'Sent you the files, check when you can', date: '8:57', unread: 1 },
  { id: 'hike', title: 'Weekend Hike', kind: 'group', photo: 'pick-5.jpg', author: 'Leo', text: 'Meet at 7 at the parking lot, bring water and the good snacks', date: '8:30', muted: true, unread: 12 },
  { id: 'news', title: 'Tech Notes', kind: 'channel', photo: 'pick-8.jpg', text: 'iOS 26.1 is out: here is everything that changed for developers', date: '7:45', muted: true },
  { id: 'omar', title: 'Omar', kind: 'user', avatar: 3, text: 'Deal. Tomorrow at 10 then 👍', date: 'Yesterday', out: 'read' },
  { id: 'saved', title: 'Saved Messages', kind: 'saved', text: 'image_2026-10-12.png', date: 'Yesterday' },
  { id: 'books', title: 'Book Club', kind: 'group', avatar: 2, author: 'Daniel', text: 'Next one is Project Hail Mary, vote in the poll', date: 'Sun' },
  { id: 'mark', title: 'Mark Chen', kind: 'user', avatar: 0, text: 'Voice message', textColor: 'accent', date: 'Sat', out: 'read' },
  { id: 'wallet', title: 'Wallet', kind: 'bot', avatar: 4, verified: true, text: 'You received 25 TON from @mark', date: 'Fri' },
  { id: 'studio', title: 'Studio Builds', kind: 'channel', photo: 'pick-3.jpg', text: 'Build 812 passed all checks and is rolling out to beta', date: 'Thu', muted: true },
  { id: 'ryan', title: 'Ryan', kind: 'user', avatar: 1, text: 'Haha that is exactly what I said', date: 'Wed' },
  { id: 'family', title: 'Home', kind: 'group', photo: 'pick-6.jpg', author: 'Sam', text: 'Who is picking up the groceries today?', date: 'Tue' },
  { id: 'jonas', title: 'Jonas', kind: 'user', avatar: 6, text: 'See you there', date: 'Mon', out: 'sent' },
];

export function initials(title) {
  const words = title.replace(/[^\p{L}\p{N}\s]/gu, '').trim().split(/\s+/);
  return ((words[0]?.[0] || '') + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase();
}
