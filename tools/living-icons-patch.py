#!/usr/bin/env python3
# Builds ios/patches/0003-living-icons.patch against Telegram-iOS f1dd7a2 (master, 2026-10-07):
#   · the module: ios/LivingSettingsIcons/{BUILD,Sources} → submodules/TelegramUI/Components/PeerInfo/LivingSettingsIcons
#   · the glue: ios/LivingSettingsIcons/PeerInfoScreen/PeerInfoSettingsLivingIcons.swift → PeerInfoScreen/Sources
#   · the hooks (HOOKS below): small edits of PeerInfoScreen's BUILD, controller, settings actions and row nodes.
# The pristine files are read from PRISTINE_DIR if set (a checkout at f1dd7a2), else fetched from GitHub at f1dd7a2.
# usage: python3 tools/living-icons-patch.py > ios/patches/0003-living-icons.patch
import difflib
import os
import sys
import urllib.parse
import urllib.request

COMMIT = 'f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838'
RAW = 'https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/' + COMMIT + '/'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE = 'submodules/TelegramUI/Components/PeerInfo/LivingSettingsIcons'
SCREEN = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen'


def pristine(path):
    local = os.environ.get('PRISTINE_DIR')
    if local:
        with open(os.path.join(local, path), encoding='utf-8') as f:
            return f.read()
    with urllib.request.urlopen(RAW + urllib.parse.quote(path)) as r:
        return r.read().decode('utf-8')


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8') as f:
        return f.read()


# Each hook: (file, anchor, replacement); the anchor must occur exactly once in the pristine file.
HOOKS = [
    # The module, among the PeerInfo components PeerInfoScreen depends on.
    (SCREEN + '/BUILD',
     '        "//submodules/TelegramUI/Components/PeerInfo/VerifyAlertController",\n',
     '        "//submodules/TelegramUI/Components/PeerInfo/VerifyAlertController",\n'
     '        "//submodules/TelegramUI/Components/PeerInfo/LivingSettingsIcons",\n'),
    # The node keeps the Living Icons state (created only when Settings uses it).
    (SCREEN + '/Sources/PeerInfoScreen.swift',
     '    lazy var hapticFeedback = { HapticFeedback() }()\n',
     '    lazy var hapticFeedback = { HapticFeedback() }()\n'
     '    /// Settings icons that come alive when you come back from their page (PeerInfoSettingsLivingIcons.swift).\n'
     '    lazy var livingIcons = PeerInfoSettingsLivingIcons()\n'),
    # Settings comes back (a pop starts, or a swipe back starts) / goes away (a row's page is pushed).
    (SCREEN + '/Sources/PeerInfoScreen.swift',
     '    override public func viewWillDisappear(_ animated: Bool) {\n'
     '        super.viewWillDisappear(animated)\n'
     '\n'
     '        self.controllerNode.logoutConfirmationDisposable.set(nil)\n',
     '    override public func viewWillAppear(_ animated: Bool) {\n'
     '        super.viewWillAppear(animated)\n'
     '        \n'
     '        self.controllerNode.livingIconsWillAppear(animated: animated)\n'
     '    }\n'
     '    \n'
     '    override public func viewWillDisappear(_ animated: Bool) {\n'
     '        super.viewWillDisappear(animated)\n'
     '\n'
     '        self.controllerNode.livingIconsWillDisappear()\n'
     '        self.controllerNode.logoutConfirmationDisposable.set(nil)\n'),
    # Settings is shown again: the end of a pop, or of a swipe back.
    (SCREEN + '/Sources/PeerInfoScreen.swift',
     '    override public func viewDidAppear(_ animated: Bool) {\n'
     '        super.viewDidAppear(animated)\n'
     '        \n',
     '    override public func viewDidAppear(_ animated: Bool) {\n'
     '        super.viewDidAppear(animated)\n'
     '        \n'
     '        self.controllerNode.livingIconsDidAppear()\n'
     '        \n'),
    # The one place that knows which row was opened.
    (SCREEN + '/Sources/PeerInfoScreenSettingsActions.swift',
     '    func openSettings(section: PeerInfoSettingsSection) {\n',
     '    func openSettings(section: PeerInfoSettingsSection) {\n'
     '        self.livingIconsWillOpen(section: section)\n'
     '        \n'),
    # The rows' static icons.
    (SCREEN + '/Sources/ListItems/PeerInfoScreenDisclosureItem.swift',
     '        return height\n    }\n}\n',
     '        return height\n    }\n}\n'
     '\n'
     'extension PeerInfoScreenDisclosureItemNode: PeerInfoScreenLivingIconItemNode {\n'
     '    var livingIconImageNode: ASImageNode? {\n'
     '        return self.iconNode.supernode != nil ? self.iconNode : nil\n'
     '    }\n'
     '}\n'),
    (SCREEN + '/Sources/ListItems/PeerInfoScreenActionItem.swift',
     '        return height\n    }\n}\n',
     '        return height\n    }\n}\n'
     '\n'
     'extension PeerInfoScreenActionItemNode: PeerInfoScreenLivingIconItemNode {\n'
     '    var livingIconImageNode: ASImageNode? {\n'
     '        return self.iconNode.supernode != nil ? self.iconNode : nil\n'
     '    }\n'
     '}\n'),
]


def new_file(path, content):
    lines = content.splitlines(keepends=True)
    out = ['diff --git a/%s b/%s\n' % (path, path), 'new file mode 100644\n', '--- /dev/null\n', '+++ b/%s\n' % path]
    out.append('@@ -0,0 +1,%d @@\n' % len(lines))
    out.extend('+' + line for line in lines)
    if lines and not lines[-1].endswith('\n'):
        out.append('\n\\ No newline at end of file\n')
    return ''.join(out)


def changed_file(path, old, new):
    diff = list(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True), 'a/' + path, 'b/' + path, n=3))
    return 'diff --git a/%s b/%s\n' % (path, path) + ''.join(diff)


def main():
    files = {}
    # The module.
    files[MODULE + '/BUILD'] = (None, read('ios/LivingSettingsIcons/BUILD'))
    for name in sorted(os.listdir(os.path.join(ROOT, 'ios/LivingSettingsIcons/Sources'))):
        if name.endswith('.swift'):
            files[MODULE + '/Sources/' + name] = (None, read('ios/LivingSettingsIcons/Sources/' + name))
    # The glue.
    files[SCREEN + '/Sources/PeerInfoSettingsLivingIcons.swift'] = (None, read('ios/LivingSettingsIcons/PeerInfoScreen/PeerInfoSettingsLivingIcons.swift'))
    # The hooks.
    edited = {}
    for path, anchor, replacement in HOOKS:
        if path not in edited:
            edited[path] = pristine(path)
        text = edited[path]
        count = text.count(anchor)
        if count != 1:
            sys.exit('%s: anchor found %d times: %r' % (path, count, anchor[:60]))
        edited[path] = text.replace(anchor, replacement)
    for path, text in edited.items():
        files[path] = (pristine(path), text)

    out = []
    for path in sorted(files):
        old, new = files[path]
        out.append(new_file(path, new) if old is None else changed_file(path, old, new))
    sys.stdout.write(''.join(out))


main()
