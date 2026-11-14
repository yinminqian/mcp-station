// JXA:查看(可选:激活)某个 pid 的窗口状态。不需要辅助功能权限。
// 用法:osascript -l JavaScript winstate.js <pid> [activate]
ObjC.import('AppKit');
ObjC.import('CoreGraphics');
function run(argv) {
  const pid = parseInt(argv[0], 10);
  const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid);
  if (argv[1] === 'activate') { app.activateWithOptions(1 << 1); delay(0.8); }
  const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1 /* onScreenOnly */, 0)));
  const mine = list.filter(w => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0);
  const firstNormal = list.find(w => w.kCGWindowLayer === 0);
  const b = mine.length ? mine[0].kCGWindowBounds : null;
  return `active=${app.active} onscreen_windows=${mine.length}` +
    (b ? ` bounds=${b.X},${b.Y},${b.Width}x${b.Height}` : '') +
    ` topmost_normal_window_owner=${firstNormal ? firstNormal.kCGWindowOwnerName + '(' + firstNormal.kCGWindowOwnerPID + ')' : '?'}`;
}
