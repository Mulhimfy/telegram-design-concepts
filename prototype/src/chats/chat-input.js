// Pointer input for the Chats tab, with the same safety as the Settings router
// (ui/input.js): a touch that ends without its pointerup reaching the page (a system
// gesture, the host app taking it) is ended as cancelled by the next first finger, a lost
// capture, or the page losing focus. Points go to the target in screen pt.

export function attachPointer(screen, { device, clock, target, enabled }) {
  let pointerId = null;
  let last = null;
  const point = (e) => {
    const r = screen.getBoundingClientRect();
    return [(e.clientX - r.left) * (device.width / r.width), (e.clientY - r.top) * (device.height / r.height)];
  };
  const abandon = () => {
    if (pointerId === null) return;
    pointerId = null;
    target.up(last || [0, 0], clock.now(), true);
  };
  screen.addEventListener('pointerdown', (e) => {
    if (pointerId !== null) {
      if (e.isPrimary && e.pointerId !== pointerId) abandon();
      else return;
    }
    if (!enabled()) return;
    e.preventDefault();
    try { screen.setPointerCapture(e.pointerId); } catch (_) {}
    pointerId = e.pointerId;
    last = point(e);
    target.down(last, clock.now());
  });
  screen.addEventListener('pointermove', (e) => {
    if (e.pointerId !== pointerId) return;
    const list = e.getCoalescedEvents ? e.getCoalescedEvents() : [];
    for (const ev of list.length ? list : [e]) {
      last = point(ev);
      target.move(last, clock.now());
    }
  });
  const end = (e) => {
    if (e.pointerId !== pointerId) return;
    pointerId = null;
    last = point(e);
    target.up(last, clock.now(), e.type === 'pointercancel');
  };
  screen.addEventListener('pointerup', end);
  screen.addEventListener('pointercancel', end);
  screen.addEventListener('lostpointercapture', (e) => { if (e.pointerId === pointerId) abandon(); });
  window.addEventListener('blur', abandon);
  document.addEventListener('visibilitychange', () => { if (document.hidden) abandon(); });
  return { get active() { return pointerId !== null; } };
}
